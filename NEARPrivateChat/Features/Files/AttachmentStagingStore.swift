import Foundation

struct PromptAttachmentResolution {
    var attachments: [ChatAttachment]
    var uploadedAttachments: [ChatAttachment]
}

@MainActor
final class AttachmentStagingStore: ObservableObject {
    nonisolated static let maxStagedDocumentChars = 200_000
    nonisolated static let maxStagedDocuments = 8

    @Published private(set) var pendingAttachments: [ChatAttachment] = []
    @Published var isUploadingAttachment = false

    private(set) var pendingLargePasteTexts: [String: String] = [:]
    private(set) var pendingSharedFileURLs: [String: URL] = [:]
    private var pendingDocumentTexts: [String: String] = [:]
    private var pendingDocumentTextIDs: [String] = []

    var onDurableStateChange: (() -> Void)?

    func replacePendingAttachments(_ attachments: [ChatAttachment]) {
        pendingAttachments = attachments
        notifyDurableStateChanged()
    }

    func appendPromptAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.append(attachment)
        notifyDurableStateChanged()
    }

    func removePromptAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
        pendingLargePasteTexts.removeValue(forKey: attachment.id)
        if let fileURL = pendingSharedFileURLs.removeValue(forKey: attachment.id) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        notifyDurableStateChanged()
    }

    func removePromptAttachment(id: String) {
        pendingAttachments.removeAll { $0.id == id }
        pendingLargePasteTexts.removeValue(forKey: id)
        if let fileURL = pendingSharedFileURLs.removeValue(forKey: id) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        notifyDurableStateChanged()
    }

    func removePromptAttachments(withID id: String) {
        removePromptAttachment(id: id)
    }

    func clearPendingAttachments() {
        pendingAttachments = []
        notifyDurableStateChanged()
    }

    func replacePendingLargePasteTexts(_ texts: [String: String]) {
        pendingLargePasteTexts = texts
        notifyDurableStateChanged()
    }

    func replacePendingSharedFileURLs(_ urls: [String: URL]) {
        pendingSharedFileURLs = urls
    }

    func resetAll() {
        pendingAttachments = []
        pendingLargePasteTexts = [:]
        pendingSharedFileURLs = [:]
        pendingDocumentTexts = [:]
        pendingDocumentTextIDs = []
        notifyDurableStateChanged()
    }

    func stageSharedFileAttachment(_ url: URL, displayName: String, byteCount: Int?) -> ChatAttachment {
        let attachment = ChatAttachment(
            id: "shared-file-\(UUID().uuidString)",
            name: displayName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? url.lastPathComponent,
            kind: ChatAttachment.pendingSharedFileKind,
            bytes: byteCount ?? ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize)
        )
        pendingSharedFileURLs[attachment.id] = url
        pendingAttachments.append(attachment)
        notifyDurableStateChanged()
        return attachment
    }

    func stageLargePasteForSend(_ text: String, suggestedName: String? = nil) -> ChatAttachment {
        let trimmedName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let filename = trimmedName.isEmpty ? Self.largePasteFilename() : trimmedName
        let attachment = ChatAttachment(
            id: "local-paste-\(UUID().uuidString)",
            name: filename,
            kind: ChatAttachment.pendingTextKind,
            bytes: text.utf8.count
        )
        pendingLargePasteTexts[attachment.id] = text
        pendingAttachments.append(attachment)
        notifyDurableStateChanged()
        return attachment
    }

    func shouldPromoteLargePaste(
        previous: String,
        current: String,
        thresholdBytes: Int,
        thresholdCharacters: Int
    ) -> Bool {
        guard current.count > previous.count else { return false }
        let insertedCharacters = current.count - previous.count
        let insertedBytes = current.utf8.count - previous.utf8.count
        guard insertedCharacters >= thresholdCharacters / 2 ||
              insertedBytes >= thresholdBytes / 2 else {
            return false
        }
        return current.count >= thresholdCharacters ||
            current.utf8.count >= thresholdBytes
    }

    func stageDocumentText(_ text: String, for id: String) {
        pendingDocumentTexts[id] = text
        pendingDocumentTextIDs.removeAll { $0 == id }
        pendingDocumentTextIDs.append(id)
        while pendingDocumentTextIDs.count > Self.maxStagedDocuments {
            let evicted = pendingDocumentTextIDs.removeFirst()
            pendingDocumentTexts.removeValue(forKey: evicted)
        }
    }

    func documentText(for id: String) -> String? {
        pendingDocumentTexts[id]
    }

    func documentPayloads(for attachments: [ChatAttachment]) -> [DocumentTextExtractor.LocalDocumentContextPayload] {
        attachments.compactMap { attachment -> DocumentTextExtractor.LocalDocumentContextPayload? in
            guard let text = pendingDocumentTexts[attachment.id] else { return nil }
            return DocumentTextExtractor.LocalDocumentContextPayload(
                text: text,
                isTable: attachment.kind == ChatAttachment.localTableKind
            )
        }
    }

    func documentAugmentedPrompt(_ prompt: String, question: String, attachments: [ChatAttachment]) -> String {
        let documents = attachments.compactMap { pendingDocumentTexts[$0.id] }
        guard !documents.isEmpty,
              !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let context = DocumentChunker.contextBlock(for: question, in: documents, topK: 4) else {
            return prompt
        }
        return "\(context)\n\nUsing those excerpts (and the attached file or table) where relevant:\n\(prompt)"
    }

    func resolvePromptAttachmentsForSend(
        _ promptAttachments: [ChatAttachment],
        fileService: FileService
    ) async throws -> PromptAttachmentResolution {
        var resolved: [ChatAttachment] = []
        var uploadedAttachments: [ChatAttachment] = []
        var uploadedLocalIDs: [String] = []
        var uploadedSharedFileIDs: [String] = []

        for attachment in promptAttachments {
            if let text = pendingLargePasteTexts[attachment.id] {
                isUploadingAttachment = true
                defer { isUploadingAttachment = false }
                let uploaded = try await fileService.uploadTextFile(filename: attachment.name, text: text)
                resolved.append(uploaded)
                uploadedAttachments.append(uploaded)
                uploadedLocalIDs.append(attachment.id)
            } else if let fileURL = pendingSharedFileURLs[attachment.id] {
                isUploadingAttachment = true
                defer { isUploadingAttachment = false }
                var uploaded = try await fileService.uploadFile(from: fileURL)
                uploaded.name = attachment.name
                resolved.append(uploaded)
                uploadedAttachments.append(uploaded)
                uploadedSharedFileIDs.append(attachment.id)
            } else {
                resolved.append(attachment)
            }
        }

        for id in uploadedLocalIDs {
            pendingLargePasteTexts.removeValue(forKey: id)
        }
        for id in uploadedSharedFileIDs {
            if let fileURL = pendingSharedFileURLs.removeValue(forKey: id) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        if !uploadedLocalIDs.isEmpty || !uploadedSharedFileIDs.isEmpty {
            notifyDurableStateChanged()
        }
        return PromptAttachmentResolution(attachments: resolved, uploadedAttachments: uploadedAttachments)
    }

    private func notifyDurableStateChanged() {
        onDurableStateChange?()
    }

    private static func largePasteFilename() -> String {
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return "large-paste-\(stamp).txt"
    }
}
