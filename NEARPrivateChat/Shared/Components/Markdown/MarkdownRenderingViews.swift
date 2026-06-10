import SwiftUI

struct MarkdownMessageText: View {
    let text: String
    let sources: [WebSearchSource]

    init(text: String, sources: [WebSearchSource] = []) {
        self.text = text
        self.sources = sources
    }

    private var blocks: [MarkdownBlock] {
        Self.cachedBlocks(for: text, sources: sources)
    }

    private static let blockCache: NSCache<NSString, MarkdownBlockCacheBox> = {
        let cache = NSCache<NSString, MarkdownBlockCacheBox>()
        cache.countLimit = 240
        return cache
    }()

    private static func cachedBlocks(for text: String, sources: [WebSearchSource]) -> [MarkdownBlock] {
        let key = cacheKey(for: text, sources: sources)
        if let cached = blockCache.object(forKey: key) {
            return cached.blocks
        }
        let blocks = MarkdownBlock.parse(normalizedMarkdown(text, sources: sources))
        blockCache.setObject(MarkdownBlockCacheBox(blocks: blocks), forKey: key)
        return blocks
    }

    private static func cacheKey(for text: String, sources: [WebSearchSource]) -> NSString {
        let sourceKey = sources.compactMap { $0.safeURL?.absoluteString }.joined(separator: "|")
        return "\(sourceKey)\n\(text)" as NSString
    }

    private static func normalizedMarkdown(_ text: String, sources: [WebSearchSource]) -> String {
        linkCitationMarkers(in: promoteCouncilSectionLabels(in: text), sources: sources)
    }

    private static func promoteCouncilSectionLabels(in text: String) -> String {
        let labels: Set<String> = [
            "direct answer",
            "synthesis",
            "what the council agrees on",
            "how the models vary",
            "model differences",
            "disagreements or uncertainty",
            "recommended next step",
            "raw glm view",
            "raw qwen max view",
            "raw opus view",
            "raw claude opus view",
            "ironclaw output",
            "inputs",
            "what changed in the plan",
            "updated project plan",
            "risks found",
            "final recommendation"
        ]
        return text
            .components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.hasPrefix("#"),
                      labels.contains(trimmed.lowercased()) else {
                    return line
                }
                return "## \(trimmed)"
            }
            .joined(separator: "\n")
    }

    private static func linkCitationMarkers(in text: String, sources: [WebSearchSource]) -> String {
        guard !sources.isEmpty else { return text }
        let pattern = #"(?<!\!)\[(\d{1,2})\](?!\()"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }

        var linked = text
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let wholeRange = Range(match.range(at: 0), in: linked),
                  let numberRange = Range(match.range(at: 1), in: linked),
                  let index = Int(linked[numberRange]),
                  index > 0,
                  sources.indices.contains(index - 1),
                  let url = sources[index - 1].safeURL else {
                continue
            }
            linked.replaceSubrange(wholeRange, with: "[[\(index)]](\(url.absoluteString))")
        }
        return linked
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(blocks) { block in
                switch block.kind {
                case let .paragraph(value):
                    InlineMarkdownText(text: value)
                        .lineSpacing(2)
                case let .heading(value, level):
                    InlineMarkdownText(text: value)
                        .font(level <= 2 ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
                        .padding(.top, 2)
                case let .list(items):
                    MarkdownList(items: items)
                case let .quote(value):
                    MarkdownQuote(text: value)
                case let .code(code, language):
                    MarkdownCodeBlock(code: code, language: language)
                case let .math(formula):
                    MarkdownMathBlock(formula: formula)
                case .divider:
                    Divider()
                        .padding(.vertical, 3)
                case let .table(rows):
                    MarkdownTable(rows: rows)
                }
            }
        }
        .textSelection(.enabled)
    }
}

private final class MarkdownBlockCacheBox {
    let blocks: [MarkdownBlock]

    init(blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }
}

struct MarkdownBlock: Identifiable {
    enum Kind {
        case paragraph(String)
        case heading(String, level: Int)
        case list([MarkdownListItem])
        case quote(String)
        case code(String, language: String?)
        case math(String)
        case divider
        case table([[String]])
    }

    let id: Int
    let kind: Kind

    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0
        var blockID = 0

        func nextID() -> Int {
            defer { blockID += 1 }
            return blockID
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let current = lines[index]
                    if current.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(current)
                    index += 1
                }
                blocks.append(MarkdownBlock(id: nextID(), kind: .code(codeLines.joined(separator: "\n"), language: language.isEmpty ? nil : language)))
                continue
            }

            if let math = MarkdownMathParser.blockMath(at: index, in: lines) {
                blocks.append(MarkdownBlock(id: nextID(), kind: .math(math.formula)))
                index += math.consumedLineCount
                continue
            }

            if isDivider(trimmed) {
                blocks.append(MarkdownBlock(id: nextID(), kind: .divider))
                index += 1
                continue
            }

            if let heading = heading(from: trimmed) {
                blocks.append(MarkdownBlock(id: nextID(), kind: .heading(heading.text, level: heading.level)))
                index += 1
                continue
            }

            if isTableStart(at: index, lines: lines) {
                var rows: [[String]] = [tableRow(from: lines[index])]
                index += 2
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard current.contains("|"), !current.isEmpty, !isDivider(current) else { break }
                    rows.append(tableRow(from: current))
                    index += 1
                }
                blocks.append(MarkdownBlock(id: nextID(), kind: .table(rows)))
                continue
            }

            if let firstItem = listItem(from: line, itemID: 0) {
                var items = [firstItem]
                index += 1
                while index < lines.count,
                      let item = listItem(from: lines[index], itemID: items.count) {
                    items.append(item)
                    index += 1
                }
                blocks.append(MarkdownBlock(id: nextID(), kind: .list(items)))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines = [String(trimmed.drop(while: { $0 == ">" || $0 == " " }))]
                index += 1
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard current.hasPrefix(">") else { break }
                    quoteLines.append(String(current.drop(while: { $0 == ">" || $0 == " " })))
                    index += 1
                }
                blocks.append(MarkdownBlock(id: nextID(), kind: .quote(quoteLines.joined(separator: "\n"))))
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let current = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !current.isEmpty,
                      !current.hasPrefix("```"),
                      !isDivider(current),
                      heading(from: current) == nil,
                      listItem(from: lines[index], itemID: 0) == nil,
                      !current.hasPrefix(">"),
                      MarkdownMathParser.blockMath(at: index, in: lines) == nil,
                      !isTableStart(at: index, lines: lines) else {
                    break
                }
                paragraphLines.append(current)
                index += 1
            }
            blocks.append(MarkdownBlock(id: nextID(), kind: .paragraph(paragraphLines.joined(separator: " "))))
        }

        return blocks.isEmpty ? [MarkdownBlock(id: 0, kind: .paragraph(text))] : blocks
    }

    private static func heading(from line: String) -> (text: String, level: Int)? {
        guard line.hasPrefix("#") else { return nil }
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let stripped = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? nil : (stripped, level)
    }

    private static func listItem(from line: String, itemID: Int) -> MarkdownListItem? {
        let expanded = line.replacingOccurrences(of: "\t", with: "    ")
        let leadingSpaces = expanded.prefix(while: { $0 == " " }).count
        let content = expanded.trimmingCharacters(in: .whitespaces)
        let level = min(leadingSpaces / 2, 8)

        for marker in ["- ", "* ", "+ "] where content.hasPrefix(marker) {
            return MarkdownListItem(
                id: itemID,
                level: level,
                marker: .unordered,
                text: String(content.dropFirst(marker.count))
            )
        }

        let digits = content.prefix(while: { $0.isNumber })
        guard !digits.isEmpty,
              let number = Int(digits),
              content.dropFirst(digits.count).hasPrefix(". ") else {
            return nil
        }
        return MarkdownListItem(
            id: itemID,
            level: level,
            marker: .ordered(number),
            text: String(content.dropFirst(digits.count + 2))
        )
    }

    private static func isDivider(_ line: String) -> Bool {
        let normalized = line.replacingOccurrences(of: " ", with: "")
        return normalized == "---" || normalized == "***" || normalized == "___"
    }

    private static func isTableStart(at index: Int, lines: [String]) -> Bool {
        guard lines.indices.contains(index + 1) else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard header.contains("|"), separator.contains("|") else { return false }
        let allowed = CharacterSet(charactersIn: "|:- ")
        return separator.unicodeScalars.allSatisfy { allowed.contains($0) } &&
            separator.contains("-")
    }

    private static func tableRow(from line: String) -> [String] {
        var columns = line.split(separator: "|", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if columns.first?.isEmpty == true {
            columns.removeFirst()
        }
        if columns.last?.isEmpty == true {
            columns.removeLast()
        }
        return columns
    }
}

struct MarkdownListItem: Identifiable, Equatable {
    enum Marker: Equatable {
        case unordered
        case ordered(Int)
    }

    let id: Int
    let level: Int
    let marker: Marker
    let text: String
}

struct MarkdownMathBlockParseResult: Equatable {
    let formula: String
    let consumedLineCount: Int
}

enum MarkdownInlineMathSegment: Equatable {
    case text(String)
    case math(String)
}

enum MarkdownMathParser {
    static func blockMath(at index: Int, in lines: [String]) -> MarkdownMathBlockParseResult? {
        guard lines.indices.contains(index) else { return nil }
        let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
        for delimiter in blockDelimiters where trimmed.hasPrefix(delimiter.opener) {
            return parseBlockMath(
                at: index,
                in: lines,
                opener: delimiter.opener,
                closer: delimiter.closer
            )
        }
        return nil
    }

    static func inlineSegments(in text: String) -> [MarkdownInlineMathSegment] {
        guard !text.isEmpty else { return [] }

        var segments: [MarkdownInlineMathSegment] = []
        var segmentStart = text.startIndex
        var index = text.startIndex

        func appendText(upTo end: String.Index) {
            guard segmentStart < end else { return }
            append(.text(String(text[segmentStart..<end])), to: &segments)
        }

        while index < text.endIndex {
            if text[index] == "`" {
                index = indexAfterCodeSpan(startedAt: index, in: text)
                continue
            }

            if let linkEnd = indexAfterMarkdownLink(startedAt: index, in: text) {
                index = linkEnd
                continue
            }

            if isEscapedParenthesisOpener(at: index, in: text),
               let closing = closingEscapedParenthesis(forOpenerAt: index, in: text) {
                let contentStart = text.index(index, offsetBy: 2)
                let formula = normalizedFormula(String(text[contentStart..<closing]))
                if !formula.isEmpty {
                    appendText(upTo: index)
                    append(.math(formula), to: &segments)
                    index = text.index(closing, offsetBy: 2)
                    segmentStart = index
                    continue
                }
            }

            if isDollarMathOpener(at: index, in: text),
               let closing = closingDollar(forOpenerAt: index, in: text) {
                let contentStart = text.index(after: index)
                let formula = normalizedFormula(String(text[contentStart..<closing]))
                appendText(upTo: index)
                append(.math(formula), to: &segments)
                index = text.index(after: closing)
                segmentStart = index
                continue
            }

            index = text.index(after: index)
        }

        appendText(upTo: text.endIndex)
        return segments
    }

    private static let blockDelimiters = [
        (opener: "$$", closer: "$$"),
        (opener: "\\[", closer: "\\]")
    ]

    private static let mathSignalCharacters = CharacterSet(charactersIn: #"\/^_=+\-*<>|{}[]()"#)

    private static func parseBlockMath(
        at index: Int,
        in lines: [String],
        opener: String,
        closer: String
    ) -> MarkdownMathBlockParseResult? {
        let opening = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = String(opening.dropFirst(opener.count))
        if let formula = sameLineBlockFormula(in: remainder, closer: closer) {
            return MarkdownMathBlockParseResult(formula: formula, consumedLineCount: 1)
        }

        var formulaLines: [String] = []
        let firstLine = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !firstLine.isEmpty {
            formulaLines.append(firstLine)
        }

        var cursor = index + 1
        while lines.indices.contains(cursor) {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == closer {
                return MarkdownMathBlockParseResult(
                    formula: normalizedFormula(formulaLines.joined(separator: "\n")),
                    consumedLineCount: cursor - index + 1
                )
            }

            if let closingRange = line.range(of: closer, options: .backwards) {
                let trailing = line[closingRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if trailing.isEmpty {
                    let beforeClose = String(line[..<closingRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !beforeClose.isEmpty {
                        formulaLines.append(beforeClose)
                    }
                    return MarkdownMathBlockParseResult(
                        formula: normalizedFormula(formulaLines.joined(separator: "\n")),
                        consumedLineCount: cursor - index + 1
                    )
                }
            }

            formulaLines.append(line)
            cursor += 1
        }

        return nil
    }

    private static func sameLineBlockFormula(in remainder: String, closer: String) -> String? {
        guard let closingRange = remainder.range(of: closer, options: .backwards) else {
            return nil
        }
        let trailing = remainder[closingRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard trailing.isEmpty else { return nil }
        return normalizedFormula(String(remainder[..<closingRange.lowerBound]))
    }

    private static func append(_ segment: MarkdownInlineMathSegment, to segments: inout [MarkdownInlineMathSegment]) {
        switch (segments.last, segment) {
        case let (.text(existing)?, .text(next)):
            segments[segments.count - 1] = .text(existing + next)
        default:
            segments.append(segment)
        }
    }

    private static func normalizedFormula(_ formula: String) -> String {
        formula.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func indexAfterCodeSpan(startedAt index: String.Index, in text: String) -> String.Index {
        let tickCount = consecutiveCharacterCount("`", from: index, in: text)
        let marker = String(repeating: "`", count: tickCount)
        let searchStart = text.index(index, offsetBy: tickCount)
        guard let closing = text.range(of: marker, range: searchStart..<text.endIndex) else {
            return text.index(after: index)
        }
        return closing.upperBound
    }

    private static func indexAfterMarkdownLink(startedAt index: String.Index, in text: String) -> String.Index? {
        guard text[index] == "[" else { return nil }

        var cursor = text.index(after: index)
        var bracketEnd: String.Index?
        while cursor < text.endIndex {
            if text[cursor] == "\\" {
                cursor = indexAfterEscapedCharacter(at: cursor, in: text) ?? text.index(after: cursor)
                continue
            }
            if text[cursor] == "]" {
                bracketEnd = cursor
                break
            }
            cursor = text.index(after: cursor)
        }

        guard let closingBracket = bracketEnd else { return nil }
        let parenStart = text.index(after: closingBracket)
        guard parenStart < text.endIndex, text[parenStart] == "(" else { return nil }

        cursor = text.index(after: parenStart)
        while cursor < text.endIndex {
            if text[cursor] == "\\" {
                cursor = indexAfterEscapedCharacter(at: cursor, in: text) ?? text.index(after: cursor)
                continue
            }
            if text[cursor] == ")" {
                return text.index(after: cursor)
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func isEscapedParenthesisOpener(at index: String.Index, in text: String) -> Bool {
        guard text[index] == "\\" else { return false }
        let next = text.index(after: index)
        return next < text.endIndex && text[next] == "("
    }

    private static func closingEscapedParenthesis(
        forOpenerAt index: String.Index,
        in text: String
    ) -> String.Index? {
        var cursor = text.index(index, offsetBy: 2)
        while cursor < text.endIndex {
            if text[cursor] == "`" {
                cursor = indexAfterCodeSpan(startedAt: cursor, in: text)
                continue
            }
            if text[cursor] == "\\" {
                let next = text.index(after: cursor)
                if next < text.endIndex, text[next] == ")" {
                    return cursor
                }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func isDollarMathOpener(at index: String.Index, in text: String) -> Bool {
        guard text[index] == "$",
              !isEscaped(index, in: text),
              !isPartOfDoubleDollar(at: index, in: text) else {
            return false
        }
        let next = text.index(after: index)
        guard next < text.endIndex, !text[next].isWhitespace else { return false }
        if let previous = character(before: index, in: text),
           previous.isLetter || previous.isNumber {
            return false
        }
        return true
    }

    private static func closingDollar(forOpenerAt index: String.Index, in text: String) -> String.Index? {
        var cursor = text.index(after: index)
        while cursor < text.endIndex {
            if text[cursor] == "`" {
                cursor = indexAfterCodeSpan(startedAt: cursor, in: text)
                continue
            }

            if text[cursor] == "$", !isEscaped(cursor, in: text), !isPartOfDoubleDollar(at: cursor, in: text) {
                let content = String(text[text.index(after: index)..<cursor])
                return isLikelyDollarFormula(content) ? cursor : nil
            }

            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func isLikelyDollarFormula(_ content: String) -> Bool {
        let trimmed = normalizedFormula(content)
        guard !trimmed.isEmpty,
              trimmed == content,
              !trimmed.contains("\n"),
              !trimmed.contains("$") else {
            return false
        }

        if trimmed.rangeOfCharacter(from: mathSignalCharacters) != nil {
            return true
        }

        let hasLetter = trimmed.rangeOfCharacter(from: .letters) != nil
        let hasDigit = trimmed.rangeOfCharacter(from: .decimalDigits) != nil
        let hasWhitespace = trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
        if hasLetter && !hasWhitespace {
            return true
        }
        return hasDigit && !hasWhitespace
    }

    private static func indexAfterEscapedCharacter(at index: String.Index, in text: String) -> String.Index? {
        guard text[index] == "\\" else { return nil }
        let escaped = text.index(after: index)
        guard escaped < text.endIndex else { return nil }
        return text.index(after: escaped)
    }

    private static func consecutiveCharacterCount(
        _ character: Character,
        from index: String.Index,
        in text: String
    ) -> Int {
        var count = 0
        var cursor = index
        while cursor < text.endIndex, text[cursor] == character {
            count += 1
            cursor = text.index(after: cursor)
        }
        return count
    }

    private static func isEscaped(_ index: String.Index, in text: String) -> Bool {
        var backslashCount = 0
        var cursor = index
        while cursor != text.startIndex {
            let previous = text.index(before: cursor)
            guard text[previous] == "\\" else { break }
            backslashCount += 1
            cursor = previous
        }
        return backslashCount % 2 == 1
    }

    private static func isPartOfDoubleDollar(at index: String.Index, in text: String) -> Bool {
        if let previous = character(before: index, in: text), previous == "$" {
            return true
        }
        let next = text.index(after: index)
        return next < text.endIndex && text[next] == "$"
    }

    private static func character(before index: String.Index, in text: String) -> Character? {
        guard index != text.startIndex else { return nil }
        return text[text.index(before: index)]
    }
}

private struct MarkdownList: View {
    let items: [MarkdownListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Color.clear
                        .frame(width: CGFloat(item.level) * 18)
                    markerView(for: item)
                    InlineMarkdownText(text: item.text)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func markerView(for item: MarkdownListItem) -> some View {
        switch item.marker {
        case .unordered:
            Image(systemName: "circle.fill")
                .font(.system(size: 4, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
        case let .ordered(number):
            Text("\(number).")
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .trailing)
        }
    }
}

private struct MarkdownQuote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Color.brandBlue.opacity(0.55))
                .frame(width: 3)
            InlineMarkdownText(text: text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(.vertical, 2)
    }
}

private struct MarkdownCodeBlock: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language {
                    Text(language.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    Clipboard.copy(code)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Copy Code")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.brandBlack.opacity(0.035))

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct MarkdownMathBlock: View {
    let formula: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MATH")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    Clipboard.copy(formula)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Copy Math")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.brandBlue.opacity(0.06))

            ScrollView(.horizontal, showsIndicators: true) {
                HStack {
                    Spacer(minLength: 0)
                    MathFormulaView(formula: formula)
                        .padding(12)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.brandBlue.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct MarkdownTable: View {
    let rows: [[String]]
    @State private var showingDetail = false

    private var columnCount: Int {
        rows.map(\.count).max() ?? 0
    }

    var body: some View {
        Group {
            if columnCount <= 3 {
                // Narrow tables fill the bubble width and wrap fully —
                // hard 96/128pt caps were truncating every cell with "…".
                tableGrid(cellMaxWidth: .infinity, cellLineLimit: nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    tableGrid(cellMaxWidth: 200, cellLineLimit: 4)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showingDetail = true }
        .sheet(isPresented: $showingDetail) {
            MarkdownTableDetailSheet(rows: rows)
        }
        .accessibilityHint("Tap to view the full table.")
    }

    private func tableGrid(cellMaxWidth: CGFloat?, cellLineLimit: Int?) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { columnIndex in
                        InlineMarkdownText(text: row.indices.contains(columnIndex) ? row[columnIndex] : "")
                            .font(rowIndex == 0 ? .caption.weight(.semibold) : .caption)
                            .foregroundStyle(rowIndex == 0 ? .primary : .secondary)
                            .lineLimit(cellLineLimit)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(
                                minWidth: 64,
                                maxWidth: cellMaxWidth,
                                alignment: .leading
                            )
                            .background(rowIndex == 0 ? Color.brandBlue.opacity(0.08) : Color.clear)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Full-content table view: each row as a key-value card (header column =
/// label), no truncation anywhere. Reached by tapping any inline table.
private struct MarkdownTableDetailSheet: View {
    let rows: [[String]]
    @Environment(\.dismiss) private var dismiss

    private var header: [String] { rows.first ?? [] }
    private var bodyRows: [[String]] { Array(rows.dropFirst()) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(bodyRows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, cell in
                            VStack(alignment: .leading, spacing: 1) {
                                if header.indices.contains(columnIndex) {
                                    Text(header[columnIndex])
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                InlineMarkdownText(text: cell)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Table")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct InlineMarkdownText: View {
    let text: String

    private var attributedText: AttributedString {
        Self.cachedAttributedText(for: text)
    }

    private static let attributedCache: NSCache<NSString, InlineAttributedCacheBox> = {
        let cache = NSCache<NSString, InlineAttributedCacheBox>()
        cache.countLimit = 600
        return cache
    }()

    private static func cachedAttributedText(for text: String) -> AttributedString {
        let key = text as NSString
        if let cached = attributedCache.object(forKey: key) {
            return cached.attributedText
        }
        var attributed = Self.attributedTextWithInlineMath(for: text)
        // Replace "[N]" link runs with a styled circled-digit so
        // citation markers read as numbered pills, not raw "[1]" text.
        // SwiftUI's AttributedString doesn't support inline SF Symbol
        // attachments cleanly, so we use unicode circled digits which
        // render as a small filled glyph and pick up the link tint
        // from `actionPrimary`. Falls back to "[N]" if the index is
        // outside the supported range.
        attributed = Self.styleCitationRuns(in: attributed)
        attributedCache.setObject(InlineAttributedCacheBox(attributedText: attributed), forKey: key)
        return attributed
    }

    private static func attributedTextWithInlineMath(for text: String) -> AttributedString {
        let segments = MarkdownMathParser.inlineSegments(in: text)
        guard segments.contains(where: { segment in
            if case .math = segment { return true }
            return false
        }) else {
            return sanitizedMarkdownAttributedText(for: text)
        }

        var output = AttributedString()
        for segment in segments {
            switch segment {
            case let .text(value):
                output += sanitizedMarkdownAttributedText(for: value)
            case let .math(formula):
                let model = MathFormulaRenderModel.build(from: formula)
                if let math = model.inlineAttributedString() {
                    output += math
                } else {
                    var fallback = AttributedString(" \(formula) ")
                    fallback.inlinePresentationIntent = .code
                    fallback.foregroundColor = .actionPrimary
                    fallback.backgroundColor = Color.actionPrimary.opacity(0.10)
                    output += fallback
                }
            }
        }
        return output
    }

    private static func sanitizedMarkdownAttributedText(for text: String) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        for run in attributed.runs {
            guard let url = run.link, !Self.isSafeInlineURL(url) else { continue }
            attributed[run.range].link = nil
        }
        return attributed
    }

    private static func styleCitationRuns(in input: AttributedString) -> AttributedString {
        var output = input
        for run in output.runs {
            guard run.link != nil else { continue }
            let segment = String(output.characters[run.range])
            guard let glyph = citationGlyph(for: segment) else { continue }
            var replacement = AttributedString(glyph)
            replacement.font = .body.weight(.bold)
            replacement.foregroundColor = .actionPrimary
            replacement.link = run.link
            output.replaceSubrange(run.range, with: replacement)
        }
        return output
    }

    private static func citationGlyph(for displayText: String) -> String? {
        // Matches "[1]" / "[12]" / " [1]" — link text after our
        // linkCitationMarkers pass. Returns a unicode circled digit
        // (1-20) sized to the surrounding font.
        let trimmed = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        let inner = trimmed.dropFirst().dropLast()
        guard let value = Int(inner), value >= 1 else { return nil }
        let circled: [String] = [
            "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩",
            "⑪", "⑫", "⑬", "⑭", "⑮", "⑯", "⑰", "⑱", "⑲", "⑳"
        ]
        if value <= circled.count {
            return circled[value - 1]
        }
        return nil
    }

    private static func isSafeInlineURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }
        return true
    }

    var body: some View {
        Text(attributedText)
    }
}

private final class InlineAttributedCacheBox {
    let attributedText: AttributedString

    init(attributedText: AttributedString) {
        self.attributedText = attributedText
    }
}

struct SearchContextStrip: View {
    let query: String?
    let sources: [WebSearchSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.trustVerified.opacity(0.20))
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.trustVerified)
                }
                .frame(width: 22, height: 22)
                Text("Sources checked")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(headerText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(sources.prefix(4).enumerated()), id: \.element.id) { index, source in
                        if let url = source.safeURL {
                            Link(destination: url) {
                                SourcePill(index: index + 1, source: source)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if sources.count > 4 {
                        Text("\(sources.count - 4) more")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color.appPanelBackground, in: Capsule())
                    }

                    if !sources.isEmpty {
                        NavigationLink {
                            SourcesDetailView(query: query, sources: sources)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "list.bullet.rectangle")
                                    .font(.caption2.weight(.bold))
                                Text("View all")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(Color.actionPrimary)
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(Color.actionPrimary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: 620, alignment: .leading)
        .background(Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder.opacity(0.8), lineWidth: 1)
        )
    }

    private var headerText: String {
        let countLabel = "\(sources.count) source\(sources.count == 1 ? "" : "s")"
        guard let query = displayQuery, !query.isEmpty else {
            return countLabel
        }
        return "\(countLabel) · \(query)"
    }

    private var displayQuery: String? {
        guard var value = query?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        if let range = value.range(of: "Mission brief from phone:", options: .caseInsensitive) {
            value = String(value[range.upperBound...])
        }
        if let range = value.range(of: "Execution contract:", options: .caseInsensitive) {
            value = String(value[..<range.lowerBound])
        }
        value = value
            .replacingOccurrences(
                of: #"(?i)^(?:Agent|Hosted IronClaw) Mission:\s*(?:[^:]+:\s*)?"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count > 96 {
            return "\(value.prefix(93))..."
        }
        return value.isEmpty ? nil : value
    }
}

private struct SourcePill: View {
    let index: Int
    let source: WebSearchSource

    var body: some View {
        HStack(spacing: 7) {
            Text("[\(index)]")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(Color.trustVerified)
            SourceLogo(source: source, fallbackText: "\(index)")
            Text(source.host)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.leading, 7)
        .padding(.trailing, 11)
        .frame(height: 34)
        .background(Color.appPanelBackground, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.appBorder.opacity(0.55), lineWidth: 1)
        }
        .accessibilityLabel("Source \(index), \(source.title ?? source.host)")
    }
}

private struct SourceLogo: View {
    let source: WebSearchSource
    let fallbackText: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.appSecondaryBackground)
            fallback
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.appBorder.opacity(0.65), lineWidth: 1)
        }
    }

    private var fallback: some View {
        Text(fallbackLabel)
            .font(fallbackFont)
            .foregroundStyle(Color.trustVerified)
    }

    private var fallbackLabel: String {
        source.sourceInitials == "#" ? fallbackText : source.sourceInitials
    }

    private var fallbackFont: Font {
        fallbackLabel == fallbackText
            ? .caption2.monospacedDigit().weight(.bold)
            : .caption2.weight(.bold)
    }
}

struct SourcesDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let query: String?
    let sources: [WebSearchSource]

    var body: some View {
        NavigationStack {
            List {
                if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
                    Section {
                        Text(query)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Search")
                    }
                }

                Section {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                        if let url = source.safeURL {
                            Link(destination: url) {
                                HStack(spacing: 11) {
                                    SourceLogo(source: source, fallbackText: "\(index + 1)")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(source.displayTitle)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        Text(source.displaySubtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.actionPrimary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("\(sources.count) linked source\(sources.count == 1 ? "" : "s")")
                }
            }
            .navigationTitle("Sources")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .platformMediumDetent()
    }
}

struct TypingDots: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.brandBlue)
                    .frame(width: 5, height: 5)
                    .opacity(pulse ? 0.35 : 1)
                    .animation(
                        .easeInOut(duration: 0.7)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: pulse
                    )
            }
        }
        .onAppear {
            pulse = true
        }
    }
}
