import Foundation

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

