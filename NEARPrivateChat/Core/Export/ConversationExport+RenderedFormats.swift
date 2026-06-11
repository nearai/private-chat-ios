import Foundation
#if canImport(UIKit)
import UIKit
#endif

extension ConversationExportBuilder {
    #if canImport(UIKit)
    static func pdfData(markdown text: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 44
        let contentWidth = pageRect.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let blocks = MarkdownBlock.parse(text)

        return renderer.pdfData { context in
            context.beginPage()
            var y = margin

            for block in blocks {
                drawPDFBlock(
                    block,
                    context: context,
                    pageRect: pageRect,
                    margin: margin,
                    contentWidth: contentWidth,
                    y: &y
                )
            }
        }
    }

    private static func drawPDFBlock(
        _ block: MarkdownBlock,
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        margin: CGFloat,
        contentWidth: CGFloat,
        y: inout CGFloat
    ) {
        switch block.kind {
        case let .paragraph(text):
            drawPDFInlineText(
                text,
                baseFont: .systemFont(ofSize: 10.5),
                color: .black,
                context: context,
                pageRect: pageRect,
                margin: margin,
                x: margin,
                width: contentWidth,
                y: &y,
                spacingAfter: 6
            )
        case let .heading(text, level):
            let fontSize: CGFloat = level == 1 ? 22 : (level == 2 ? 15 : 12.5)
            let color = level == 1 ? UIColor.black : UIColor(red: 0.0, green: 0.42, blue: 0.75, alpha: 1.0)
            drawPDFInlineText(
                text,
                baseFont: .systemFont(ofSize: fontSize, weight: .bold),
                color: color,
                context: context,
                pageRect: pageRect,
                margin: margin,
                x: margin,
                width: contentWidth,
                y: &y,
                spacingAfter: level == 1 ? 14 : 8
            )
        case let .list(items):
            for item in items {
                let indent = CGFloat(item.level) * 18
                let marker: String
                switch item.marker {
                case .unordered:
                    marker = "•"
                case let .ordered(number):
                    marker = "\(number)."
                }
                let markerFont = UIFont.systemFont(ofSize: 10.5, weight: .medium)
                let markerText = NSAttributedString(
                    string: marker,
                    attributes: pdfAttributes(font: markerFont, color: .darkGray)
                )
                let markerWidth: CGFloat = 24
                let itemWidth = contentWidth - indent - markerWidth
                let itemText = pdfInlineAttributedString(item.text, baseFont: .systemFont(ofSize: 10.5), color: .black)
                let textHeight = pdfHeight(for: itemText, width: itemWidth)
                let height = max(textHeight, 13)
                ensurePDFSpace(height, context: context, pageRect: pageRect, margin: margin, y: &y)
                markerText.draw(
                    with: CGRect(x: margin + indent, y: y, width: markerWidth - 4, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                itemText.draw(
                    with: CGRect(x: margin + indent + markerWidth, y: y, width: itemWidth, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                y += height + 4
            }
            y += 2
        case let .quote(text):
            let quoteX = margin + 12
            let barRect = CGRect(x: margin, y: y, width: 3, height: 1)
            let attributed = pdfInlineAttributedString(
                text,
                baseFont: .italicSystemFont(ofSize: 10.5),
                color: .darkGray
            )
            let height = max(pdfHeight(for: attributed, width: contentWidth - 18), 14)
            ensurePDFSpace(height, context: context, pageRect: pageRect, margin: margin, y: &y)
            UIColor(red: 0.0, green: 0.42, blue: 0.75, alpha: 0.65).setFill()
            UIBezierPath(rect: CGRect(x: barRect.minX, y: y, width: barRect.width, height: height)).fill()
            attributed.draw(
                with: CGRect(x: quoteX, y: y, width: contentWidth - 18, height: height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            y += height + 8
        case let .code(code, _):
            drawPDFCodeBlock(
                code,
                context: context,
                pageRect: pageRect,
                margin: margin,
                contentWidth: contentWidth,
                y: &y
            )
        case let .math(formula):
            drawPDFCodeBlock(
                mathBlockSource(formula),
                context: context,
                pageRect: pageRect,
                margin: margin,
                contentWidth: contentWidth,
                y: &y
            )
        case .divider:
            ensurePDFSpace(12, context: context, pageRect: pageRect, margin: margin, y: &y)
            UIColor.lightGray.setStroke()
            UIBezierPath(rect: CGRect(x: margin, y: y + 5, width: contentWidth, height: 1)).stroke()
            y += 14
        case let .table(rows):
            drawPDFTable(
                rows,
                context: context,
                pageRect: pageRect,
                margin: margin,
                contentWidth: contentWidth,
                y: &y
            )
        }
    }

    private static func drawPDFInlineText(
        _ text: String,
        baseFont: UIFont,
        color: UIColor,
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        margin: CGFloat,
        x: CGFloat,
        width: CGFloat,
        y: inout CGFloat,
        spacingAfter: CGFloat
    ) {
        let attributed = pdfInlineAttributedString(text.isEmpty ? " " : text, baseFont: baseFont, color: color)
        let height = max(pdfHeight(for: attributed, width: width), 12)
        ensurePDFSpace(height, context: context, pageRect: pageRect, margin: margin, y: &y)
        attributed.draw(
            with: CGRect(x: x, y: y, width: width, height: height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        y += height + spacingAfter
    }

    private static func drawPDFCodeBlock(
        _ code: String,
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        margin: CGFloat,
        contentWidth: CGFloat,
        y: inout CGFloat
    ) {
        let font = UIFont(name: "Menlo-Regular", size: 9.5) ?? .monospacedSystemFont(ofSize: 9.5, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        let attributed = NSAttributedString(
            string: code.isEmpty ? " " : code,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ]
        )
        let inset: CGFloat = 8
        let height = max(pdfHeight(for: attributed, width: contentWidth - inset * 2) + inset * 2, 28)
        ensurePDFSpace(height, context: context, pageRect: pageRect, margin: margin, y: &y)
        UIColor(white: 0.96, alpha: 1.0).setFill()
        UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: contentWidth, height: height), cornerRadius: 6).fill()
        attributed.draw(
            with: CGRect(x: margin + inset, y: y + inset, width: contentWidth - inset * 2, height: height - inset * 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        y += height + 8
    }

    private static func drawPDFTable(
        _ rows: [[String]],
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        margin: CGFloat,
        contentWidth: CGFloat,
        y: inout CGFloat
    ) {
        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return }
        let columnWidths = pdfTableColumnWidths(rows: rows, columnCount: columnCount, contentWidth: contentWidth)
        let cellPadding: CGFloat = 6

        for (rowIndex, row) in rows.enumerated() {
            let cellTexts = (0..<columnCount).map { columnIndex -> NSAttributedString in
                let text = row.indices.contains(columnIndex) ? row[columnIndex] : ""
                let font = rowIndex == 0 ? UIFont.systemFont(ofSize: 9.5, weight: .semibold) : UIFont.systemFont(ofSize: 9.5)
                return pdfInlineAttributedString(text, baseFont: font, color: .black)
            }
            let rowHeight = max(
                cellTexts.enumerated().map { index, value in
                    pdfHeight(for: value, width: columnWidths[index] - cellPadding * 2) + cellPadding * 2
                }.max() ?? 24,
                24
            )
            ensurePDFSpace(rowHeight, context: context, pageRect: pageRect, margin: margin, y: &y)

            var x = margin
            for columnIndex in 0..<columnCount {
                let rect = CGRect(x: x, y: y, width: columnWidths[columnIndex], height: rowHeight)
                (rowIndex == 0 ? UIColor(red: 0.92, green: 0.96, blue: 1.0, alpha: 1.0) : UIColor.white).setFill()
                UIBezierPath(rect: rect).fill()
                UIColor(white: 0.78, alpha: 1.0).setStroke()
                UIBezierPath(rect: rect).stroke()
                cellTexts[columnIndex].draw(
                    with: rect.insetBy(dx: cellPadding, dy: cellPadding),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                x += columnWidths[columnIndex]
            }
            y += rowHeight
        }
        y += 10
    }

    private static func pdfTableColumnWidths(rows: [[String]], columnCount: Int, contentWidth: CGFloat) -> [CGFloat] {
        let font = UIFont.systemFont(ofSize: 9.5)
        let rawWidths = (0..<columnCount).map { columnIndex -> CGFloat in
            let measured = rows.map { row -> CGFloat in
                guard row.indices.contains(columnIndex) else { return 48 }
                return ceil((row[columnIndex] as NSString).size(withAttributes: [.font: font]).width) + 18
            }.max() ?? 64
            return min(max(measured, 64), 190)
        }
        let total = rawWidths.reduce(0, +)
        guard total > contentWidth else { return rawWidths }
        return rawWidths.map { max(48, $0 / total * contentWidth) }
    }

    private static func ensurePDFSpace(
        _ height: CGFloat,
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        margin: CGFloat,
        y: inout CGFloat
    ) {
        if y + height > pageRect.height - margin {
            context.beginPage()
            y = margin
        }
    }

    private static func pdfHeight(for attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).integral.height
    }

    private static func pdfInlineAttributedString(_ text: String, baseFont: UIFont, color: UIColor) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for segment in inlineExportSegments(in: text) {
            let font = pdfFont(baseFont: baseFont, segment: segment)
            var attributes = pdfAttributes(font: font, color: segment.url == nil ? color : UIColor.systemBlue)
            if segment.url != nil {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if segment.isCode {
                attributes[.backgroundColor] = UIColor(white: 0.94, alpha: 1.0)
            }
            output.append(NSAttributedString(string: segment.text, attributes: attributes))
        }
        return output
    }

    private static func pdfFont(baseFont: UIFont, segment: InlineExportSegment) -> UIFont {
        if segment.isCode {
            return UIFont(name: "Menlo-Regular", size: baseFont.pointSize) ??
                .monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
        }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if segment.isBold { traits.insert(.traitBold) }
        if segment.isItalic { traits.insert(.traitItalic) }
        guard !traits.isEmpty,
              let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) else {
            return baseFont
        }
        return UIFont(descriptor: descriptor, size: baseFont.pointSize)
    }

    private static func pdfAttributes(font: UIFont, color: UIColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2

        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    }
    #endif

    static func docxData(markdown: String) throws -> Data {
        try MinimalZIPArchive(entries: [
            MinimalZIPArchive.Entry(path: "[Content_Types].xml", data: Data(docxContentTypesXML.utf8)),
            MinimalZIPArchive.Entry(path: "_rels/.rels", data: Data(docxPackageRelationshipsXML.utf8)),
            MinimalZIPArchive.Entry(path: "word/_rels/document.xml.rels", data: Data(docxDocumentRelationshipsXML.utf8)),
            MinimalZIPArchive.Entry(path: "word/document.xml", data: Data(docxDocumentXML(markdown: markdown).utf8)),
            MinimalZIPArchive.Entry(path: "word/numbering.xml", data: Data(docxNumberingXML.utf8))
        ]).data()
    }

    private static let docxContentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/></Types>
    """

    private static let docxPackageRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
    """

    private static let docxDocumentRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdNumbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/></Relationships>
    """

    private static var docxNumberingXML: String {
        let bulletGlyphs = ["•", "◦", "▪"]
        let bullets = (0...8).map { level in
            let left = 720 + level * 360
            let glyph = bulletGlyphs[level % bulletGlyphs.count]
            return """
            <w:lvl w:ilvl="\(level)"><w:numFmt w:val="bullet"/><w:lvlText w:val="\(glyph)"/><w:pPr><w:ind w:left="\(left)" w:hanging="360"/></w:pPr></w:lvl>
            """
        }.joined()
        let orderedFormats = ["decimal", "lowerLetter", "lowerRoman"]
        let ordered = (0...8).map { level in
            let left = 720 + level * 360
            return """
            <w:lvl w:ilvl="\(level)"><w:numFmt w:val="\(orderedFormats[level % orderedFormats.count])"/><w:lvlText w:val="%\(level + 1)."/><w:pPr><w:ind w:left="\(left)" w:hanging="360"/></w:pPr></w:lvl>
            """
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>\(bullets)</w:abstractNum><w:abstractNum w:abstractNumId="2"><w:multiLevelType w:val="hybridMultilevel"/>\(ordered)</w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num><w:num w:numId="2"><w:abstractNumId w:val="2"/></w:num></w:numbering>
        """
    }

    private static func docxDocumentXML(markdown: String) -> String {
        let body = MarkdownBlock.parse(markdown)
            .map(docxBlockXML)
            .joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>\(body)<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body></w:document>
        """
    }

    private static func docxBlockXML(_ block: MarkdownBlock) -> String {
        switch block.kind {
        case let .paragraph(text):
            return docxInlineParagraphXML(text, paragraphProperties: "<w:pPr><w:spacing w:after=\"100\"/></w:pPr>")
        case let .heading(text, level):
            let style = min(max(level, 1), 3)
            let size = style == 1 ? "32" : (style == 2 ? "26" : "23")
            return docxInlineParagraphXML(
                text,
                paragraphProperties: "<w:pPr><w:pStyle w:val=\"Heading\(style)\"/><w:spacing w:before=\"160\" w:after=\"120\"/></w:pPr>",
                forcedRunProperties: "<w:b/><w:sz w:val=\"\(size)\"/>"
            )
        case let .list(items):
            return items.map(docxListItemXML).joined()
        case let .quote(text):
            return docxInlineParagraphXML(
                text,
                paragraphProperties: "<w:pPr><w:ind w:left=\"360\"/><w:pBdr><w:left w:val=\"single\" w:sz=\"12\" w:space=\"8\" w:color=\"006ABF\"/></w:pBdr></w:pPr>",
                forcedRunProperties: "<w:i/><w:color w:val=\"555555\"/>"
            )
        case let .code(code, _):
            return docxCodeParagraphXML(code)
        case let .math(formula):
            return docxCodeParagraphXML(mathBlockSource(formula))
        case .divider:
            return "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"CCCCCC\"/></w:pBdr></w:pPr></w:p>"
        case let .table(rows):
            return docxTableXML(rows)
        }
    }

    private static func docxInlineParagraphXML(
        _ text: String,
        paragraphProperties: String = "",
        forcedRunProperties: String = ""
    ) -> String {
        "<w:p>\(paragraphProperties)\(docxInlineRunsXML(text, forcedRunProperties: forcedRunProperties))</w:p>"
    }

    private static func docxListItemXML(_ item: MarkdownListItem) -> String {
        let numID: Int
        switch item.marker {
        case .unordered:
            numID = 1
        case .ordered:
            numID = 2
        }
        let level = min(item.level, 8)
        let left = 720 + level * 360
        let paragraphProperties = """
        <w:pPr><w:numPr><w:ilvl w:val="\(level)"/><w:numId w:val="\(numID)"/></w:numPr><w:ind w:left="\(left)" w:hanging="360"/></w:pPr>
        """
        return docxInlineParagraphXML(item.text, paragraphProperties: paragraphProperties)
    }

    private static func docxTableXML(_ rows: [[String]]) -> String {
        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return "" }
        let grid = (0..<columnCount)
            .map { _ in "<w:gridCol w:w=\"2400\"/>" }
            .joined()
        let rowXML = rows.enumerated().map { rowIndex, row in
            let cells = (0..<columnCount).map { columnIndex -> String in
                let value = row.indices.contains(columnIndex) ? row[columnIndex] : ""
                let shading = rowIndex == 0 ? "<w:shd w:fill=\"EAF4FF\"/>" : ""
                let runProperties = rowIndex == 0 ? "<w:b/>" : ""
                return """
                <w:tc><w:tcPr><w:tcW w:w="2400" w:type="dxa"/>\(shading)</w:tcPr>\(docxInlineParagraphXML(value, forcedRunProperties: runProperties))</w:tc>
                """
            }.joined()
            return "<w:tr>\(cells)</w:tr>"
        }.joined()
        return """
        <w:tbl><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:color="CCCCCC"/><w:left w:val="single" w:sz="4" w:color="CCCCCC"/><w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/><w:right w:val="single" w:sz="4" w:color="CCCCCC"/><w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/><w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/></w:tblBorders></w:tblPr><w:tblGrid>\(grid)</w:tblGrid>\(rowXML)</w:tbl>
        """
    }

    private static func docxCodeParagraphXML(_ code: String) -> String {
        let lines = (code.isEmpty ? " " : code).components(separatedBy: .newlines)
        let runs = lines.enumerated().map { index, line in
            let lineBreak = index == lines.count - 1 ? "" : "<w:br/>"
            return """
            <w:r><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/><w:sz w:val="19"/></w:rPr><w:t xml:space="preserve">\(xmlEscaped(line))</w:t>\(lineBreak)</w:r>
            """
        }.joined()
        return "<w:p><w:pPr><w:shd w:fill=\"F3F4F6\"/><w:spacing w:before=\"100\" w:after=\"120\"/></w:pPr>\(runs)</w:p>"
    }

    private static func docxInlineRunsXML(_ text: String, forcedRunProperties: String = "") -> String {
        let segments = inlineExportSegments(in: text.isEmpty ? " " : text)
        return segments.map { segment in
            let properties = docxRunPropertiesXML(for: segment, forcedRunProperties: forcedRunProperties)
            return "<w:r>\(properties)<w:t xml:space=\"preserve\">\(xmlEscaped(segment.text))</w:t></w:r>"
        }.joined()
    }

    private static func docxRunPropertiesXML(for segment: InlineExportSegment, forcedRunProperties: String) -> String {
        var properties = forcedRunProperties
        if segment.isBold {
            properties += "<w:b/>"
        }
        if segment.isItalic {
            properties += "<w:i/>"
        }
        if segment.isCode {
            properties += "<w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\"/><w:shd w:fill=\"F3F4F6\"/>"
        }
        if segment.url != nil {
            properties += "<w:color w:val=\"0563C1\"/><w:u w:val=\"single\"/>"
        }
        return properties.isEmpty ? "" : "<w:rPr>\(properties)</w:rPr>"
    }

    private static func inlineExportSegments(in text: String) -> [InlineExportSegment] {
        var segments: [InlineExportSegment] = []
        var plain = ""
        var index = text.startIndex

        func flushPlain() {
            guard !plain.isEmpty else { return }
            segments.append(InlineExportSegment(text: plain))
            plain = ""
        }

        while index < text.endIndex {
            if text[index] == "`",
               let closing = text[text.index(after: index)...].firstIndex(of: "`") {
                flushPlain()
                let contentStart = text.index(after: index)
                segments.append(InlineExportSegment(text: String(text[contentStart..<closing]), isCode: true))
                index = text.index(after: closing)
                continue
            }

            if text[index...].hasPrefix("**"),
               let closing = text.range(of: "**", range: text.index(index, offsetBy: 2)..<text.endIndex) {
                flushPlain()
                let contentStart = text.index(index, offsetBy: 2)
                segments.append(InlineExportSegment(text: String(text[contentStart..<closing.lowerBound]), isBold: true))
                index = closing.upperBound
                continue
            }

            if text[index] == "*",
               let closing = text[text.index(after: index)...].firstIndex(of: "*") {
                flushPlain()
                let contentStart = text.index(after: index)
                segments.append(InlineExportSegment(text: String(text[contentStart..<closing]), isItalic: true))
                index = text.index(after: closing)
                continue
            }

            if let link = markdownLink(at: index, in: text) {
                flushPlain()
                segments.append(InlineExportSegment(text: "\(link.label) (\(link.url))", url: link.url))
                index = link.end
                continue
            }

            plain.append(text[index])
            index = text.index(after: index)
        }

        flushPlain()
        return segments.isEmpty ? [InlineExportSegment(text: text)] : segments
    }

    private static func markdownLink(
        at index: String.Index,
        in text: String
    ) -> (label: String, url: String, end: String.Index)? {
        guard text[index] == "[" else { return nil }
        guard let labelEnd = text[text.index(after: index)...].firstIndex(of: "]") else { return nil }
        let openParen = text.index(after: labelEnd)
        guard openParen < text.endIndex, text[openParen] == "(" else { return nil }
        guard let closeParen = text[text.index(after: openParen)...].firstIndex(of: ")") else { return nil }
        let label = String(text[text.index(after: index)..<labelEnd])
        let url = String(text[text.index(after: openParen)..<closeParen])
        guard !label.isEmpty, !url.isEmpty else { return nil }
        return (label, url, text.index(after: closeParen))
    }

    private static func mathBlockSource(_ formula: String) -> String {
        formula.contains("\n") ? "$$\n\(formula)\n$$" : "$$\(formula)$$"
    }

    static func xmlEscaped(_ value: String) -> String {
        // Drop scalars XML 1.0 forbids even as entities (C0 controls except
        // tab/newline/CR, plus U+FFFE/U+FFFF). A literal control char from
        // model output or a pasted attachment otherwise produces a .docx Word
        // refuses to open ("unreadable content").
        let cleaned = String(String.UnicodeScalarView(value.unicodeScalars.filter { scalar in
            let v = scalar.value
            if v == 0x9 || v == 0xA || v == 0xD { return true }
            if v < 0x20 { return false }
            if v == 0xFFFE || v == 0xFFFF { return false }
            return true
        }))
        return cleaned
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private struct InlineExportSegment {
    var text: String
    var isBold: Bool = false
    var isItalic: Bool = false
    var isCode: Bool = false
    var url: String?
}

private struct MinimalZIPArchive {
    struct Entry {
        var path: String
        var data: Data
    }

    var entries: [Entry]

    func data() throws -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let localHeaderOffset = UInt32(archive.count)
            let pathData = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)

            archive.appendLittleEndianUInt32(0x04034b50)
            archive.appendLittleEndianUInt16(20)
            archive.appendLittleEndianUInt16(0)
            archive.appendLittleEndianUInt16(0)
            archive.appendLittleEndianUInt16(0)
            archive.appendLittleEndianUInt16(0)
            archive.appendLittleEndianUInt32(crc)
            archive.appendLittleEndianUInt32(size)
            archive.appendLittleEndianUInt32(size)
            archive.appendLittleEndianUInt16(UInt16(pathData.count))
            archive.appendLittleEndianUInt16(0)
            archive.append(pathData)
            archive.append(entry.data)

            centralDirectory.appendLittleEndianUInt32(0x02014b50)
            centralDirectory.appendLittleEndianUInt16(20)
            centralDirectory.appendLittleEndianUInt16(20)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt32(crc)
            centralDirectory.appendLittleEndianUInt32(size)
            centralDirectory.appendLittleEndianUInt32(size)
            centralDirectory.appendLittleEndianUInt16(UInt16(pathData.count))
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt32(0)
            centralDirectory.appendLittleEndianUInt32(localHeaderOffset)
            centralDirectory.append(pathData)
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.appendLittleEndianUInt32(0x06054b50)
        archive.appendLittleEndianUInt16(0)
        archive.appendLittleEndianUInt16(0)
        archive.appendLittleEndianUInt16(UInt16(entries.count))
        archive.appendLittleEndianUInt16(UInt16(entries.count))
        archive.appendLittleEndianUInt32(UInt32(centralDirectory.count))
        archive.appendLittleEndianUInt32(centralDirectoryOffset)
        archive.appendLittleEndianUInt16(0)
        return archive
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask = 0 &- (crc & 1)
                crc = (crc >> 1) ^ (0xedb8_8320 & mask)
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendLittleEndianUInt16(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendLittleEndianUInt32(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}

