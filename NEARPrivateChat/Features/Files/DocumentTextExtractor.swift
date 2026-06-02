import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(zlib)
import zlib
#endif

enum DocumentTextExtractor {
    nonisolated static let maxLocalTableBytes = 2 * 1024 * 1024
    nonisolated static let maxPDFTextExtractionBytes = 5 * 1024 * 1024
    nonisolated static let maxPDFExtractedTextBytes = 10 * 1024 * 1024
    nonisolated static let maxPDFExtractionPages = 40
    nonisolated static let maxPDFExtractionSeconds: TimeInterval = 5

    struct TableTextExtractionResult: Sendable, Equatable {
        var text: String
        var truncated: Bool
    }

    struct PDFTextExtractionResult: Sendable, Equatable {
        var text: String
        var truncated: Bool
    }

    struct LocalDocumentContextPayload: Sendable, Equatable {
        var text: String
        var isTable: Bool
    }

    nonisolated static func shouldKeepDelimitedTableOnDevice(
        fileExtension: String,
        keepDocumentsOnDevice: Bool
    ) -> Bool {
        keepDocumentsOnDevice && (fileExtension == "csv" || fileExtension == "tsv")
    }

    nonisolated static func extractedTableFilename(for url: URL) -> String {
        let basename = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeBasename = basename.isEmpty ? "table" : basename
        return "\(safeBasename)-table-text.txt"
    }

    nonisolated static func extractedPDFFilename(for url: URL) -> String {
        let basename = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeBasename = basename.isEmpty ? "attachment" : basename
        return "\(safeBasename)-pdf-text.txt"
    }

    nonisolated static func extractedDelimitedTableText(from url: URL, fileSize: Int?) -> TableTextExtractionResult? {
        if let fileSize, fileSize > maxLocalTableBytes {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return extractedDelimitedTableText(
            data: data,
            filename: url.lastPathComponent,
            delimiter: url.pathExtension.lowercased() == "tsv" ? "\t" : ","
        )
    }

    nonisolated static func extractedDelimitedTableText(
        data: Data,
        filename: String,
        delimiter: Character
    ) -> TableTextExtractionResult? {
        guard data.count <= maxLocalTableBytes,
              let rawText = string(fromDelimitedTableData: data) else {
            return nil
        }
        return extractedDelimitedTableText(rawText: rawText, filename: filename, delimiter: delimiter)
    }

    nonisolated static func extractedDelimitedTableText(
        rawText: String,
        filename: String,
        delimiter: Character
    ) -> TableTextExtractionResult? {
        let rows = parseDelimitedRows(rawText, delimiter: delimiter)
        guard !rows.isEmpty else { return nil }
        let maxRows = 220
        let normalized = rows.prefix(maxRows).map { row in
            row.map(normalizedTableCell).joined(separator: " | ")
        }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !normalized.isEmpty else { return nil }

        let header = "Extracted table rows from \(filename):"
        let body = normalized.enumerated().map { index, row in
            "Row \(index + 1): \(row)"
        }.joined(separator: "\n")
        return TableTextExtractionResult(
            text: "\(header)\n\(body)",
            truncated: rows.count > maxRows
        )
    }

    nonisolated static func extractedSpreadsheetTableText(from url: URL, fileSize: Int?) -> TableTextExtractionResult? {
        if let fileSize, fileSize > APIClient.maxUploadBytes {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return extractedSpreadsheetTableText(data: data, filename: url.lastPathComponent)
    }

    nonisolated static func extractedSpreadsheetTableText(data: Data, filename: String) -> TableTextExtractionResult? {
        guard data.count <= APIClient.maxUploadBytes,
              let archive = XLSXArchive(data: data) else {
            return nil
        }

        let sharedStrings = xlsxSharedStrings(from: archive.textEntry("xl/sharedStrings.xml"))
        let sheetRefs = xlsxSheetReferences(
            workbookXML: archive.textEntry("xl/workbook.xml"),
            relationshipsXML: archive.textEntry("xl/_rels/workbook.xml.rels")
        )
        guard !sheetRefs.isEmpty else { return nil }

        let maxRowsPerSheet = 80
        let maxWorkbookRows = 900
        var emittedRows = 0
        var output: [String] = ["Extracted workbook rows from \(filename):"]
        var truncated = false

        for sheet in sheetRefs {
            guard emittedRows < maxWorkbookRows,
                  let xml = archive.textEntry(sheet.path) else {
                if emittedRows >= maxWorkbookRows { truncated = true }
                continue
            }

            let rows = xlsxRows(from: xml, sharedStrings: sharedStrings)
            let normalized = rows.compactMap { row -> (Int, String)? in
                let cells = row.values.map(normalizedTableCell)
                    .filter { !$0.isEmpty }
                guard !cells.isEmpty else { return nil }
                return (row.number, cells.joined(separator: " | "))
            }
            guard !normalized.isEmpty else { continue }

            output.append("")
            output.append("Sheet \"\(sheet.name)\":")
            for (index, row) in normalized.prefix(maxRowsPerSheet).enumerated() {
                guard emittedRows < maxWorkbookRows else {
                    truncated = true
                    break
                }
                output.append("Row \(row.0): \(row.1)")
                emittedRows += 1
                if index == maxRowsPerSheet - 1, normalized.count > maxRowsPerSheet {
                    truncated = true
                }
            }
        }

        guard emittedRows > 0 else { return nil }
        return TableTextExtractionResult(text: output.joined(separator: "\n"), truncated: truncated)
    }

    nonisolated static func extractPDFText(from url: URL, fileSize: Int?) async -> PDFTextExtractionResult? {
        #if canImport(PDFKit)
        guard let fileSize, fileSize <= maxPDFTextExtractionBytes else { return nil }
        return await pdfTextExtractionQueue.extract(from: url, fileSize: fileSize)
        #else
        return nil
        #endif
    }

    nonisolated static func localDocumentQuery(userText: String, actionSurfaceText: String) -> String {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? actionSurfaceText : trimmed
    }

    nonisolated static func localDocumentContextBlock(
        for query: String,
        payloads: [LocalDocumentContextPayload],
        topK: Int = 5
    ) -> String? {
        let documents = payloads.map(\.text)
        if let context = DocumentChunker.contextBlock(for: query, in: documents, topK: topK) {
            return context
        }

        let tablePreviews = payloads
            .filter { $0.isTable }
            .flatMap { DocumentChunker.chunk($0.text).prefix(2) }
            .prefix(topK)
        guard !tablePreviews.isEmpty else { return nil }
        let joined = tablePreviews.joined(separator: "\n\n– – –\n\n")
        return "Relevant excerpts from the attached table(s):\n\"\"\"\n\(joined)\n\"\"\""
    }

    nonisolated static func localDocsAllowedForRoute(councilModelIDs: [String], singleModelID: String) -> Bool {
        if councilModelIDs.count > 1 {
            return councilModelIDs.allSatisfy { RoutePlanner.routeKind(forModelID: $0) == .nearPrivate }
        }
        return RoutePlanner.routeKind(forModelID: singleModelID) == .nearPrivate
    }

    nonisolated static func parseDelimitedRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var isInsideQuotedCell = false
        var index = text.startIndex

        func appendCell() {
            row.append(cell)
            cell = ""
        }

        func appendRowIfNeeded() {
            appendCell()
            if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                rows.append(row)
            }
            row = []
        }

        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if isInsideQuotedCell, next < text.endIndex, text[next] == "\"" {
                    cell.append("\"")
                    index = text.index(after: next)
                    continue
                }
                isInsideQuotedCell.toggle()
            } else if character == delimiter, !isInsideQuotedCell {
                appendCell()
            } else if (character == "\n" || character == "\r"), !isInsideQuotedCell {
                if character == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" {
                        index = next
                    }
                }
                appendRowIfNeeded()
            } else {
                cell.append(character)
            }
            index = text.index(after: index)
        }

        if !cell.isEmpty || !row.isEmpty {
            appendRowIfNeeded()
        }
        return rows
    }

    nonisolated private static func xlsxSharedStrings(from xml: String?) -> [String] {
        guard let xml else { return [] }
        return xmlMatches(pattern: #"<si\b[^>]*>(.*?)</si>"#, in: xml).map { item in
            let parts = xmlMatches(pattern: #"<t\b[^>]*>(.*?)</t>"#, in: item)
            return parts.map(xmlDecodedText).joined()
        }
    }

    nonisolated private static func xlsxSheetReferences(
        workbookXML: String?,
        relationshipsXML: String?
    ) -> [(name: String, path: String)] {
        guard let workbookXML else { return [] }
        let relationshipTargets = xlsxRelationshipTargets(from: relationshipsXML)
        return xmlMatches(pattern: #"<sheet\b[^>]*/?>"#, in: workbookXML).compactMap { tag in
            let attributes = xmlAttributes(in: tag)
            guard let rawName = attributes["name"] else { return nil }
            let name = xmlDecodedText(rawName)
            let relationshipID = attributes["r:id"] ?? attributes["id"]
            let rawPath = relationshipID.flatMap { relationshipTargets[$0] }
                ?? attributes["sheetId"].map { "worksheets/sheet\($0).xml" }
            guard let rawPath else { return nil }
            let path = rawPath.hasPrefix("xl/") ? rawPath : "xl/\(rawPath)"
            return (name: name, path: path.replacingOccurrences(of: "//", with: "/"))
        }
    }

    nonisolated private static func xlsxRelationshipTargets(from xml: String?) -> [String: String] {
        guard let xml else { return [:] }
        return xmlMatches(pattern: #"<Relationship\b[^>]*/?>"#, in: xml).reduce(into: [String: String]()) { result, tag in
            let attributes = xmlAttributes(in: tag)
            guard let id = attributes["Id"], let target = attributes["Target"] else { return }
            result[id] = target
        }
    }

    nonisolated private static func xlsxRows(
        from xml: String,
        sharedStrings: [String]
    ) -> [(number: Int, values: [String])] {
        xmlMatches(pattern: #"<row\b[^>]*>.*?</row>"#, in: xml).compactMap { rowXML -> (Int, [String])? in
            let rowTag = xmlMatches(pattern: #"^<row\b[^>]*>"#, in: rowXML).first ?? ""
            let rowNumber = Int(xmlAttributes(in: rowTag)["r"] ?? "") ?? 0
            var cells: [(Int, String)] = []
            for cellXML in xmlMatches(pattern: #"<c\b[^>]*(?<!/)>.*?</c>"#, in: rowXML) {
                guard let cellTag = xmlMatches(pattern: #"^<c\b[^>]*>"#, in: cellXML).first else { continue }
                let attributes = xmlAttributes(in: cellTag)
                let column = attributes["r"].flatMap(xlsxColumnIndex(from:)) ?? cells.count + 1
                guard let value = xlsxCellValue(from: cellXML, attributes: attributes, sharedStrings: sharedStrings),
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                cells.append((column, value))
            }
            let values = cells.sorted { $0.0 < $1.0 }.map(\.1)
            guard !values.isEmpty else { return nil }
            return (number: rowNumber == 0 ? 1 : rowNumber, values: values)
        }
    }

    nonisolated private static func xlsxCellValue(
        from cellXML: String,
        attributes: [String: String],
        sharedStrings: [String]
    ) -> String? {
        if attributes["t"] == "inlineStr" {
            let parts = xmlMatches(pattern: #"<t\b[^>]*>(.*?)</t>"#, in: cellXML)
            return parts.map(xmlDecodedText).joined()
        }
        guard let rawValue = xmlMatches(pattern: #"<v\b[^>]*>(.*?)</v>"#, in: cellXML).first else {
            return nil
        }
        let decoded = xmlDecodedText(rawValue)
        if attributes["t"] == "s",
           let index = Int(decoded),
           sharedStrings.indices.contains(index) {
            return sharedStrings[index]
        }
        return decoded
    }

    nonisolated private static func xlsxColumnIndex(from cellReference: String) -> Int? {
        var result = 0
        var sawLetter = false
        for scalar in cellReference.uppercased().unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { break }
            sawLetter = true
            result = result * 26 + Int(scalar.value - 64)
        }
        return sawLetter ? result : nil
    }

    nonisolated private static func xmlMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            let captureIndex = match.numberOfRanges > 1 ? 1 : 0
            guard let range = Range(match.range(at: captureIndex), in: text) else { return nil }
            return String(text[range])
        }
    }

    nonisolated private static func xmlAttributes(in tag: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z_:][A-Za-z0-9_:.\-]*)\s*=\s*"([^"]*)""#) else {
            return [:]
        }
        let nsRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        return regex.matches(in: tag, range: nsRange).reduce(into: [String: String]()) { result, match in
            guard match.numberOfRanges >= 3,
                  let keyRange = Range(match.range(at: 1), in: tag),
                  let valueRange = Range(match.range(at: 2), in: tag) else {
                return
            }
            result[String(tag[keyRange])] = xmlDecodedText(String(tag[valueRange]))
        }
    }

    nonisolated private static func xmlDecodedText(_ text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return decoded
        }
        let matches = regex.matches(in: decoded, range: NSRange(decoded.startIndex..<decoded.endIndex, in: decoded))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: decoded),
                  let valueRange = Range(match.range(at: 1), in: decoded) else {
                continue
            }
            let rawValue = String(decoded[valueRange])
            let radix = rawValue.hasPrefix("x") ? 16 : 10
            let digits = rawValue.hasPrefix("x") ? String(rawValue.dropFirst()) : rawValue
            guard let scalarValue = UInt32(digits, radix: radix),
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            decoded.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return decoded
    }

    nonisolated private static func string(fromDelimitedTableData data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .utf16) {
            return text
        }
        if let text = String(data: data, encoding: .utf16LittleEndian) {
            return text
        }
        if let text = String(data: data, encoding: .utf16BigEndian) {
            return text
        }
        return String(data: data, encoding: .isoLatin1)
    }

    nonisolated private static func normalizedTableCell(_ cell: String) -> String {
        cell
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct XLSXArchive {
        let entries: [String: Data]

        init?(data: Data) {
            guard let entries = Self.entries(from: data), !entries.isEmpty else {
                return nil
            }
            self.entries = entries
        }

        func textEntry(_ path: String) -> String? {
            guard let data = entries[path] else { return nil }
            return String(data: data, encoding: .utf8)
        }

        private static func entries(from data: Data) -> [String: Data]? {
            guard let end = endOfCentralDirectory(in: data) else { return nil }
            let entryCount = Int(littleUInt16(data, at: end + 10) ?? 0)
            guard let centralDirectoryOffset = littleUInt32(data, at: end + 16).map(Int.init) else {
                return nil
            }

            var offset = centralDirectoryOffset
            var result: [String: Data] = [:]
            for _ in 0..<entryCount {
                guard littleUInt32(data, at: offset) == 0x0201_4b50,
                      let method = littleUInt16(data, at: offset + 10),
                      let compressedSize = littleUInt32(data, at: offset + 20).map(Int.init),
                      let uncompressedSize = littleUInt32(data, at: offset + 24).map(Int.init),
                      let filenameLength = littleUInt16(data, at: offset + 28).map(Int.init),
                      let extraLength = littleUInt16(data, at: offset + 30).map(Int.init),
                      let commentLength = littleUInt16(data, at: offset + 32).map(Int.init),
                      let localHeaderOffset = littleUInt32(data, at: offset + 42).map(Int.init) else {
                    return nil
                }
                let nameStart = offset + 46
                let nameEnd = nameStart + filenameLength
                guard nameEnd <= data.count,
                      let name = String(data: data[nameStart..<nameEnd], encoding: .utf8) else {
                    return nil
                }
                if !name.hasSuffix("/") {
                    guard let entryData = entryData(
                        in: data,
                        localHeaderOffset: localHeaderOffset,
                        method: method,
                        compressedSize: compressedSize,
                        uncompressedSize: uncompressedSize
                    ) else {
                        return nil
                    }
                    result[name] = entryData
                }
                offset = nameEnd + extraLength + commentLength
            }
            return result
        }

        private static func entryData(
            in data: Data,
            localHeaderOffset: Int,
            method: UInt16,
            compressedSize: Int,
            uncompressedSize: Int
        ) -> Data? {
            guard littleUInt32(data, at: localHeaderOffset) == 0x0403_4b50,
                  let filenameLength = littleUInt16(data, at: localHeaderOffset + 26).map(Int.init),
                  let extraLength = littleUInt16(data, at: localHeaderOffset + 28).map(Int.init) else {
                return nil
            }
            let payloadStart = localHeaderOffset + 30 + filenameLength + extraLength
            let payloadEnd = payloadStart + compressedSize
            guard payloadStart >= 0, payloadEnd <= data.count else { return nil }
            let payload = data[payloadStart..<payloadEnd]
            switch method {
            case 0:
                return Data(payload)
            case 8:
                return inflateRawDeflate(payload, expectedSize: uncompressedSize)
            default:
                return nil
            }
        }

        private static func endOfCentralDirectory(in data: Data) -> Int? {
            let signature: UInt32 = 0x0605_4b50
            let lowerBound = max(0, data.count - 65_557)
            guard data.count >= 22, lowerBound <= data.count - 22 else { return nil }
            for offset in stride(from: data.count - 22, through: lowerBound, by: -1) {
                if littleUInt32(data, at: offset) == signature {
                    return offset
                }
            }
            return nil
        }

        private static func littleUInt16(_ data: Data, at offset: Int) -> UInt16? {
            guard offset >= 0, offset + 2 <= data.count else { return nil }
            return data.withUnsafeBytes { rawBuffer in
                let bytes = rawBuffer.bindMemory(to: UInt8.self)
                return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
            }
        }

        private static func littleUInt32(_ data: Data, at offset: Int) -> UInt32? {
            guard offset >= 0, offset + 4 <= data.count else { return nil }
            return data.withUnsafeBytes { rawBuffer in
                let bytes = rawBuffer.bindMemory(to: UInt8.self)
                return UInt32(bytes[offset]) |
                    (UInt32(bytes[offset + 1]) << 8) |
                    (UInt32(bytes[offset + 2]) << 16) |
                    (UInt32(bytes[offset + 3]) << 24)
            }
        }

        private static func inflateRawDeflate(_ data: Data.SubSequence, expectedSize: Int) -> Data? {
            #if canImport(zlib)
            guard !data.isEmpty || expectedSize == 0 else { return nil }
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                return nil
            }
            defer { inflateEnd(&stream) }

            var input = Data(data)
            var output = Data(count: max(expectedSize, 1))
            let status: Int32 = input.withUnsafeMutableBytes { inputBuffer in
                output.withUnsafeMutableBytes { outputBuffer in
                    stream.next_in = inputBuffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_in = uInt(inputBuffer.count)
                    stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(outputBuffer.count)
                    return inflate(&stream, Z_FINISH)
                }
            }
            guard status == Z_STREAM_END else { return nil }
            output.removeSubrange(Int(stream.total_out)..<output.count)
            return output
            #else
            return nil
            #endif
        }
    }

    #if canImport(PDFKit)
    private actor PDFTextExtractionTimeout {
        private var continuation: CheckedContinuation<PDFTextExtractionResult?, Never>?

        init(continuation: CheckedContinuation<PDFTextExtractionResult?, Never>) {
            self.continuation = continuation
        }

        func resume(_ result: PDFTextExtractionResult?) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: result)
        }
    }

    private actor PDFTextExtractionQueue {
        func extract(from url: URL, fileSize: Int) async -> PDFTextExtractionResult? {
            await DocumentTextExtractor.extractedPDFTextWithTimeout(from: url, fileSize: fileSize)
        }
    }

    nonisolated private static let pdfTextExtractionQueue = PDFTextExtractionQueue()

    nonisolated private static func extractedPDFTextWithTimeout(from url: URL, fileSize: Int) async -> PDFTextExtractionResult? {
        await withCheckedContinuation { continuation in
            let timeoutState = PDFTextExtractionTimeout(continuation: continuation)
            let extractionTask = Task.detached(priority: .userInitiated) {
                Self.extractedPDFText(from: url, fileSize: fileSize)
            }
            Task.detached {
                let result = await extractionTask.value
                await timeoutState.resume(result)
            }
            Task.detached {
                let nanoseconds = UInt64(maxPDFExtractionSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                extractionTask.cancel()
                await timeoutState.resume(nil)
            }
        }
    }

    nonisolated private static func extractedPDFText(from url: URL, fileSize: Int?) -> PDFTextExtractionResult? {
        if let fileSize, fileSize > maxPDFTextExtractionBytes {
            return nil
        }
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            return nil
        }

        let startedAt = Date()
        let pageLimit = min(document.pageCount, maxPDFExtractionPages)
        var pages: [String] = []
        var accumulatedBytes = 0
        var truncated = document.pageCount > pageLimit

        for pageIndex in 0..<pageLimit {
            if Task.isCancelled || Date().timeIntervalSince(startedAt) > maxPDFExtractionSeconds {
                truncated = true
                break
            }
            let pageText = document.page(at: pageIndex)?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pageText, !pageText.isEmpty else { continue }

            let pageBytes = pageText.utf8.count
            if accumulatedBytes + pageBytes > maxPDFExtractedTextBytes {
                truncated = true
                break
            }
            pages.append(pageText)
            accumulatedBytes += pageBytes + 2
        }

        let text = pages.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : PDFTextExtractionResult(text: text, truncated: truncated)
    }
    #endif
}
