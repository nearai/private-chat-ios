import Foundation

enum FileServiceError: LocalizedError, Equatable {
    case fileTooLarge
    case localTableTooLarge
    case unreadableLocalTable(String)
    case unreadableSpreadsheet(kind: String, filename: String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "Files must be 10 MB or smaller."
        case .localTableTooLarge:
            return "CSV/TSV tables kept on-device must be 2 MB or smaller. Export the needed rows or paste the table."
        case let .unreadableLocalTable(filename):
            return "Could not read table rows from \(filename). Nothing was uploaded."
        case let .unreadableSpreadsheet(kind, filename):
            return "Could not read \(kind) rows from \(filename). Nothing was uploaded."
        }
    }
}

struct StagedDocumentText: Equatable {
    var attachmentID: String
    var text: String
}

struct FileAttachmentUploadResult {
    var attachment: ChatAttachment
    var notice: String?
    var stagedDocumentText: StagedDocumentText?
}

final class FileService {
    private let fileAPI: FileAPI

    init(fileAPI: FileAPI) {
        self.fileAPI = fileAPI
    }

    func remoteFiles() async throws -> [RemoteFileInfo] {
        try await fileAPI.fetchFiles().data.sorted {
            ($0.createdAt ?? 0) > ($1.createdAt ?? 0)
        }
    }

    func remoteFilePreview(_ file: RemoteFileInfo) async throws -> RemoteFilePreview {
        let metadata = (try? await fileAPI.fetchFile(file.id)) ?? file
        let data = try await fileAPI.fetchFilePreviewContent(file.id, maxBytes: APIClient.maxFilePreviewBytes)
        return RemoteFilePreview(file: metadata, data: data, maxPreviewBytes: APIClient.maxFilePreviewBytes)
    }

    func deleteRemoteFile(_ fileID: String) async throws {
        try await fileAPI.deleteFile(fileID)
    }

    func uploadTextFile(filename: String, text: String) async throws -> ChatAttachment {
        try await fileAPI.uploadTextFile(filename: filename, text: text)
    }

    func uploadFile(from url: URL) async throws -> ChatAttachment {
        try await fileAPI.uploadFile(from: url)
    }

    /// Downloads an uploaded extracted-text file (e.g. "…-pdf-text.txt") so its
    /// content can be re-staged after an app restart — staged document text is
    /// in-memory only, which previously meant project files attached in an
    /// earlier session reached the model as a bare filename.
    func fetchFileText(_ fileID: String) async throws -> String? {
        let data = try await fileAPI.fetchFilePreviewContent(fileID, maxBytes: APIClient.maxFilePreviewBytes)
        return String(data: data, encoding: .utf8)
    }

    /// Fetches the full raw bytes of an uploaded file. Used for image thumbnails
    /// in sent message bubbles.
    func fetchFileContent(_ fileID: String) async throws -> Data {
        try await fileAPI.fetchFileContent(fileID)
    }

    func uploadAttachment(from url: URL, keepDocumentsOnDevice: Bool) async throws -> FileAttachmentUploadResult {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let fileSize, fileSize > APIClient.maxUploadBytes {
            throw FileServiceError.fileTooLarge
        }

        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "csv" || fileExtension == "tsv" {
            return try await uploadDelimitedTable(
                from: url,
                fileSize: fileSize,
                keepDocumentsOnDevice: keepDocumentsOnDevice
            )
        }
        if fileExtension == "xlsx" || fileExtension == "xls" {
            return try await uploadSpreadsheet(
                from: url,
                fileSize: fileSize,
                keepDocumentsOnDevice: keepDocumentsOnDevice
            )
        }
        if fileExtension == "pdf",
           let pdfResult = try await uploadExtractedPDF(
            from: url,
            fileSize: fileSize,
            keepDocumentsOnDevice: keepDocumentsOnDevice
           ) {
            return pdfResult
        }

        let imageText = await VisionTextExtractor.extractedImageTextIfAvailable(from: url, fileExtension: fileExtension)
        var attachment = try await fileAPI.uploadFile(from: url)
        let stagedText = imageText.map { text -> StagedDocumentText in
            let cappedText = String(text.prefix(AttachmentStagingStore.maxStagedDocumentChars))
            return StagedDocumentText(attachmentID: attachment.id, text: cappedText)
        }
        if stagedText != nil {
            attachment.kind = attachment.kind.isEmpty ? "image" : attachment.kind
        }
        return FileAttachmentUploadResult(
            attachment: attachment,
            notice: stagedText == nil ? nil : "Attached \(url.lastPathComponent) and staged readable text from the image.",
            stagedDocumentText: stagedText
        )
    }

    private func uploadDelimitedTable(
        from url: URL,
        fileSize: Int?,
        keepDocumentsOnDevice: Bool
    ) async throws -> FileAttachmentUploadResult {
        if let extraction = DocumentTextExtractor.extractedDelimitedTableText(from: url, fileSize: fileSize) {
            return try await uploadExtractedTable(
                extraction,
                sourceURL: url,
                fileSize: fileSize,
                keepDocumentsOnDevice: keepDocumentsOnDevice,
                sourceKind: "table rows"
            )
        }
        if DocumentTextExtractor.shouldKeepDelimitedTableOnDevice(
            fileExtension: url.pathExtension.lowercased(),
            keepDocumentsOnDevice: keepDocumentsOnDevice
        ) {
            if let fileSize, fileSize > DocumentTextExtractor.maxLocalTableBytes {
                throw FileServiceError.localTableTooLarge
            }
            throw FileServiceError.unreadableLocalTable(url.lastPathComponent)
        }
        return FileAttachmentUploadResult(
            attachment: try await fileAPI.uploadFile(from: url),
            notice: nil,
            stagedDocumentText: nil
        )
    }

    private func uploadSpreadsheet(
        from url: URL,
        fileSize: Int?,
        keepDocumentsOnDevice: Bool
    ) async throws -> FileAttachmentUploadResult {
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "xlsx",
           let extraction = DocumentTextExtractor.extractedSpreadsheetTableText(from: url, fileSize: fileSize) {
            return try await uploadExtractedTable(
                extraction,
                sourceURL: url,
                fileSize: fileSize,
                keepDocumentsOnDevice: keepDocumentsOnDevice,
                sourceKind: "workbook rows"
            )
        }
        if keepDocumentsOnDevice {
            let kind = fileExtension == "xls" ? "Legacy XLS" : "XLSX"
            throw FileServiceError.unreadableSpreadsheet(kind: kind, filename: url.lastPathComponent)
        }
        let notice = fileExtension == "xls"
            ? "Attached legacy spreadsheet. For local row extraction, export XLSX, CSV, or TSV."
            : "Attached spreadsheet. Local row extraction was unavailable, so the workbook was uploaded as a file."
        return FileAttachmentUploadResult(
            attachment: try await fileAPI.uploadFile(from: url),
            notice: notice,
            stagedDocumentText: nil
        )
    }

    private func uploadExtractedTable(
        _ extraction: DocumentTextExtractor.TableTextExtractionResult,
        sourceURL: URL,
        fileSize: Int?,
        keepDocumentsOnDevice: Bool,
        sourceKind: String
    ) async throws -> FileAttachmentUploadResult {
        let cappedText = String(extraction.text.prefix(AttachmentStagingStore.maxStagedDocumentChars))
        if keepDocumentsOnDevice {
            let localID = "local-table-\(UUID().uuidString)"
            let sourcePrefix = sourceKind == "workbook rows" ? "workbook rows" : "table rows"
            let notice = extraction.truncated
                ? "Kept capped \(sourcePrefix) from \(sourceURL.lastPathComponent) on your device."
                : "Kept \(sourcePrefix) from \(sourceURL.lastPathComponent) on your device."
            return FileAttachmentUploadResult(
                attachment: ChatAttachment(
                    id: localID,
                    name: sourceURL.lastPathComponent,
                    kind: ChatAttachment.localTableKind,
                    bytes: fileSize
                ),
                notice: notice,
                stagedDocumentText: StagedDocumentText(attachmentID: localID, text: cappedText)
            )
        }

        let extractedFilename = DocumentTextExtractor.extractedTableFilename(for: sourceURL)
        do {
            var attachment = try await fileAPI.uploadTextFile(
                filename: extractedFilename,
                text: extraction.text
            )
            attachment.name = extractedFilename
            attachment.kind = "table_text"
            let sourcePrefix = sourceKind == "workbook rows" ? "workbook rows" : "table rows"
            let notice = extraction.truncated
                ? "Attached capped \(sourcePrefix) from \(sourceURL.lastPathComponent)."
                : "Attached \(sourcePrefix) from \(sourceURL.lastPathComponent)."
            return FileAttachmentUploadResult(
                attachment: attachment,
                notice: notice,
                stagedDocumentText: StagedDocumentText(attachmentID: attachment.id, text: cappedText)
            )
        } catch {
            let localID = "local-table-\(UUID().uuidString)"
            let sourcePrefix = sourceKind == "workbook rows" ? "workbook rows" : "table rows"
            return FileAttachmentUploadResult(
                attachment: ChatAttachment(
                    id: localID,
                    name: sourceURL.lastPathComponent,
                    kind: ChatAttachment.localTableKind,
                    bytes: fileSize
                ),
                notice: "Could not upload \(sourceURL.lastPathComponent), so \(sourcePrefix) are kept on-device for this session.",
                stagedDocumentText: StagedDocumentText(attachmentID: localID, text: cappedText)
            )
        }
    }

    private func uploadExtractedPDF(
        from url: URL,
        fileSize: Int?,
        keepDocumentsOnDevice: Bool
    ) async throws -> FileAttachmentUploadResult? {
        guard fileSize == nil || fileSize! <= DocumentTextExtractor.maxPDFTextExtractionBytes else {
            let attachment = try await fileAPI.uploadFile(from: url)
            return FileAttachmentUploadResult(
                attachment: attachment,
                notice: "Attached \(url.lastPathComponent) as a PDF file. Text extraction runs only for PDFs up to 5 MB.",
                stagedDocumentText: nil
            )
        }
        guard let fileSize else {
            let attachment = try await fileAPI.uploadFile(from: url)
            return FileAttachmentUploadResult(
                attachment: attachment,
                notice: "Attached \(url.lastPathComponent) as a PDF file. Text extraction was skipped because the file size could not be verified.",
                stagedDocumentText: nil
            )
        }
        guard let extraction = await DocumentTextExtractor.extractPDFText(from: url, fileSize: fileSize) else {
            let attachment = try await fileAPI.uploadFile(from: url)
            return FileAttachmentUploadResult(
                attachment: attachment,
                notice: "Attached \(url.lastPathComponent) as a PDF file. Text extraction timed out or found no readable text.",
                stagedDocumentText: nil
            )
        }

        let cappedText = String(extraction.text.prefix(AttachmentStagingStore.maxStagedDocumentChars))
        if keepDocumentsOnDevice {
            let localID = "local-doc-\(UUID().uuidString)"
            return FileAttachmentUploadResult(
                attachment: ChatAttachment(
                    id: localID,
                    name: url.lastPathComponent,
                    kind: ChatAttachment.localDocumentKind,
                    bytes: fileSize
                ),
                notice: "Kept \(url.lastPathComponent) on your device — only the passages relevant to your question are sent.",
                stagedDocumentText: StagedDocumentText(attachmentID: localID, text: cappedText)
            )
        }

        let extractedFilename = DocumentTextExtractor.extractedPDFFilename(for: url)
        var attachment = try await fileAPI.uploadTextFile(
            filename: extractedFilename,
            text: extraction.text
        )
        attachment.name = extractedFilename
        attachment.kind = "pdf_text"
        let notice = extraction.truncated
            ? "Attached capped readable text from \(url.lastPathComponent)."
            : "Attached readable text from \(url.lastPathComponent)."
        return FileAttachmentUploadResult(
            attachment: attachment,
            notice: notice,
            stagedDocumentText: StagedDocumentText(attachmentID: attachment.id, text: cappedText)
        )
    }
}
