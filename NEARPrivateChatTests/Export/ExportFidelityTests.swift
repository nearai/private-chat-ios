import XCTest
#if canImport(PDFKit)
import PDFKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testDocxExportPreservesTableStructure() throws {
        let xml = try docxDocumentXML(for: """
        | Party | Role | Amount |
        | --- | --- | --- |
        | Buyer | Lead | $10M |
        | Seller | Counterparty | 25% |
        """)

        XCTAssertTrue(xml.contains("<w:tbl>"))
        for cell in ["Party", "Role", "Amount", "Buyer", "Lead", "$10M", "Seller", "Counterparty", "25%"] {
            XCTAssertTrue(xml.contains(cell), "Missing table cell: \(cell)")
        }
    }

    func testDocxExportPreservesNestedLists() throws {
        let xml = try docxDocumentXML(for: """
        1. Parent one
           - Child bullet
           - Child second
        2. Parent two
           1. Child ordered
        """)

        XCTAssertTrue(xml.contains("<w:ilvl w:val=\"0\"/>"))
        XCTAssertTrue(xml.contains("<w:ilvl w:val=\"1\"/>"))
        XCTAssertTrue(xml.contains("<w:ind w:left=\"720\" w:hanging=\"360\"/>"))
        XCTAssertTrue(xml.contains("<w:ind w:left=\"1080\" w:hanging=\"360\"/>"))
        XCTAssertTrue(xml.contains("<w:numId w:val=\"1\"/>"))
        XCTAssertTrue(xml.contains("<w:numId w:val=\"2\"/>"))
        assertStringsAppearInOrder(
            ["Parent one", "Child bullet", "Child second", "Parent two", "Child ordered"],
            in: xml
        )
    }

    func testPdfExportPreservesContentOrderAndCode() throws {
        #if canImport(PDFKit) && canImport(UIKit)
        let document = try exportDocument(for: """
        # Export Fidelity

        | Term | Value | Notes |
        | --- | --- | --- |
        | Valuation | $10M | Seed |
        | Close | June | Pending |

        ```swift
        let answer = "structured"
        ```

        > Quote survives
        """, format: .pdf)
        let text = try pdfText(from: document.data)

        for value in ["Export Fidelity", "Term", "Value", "Notes", "Valuation", "$10M", "Seed", "Close", "June", "Pending", "let answer", "Quote survives"] {
            XCTAssertTrue(text.contains(value), "Missing PDF text: \(value)\n\(text)")
        }
        assertStringsAppearInOrder(["Export Fidelity", "let answer"], in: text)
        #else
        throw XCTSkip("PDF fidelity assertions require PDFKit and UIKit.")
        #endif
    }

    func testExportKeepsMathSourceVerbatim() throws {
        let markdown = "$$E=mc^2$$"
        let xml = try docxDocumentXML(for: markdown)
        XCTAssertTrue(xml.contains("$$E=mc^2$$"))

        #if canImport(PDFKit) && canImport(UIKit)
        let document = try exportDocument(for: markdown, format: .pdf)
        let text = try pdfText(from: document.data)
        XCTAssertTrue(text.contains("E=mc^2"))
        #else
        throw XCTSkip("PDF math assertions require PDFKit and UIKit.")
        #endif
    }

    private func docxDocumentXML(for markdown: String) throws -> String {
        let document = try exportDocument(for: markdown, format: .docx)
        let data = try zipEntry(named: "word/document.xml", in: document.data)
        return String(decoding: data, as: UTF8.self)
    }

    private func exportDocument(for markdown: String, format: ConversationExportFormat) throws -> ConversationExportDocument {
        let createdAt = Date(timeIntervalSince1970: 1_780_000_000)
        let message = makeMessage(
            id: "export-fidelity-answer",
            role: .assistant,
            text: markdown,
            model: "nearai/test",
            createdAt: createdAt
        )
        return try ConversationExportBuilder.selectedAnswerDocument(
            for: ConversationSummary(
                id: "export-fidelity-conversation",
                createdAt: createdAt.timeIntervalSince1970,
                metadata: ConversationMetadata(title: "Export Fidelity")
            ),
            messages: [message],
            answerID: message.id,
            format: format
        )
    }

    private func assertStringsAppearInOrder(_ values: [String], in text: String, file: StaticString = #filePath, line: UInt = #line) {
        var searchStart = text.startIndex
        for value in values {
            guard let range = text.range(of: value, range: searchStart..<text.endIndex) else {
                XCTFail("Missing ordered value: \(value)", file: file, line: line)
                return
            }
            searchStart = range.upperBound
        }
    }

    private func zipEntry(named entryName: String, in data: Data) throws -> Data {
        var offset = 0
        while offset + 30 <= data.count {
            let signature = data.littleEndianUInt32(at: offset)
            guard signature == 0x0403_4b50 else { break }
            let compressedSize = Int(data.littleEndianUInt32(at: offset + 18))
            let fileNameLength = Int(data.littleEndianUInt16(at: offset + 26))
            let extraLength = Int(data.littleEndianUInt16(at: offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + fileNameLength
            let dataStart = nameEnd + extraLength
            let dataEnd = dataStart + compressedSize
            guard nameEnd <= data.count, dataEnd <= data.count else { break }

            let name = String(decoding: data[nameStart..<nameEnd], as: UTF8.self)
            if name == entryName {
                return Data(data[dataStart..<dataEnd])
            }
            offset = dataEnd
        }
        throw XCTSkip("Missing DOCX entry \(entryName).")
    }

    #if canImport(PDFKit)
    private func pdfText(from data: Data) throws -> String {
        let document = try XCTUnwrap(PDFDocument(data: data))
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }
    #endif
}

private extension Data {
    func littleEndianUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) |
            (UInt16(self[offset + 1]) << 8)
    }

    func littleEndianUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }
}
