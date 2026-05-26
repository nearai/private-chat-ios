import SwiftUI

struct MarkdownMessageText: View {
    let text: String
    let sources: [WebSearchSource]

    init(text: String, sources: [WebSearchSource] = []) {
        self.text = text
        self.sources = sources
    }

    private var blocks: [MarkdownBlock] {
        MarkdownBlock.parse(Self.normalizedMarkdown(text, sources: sources))
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
                case let .unorderedList(items):
                    MarkdownBulletList(items: items)
                case let .orderedList(items):
                    MarkdownNumberedList(items: items)
                case let .quote(value):
                    MarkdownQuote(text: value)
                case let .code(code, language):
                    MarkdownCodeBlock(code: code, language: language)
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

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case paragraph(String)
        case heading(String, level: Int)
        case unorderedList([String])
        case orderedList([(Int, String)])
        case quote(String)
        case code(String, language: String?)
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

            if let firstItem = unorderedListItem(from: trimmed) {
                var items = [firstItem]
                index += 1
                while index < lines.count,
                      let item = unorderedListItem(from: lines[index].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(MarkdownBlock(id: nextID(), kind: .unorderedList(items)))
                continue
            }

            if let firstItem = orderedListItem(from: trimmed) {
                var items = [firstItem]
                index += 1
                while index < lines.count,
                      let item = orderedListItem(from: lines[index].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(MarkdownBlock(id: nextID(), kind: .orderedList(items)))
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
                      unorderedListItem(from: current) == nil,
                      orderedListItem(from: current) == nil,
                      !current.hasPrefix(">"),
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

    private static func unorderedListItem(from line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedListItem(from line: String) -> (Int, String)? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty,
              let number = Int(digits),
              line.dropFirst(digits.count).hasPrefix(". ") else {
            return nil
        }
        return (number, String(line.dropFirst(digits.count + 2)))
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

private struct MarkdownBulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4, weight: .bold))
                        .foregroundStyle(.secondary)
                    InlineMarkdownText(text: item)
                        .lineSpacing(2)
                }
            }
        }
    }
}

private struct MarkdownNumberedList: View {
    let items: [(Int, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(item.0).")
                        .font(.callout.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 22, alignment: .trailing)
                    InlineMarkdownText(text: item.1)
                        .lineSpacing(2)
                }
            }
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

private struct MarkdownTable: View {
    let rows: [[String]]

    private var columnCount: Int {
        rows.map(\.count).max() ?? 0
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { columnIndex in
                            InlineMarkdownText(text: row.indices.contains(columnIndex) ? row[columnIndex] : "")
                                .font(rowIndex == 0 ? .caption.weight(.semibold) : .caption)
                                .foregroundStyle(rowIndex == 0 ? .primary : .secondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(
                                    minWidth: columnIndex == 0 ? 74 : 92,
                                    maxWidth: columnIndex == 0 ? 96 : 128,
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
}

private struct InlineMarkdownText: View {
    let text: String

    private var attributedText: AttributedString {
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
                of: #"(?i)^(?:IronClaw Agent|Hosted IronClaw) Mission:\s*(?:[^:]+:\s*)?"#,
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
            if let faviconURL {
                AsyncImage(url: faviconURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(3)
                    case .failure, .empty:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
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

    private var faviconURL: URL? {
        guard let encodedHost = source.host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(encodedHost)")
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
