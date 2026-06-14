import SwiftUI

struct MarkdownMessageText: View {
    let text: String
    let sources: [WebSearchSource]
    let textSelectionEnabled: Bool

    init(text: String, sources: [WebSearchSource] = [], textSelectionEnabled: Bool = true) {
        self.text = text
        self.sources = sources
        self.textSelectionEnabled = textSelectionEnabled
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
        if textSelectionEnabled {
            content
                .textSelection(.enabled)
        } else {
            content
        }
    }

    private var content: some View {
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
    }
}

private final class MarkdownBlockCacheBox {
    let blocks: [MarkdownBlock]

    init(blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }
}

private struct MarkdownList: View {
    let items: [MarkdownListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    markerView(for: item)
                    InlineMarkdownText(text: item.text)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Indent per nesting level via padding, not a flexible
                // Color.clear spacer — that spacer had no fixed height and
                // collapsed baseline-aligned rows on top of each other.
                .padding(.leading, CGFloat(item.level) * 18)
            }
        }
    }

    @ViewBuilder
    private func markerView(for item: MarkdownListItem) -> some View {
        switch item.marker {
        case .unordered:
            Circle()
                .fill(.secondary)
                .frame(width: 4, height: 4)
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
                .fill(Color.brandAccent.opacity(0.55))
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
                        .minimumTouchTarget()
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
        .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.pill))
        .overlay(
            RoundedRectangle.app(AppRadius.pill)
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
                        .minimumTouchTarget()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Copy Math")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.brandAccent.opacity(0.06))

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
        .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.pill))
        .overlay(
            RoundedRectangle.app(AppRadius.pill)
                .stroke(Color.brandAccent.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct MarkdownTable: View {
    let rows: [[String]]
    @State private var showingDetail = false

    private var columnCount: Int {
        rows.map(\.count).max() ?? 0
    }

    private var header: [String] {
        rows.first ?? []
    }

    private var bodyRows: [[String]] {
        rows.count > 1 ? Array(rows.dropFirst()) : rows
    }

    var body: some View {
        Group {
            if columnCount <= 2 {
                // Narrow tables fill the bubble width and wrap fully —
                // hard 96/128pt caps were truncating every cell with "…".
                tableGrid(cellMaxWidth: .infinity)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                stackedRows
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showingDetail = true }
        .sheet(isPresented: $showingDetail) {
            MarkdownTableDetailSheet(rows: rows)
        }
        .accessibilityHint("Tap to view the full table.")
    }

    private var stackedRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(bodyRows.enumerated()), id: \.offset) { rowIndex, row in
                if rowIndex > 0 {
                    Divider()
                        .padding(.horizontal, 10)
                }

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(0..<columnCount, id: \.self) { columnIndex in
                        let title = header.indices.contains(columnIndex) && !header[columnIndex].isEmpty
                            ? header[columnIndex]
                            : "Column \(columnIndex + 1)"
                        let value = row.indices.contains(columnIndex) ? row[columnIndex] : ""
                        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                InlineMarkdownText(text: value)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.brandAccent.opacity(0.035))
            }
        }
        .overlay(
            RoundedRectangle.app(AppRadius.pill)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle.app(AppRadius.pill))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("markdown.table.stacked")
    }

    private func tableGrid(cellMaxWidth: CGFloat?) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { columnIndex in
                        InlineMarkdownText(text: row.indices.contains(columnIndex) ? row[columnIndex] : "")
                            .font(rowIndex == 0 ? .caption.weight(.semibold) : .caption)
                            .foregroundStyle(rowIndex == 0 ? .primary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(
                                minWidth: 64,
                                maxWidth: cellMaxWidth,
                                alignment: .leading
                            )
                            .background(rowIndex == 0 ? Color.brandAccent.opacity(0.08) : Color.clear)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle.app(AppRadius.pill)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle.app(AppRadius.pill))
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.trustVerified)
                    .frame(width: 22, height: 22)
                    .background(Color.trustVerified.opacity(0.12), in: Circle())

                ForEach(Array(sources.prefix(4).enumerated()), id: \.element.id) { index, source in
                    if let url = source.safeURL {
                        Link(destination: url) {
                            SourcePill(index: index + 1, source: source)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if sources.count > 4 {
                    Text("+\(sources.count - 4)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(Color.appPanelBackground, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.appBorder.opacity(0.45), lineWidth: 1)
                        }
                }

                if !sources.isEmpty {
                    NavigationLink {
                        SourcesDetailView(query: query, sources: sources)
                    } label: {
                        HStack(spacing: 4) {
                            Text("All")
                                .font(.caption2.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(Color.actionPrimary)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(Color.actionPrimary.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, 2)
        }
        .frame(maxWidth: 620, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sources checked, \(headerText)")
    }

    private var headerText: String {
        let countLabel = "\(sources.count) source\(sources.count == 1 ? "" : "s")"
        guard let query = SourceSearchDisplay(query: query).summary, !query.isEmpty else {
            return countLabel
        }
        return "\(countLabel) · \(query)"
    }
}

struct SourceSearchDisplay: Equatable {
    let summary: String?
    let queries: [String]

    init(query: String?) {
        guard let cleaned = Self.cleanedQuery(query) else {
            summary = nil
            queries = []
            return
        }
        let parts = Self.queryParts(from: cleaned)
        queries = parts
        summary = parts.isEmpty ? cleaned : parts.joined(separator: " · ")
    }

    private static func cleanedQuery(_ query: String?) -> String? {
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
        return value.isEmpty ? nil : value
    }

    private static func queryParts(from value: String) -> [String] {
        var seen = Set<String>()
        return value
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { part in
                let key = part.lowercased()
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
    }
}

private struct SourcePill: View {
    let index: Int
    let source: WebSearchSource

    var body: some View {
        HStack(spacing: 5) {
            SourceLogo(source: source, fallbackText: "\(index)", size: 16)
            Text(source.host)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .frame(height: 28)
        .background(Color.appPanelBackground, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.appBorder.opacity(0.45), lineWidth: 1)
        }
        .accessibilityLabel("Source \(index), \(source.title ?? source.host)")
    }
}

private struct SourceLogo: View {
    let source: WebSearchSource
    let fallbackText: String
    var size: CGFloat = 22

    var body: some View {
        SourceFaviconView(
            domain: source.host,
            size: size,
            fallbackText: fallbackLabel,
            cornerRadius: size / 2,
            borderColor: Color.appBorder.opacity(0.65),
            borderWidth: 1,
            allowsNetworkFavicon: source.allowsNetworkFavicon
        )
    }

    private var fallbackLabel: String {
        let label = source.sourceInitials == "#" ? fallbackText : source.sourceInitials
        return String(label.prefix(1))
    }
}

struct SourcesDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let query: String?
    let sources: [WebSearchSource]

    var body: some View {
        let searchDisplay = SourceSearchDisplay(query: query)

        NavigationStack {
            List {
                if !searchDisplay.queries.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(searchDisplay.queries, id: \.self) { query in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.actionPrimary)
                                        .frame(width: 18, height: 18)
                                    Text(query)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.actionPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .padding(.vertical, 2)
                    } header: {
                        Text(searchDisplay.queries.count == 1 ? "Search" : "Searches")
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
                            .accessibilityIdentifier("sources.detail.row.\(index + 1)")
                        }
                    }
                } header: {
                    Text("\(sources.count) linked source\(sources.count == 1 ? "" : "s")")
                }
            }
            .accessibilityIdentifier("sources.detail")
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
                    .fill(Color.brandAccent)
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
