import SwiftUI

enum CouncilSynthesisSections {
    enum Kind: CaseIterable, Hashable {
        case directAnswer
        case agreement
        case disagreement
        case nextStep

        var heading: String {
            switch self {
            case .directAnswer:
                return "Direct answer"
            case .agreement:
                return "What the council agrees on"
            case .disagreement:
                return "Disagreements or uncertainty"
            case .nextStep:
                return "Recommended next step"
            }
        }

        var chipTitle: String? {
            switch self {
            case .directAnswer:
                return nil
            case .agreement:
                return "Agreement"
            case .disagreement:
                return "Disagreements"
            case .nextStep:
                return "Next step"
            }
        }
    }

    struct ParsedSection: Identifiable, Equatable {
        let kind: Kind
        let text: String

        var id: Kind { kind }
    }

    static func split(_ markdown: String) -> [ParsedSection] {
        var currentKind: Kind = .directAnswer
        var buckets = Dictionary(uniqueKeysWithValues: Kind.allCases.map { ($0, [String]()) })

        for line in markdown.components(separatedBy: .newlines) {
            if let headingKind = kind(forHeadingLine: line) {
                currentKind = headingKind
                continue
            }
            buckets[currentKind, default: []].append(line)
        }

        return Kind.allCases.compactMap { kind in
            let text = (buckets[kind] ?? [])
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return ParsedSection(kind: kind, text: text)
        }
    }

    static func text(in sections: [ParsedSection], for kind: Kind) -> String {
        sections.first(where: { $0.kind == kind })?.text ?? ""
    }

    private static func kind(forHeadingLine line: String) -> Kind? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("## ") else { return nil }
        let heading = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        return Kind.allCases.first { $0.heading == heading }
    }
}

struct CouncilAnswerTabModel {
    let tabs: [CouncilAnswerTab]
    let defaultTabID: String?
    let sources: [WebSearchSource]
    let sourceAttributions: [String: [String]]

    static func build(from messages: [ChatMessage]) -> CouncilAnswerTabModel {
        let synthesis = messages
            .filter(\.isCouncilSynthesisMessage)
            .sorted { $0.createdAt < $1.createdAt }
            .last
        let memberMessages = messages.filter { !$0.isCouncilSynthesisMessage }
        let sources = uniqueSources(in: messages)

        var tabs = [CouncilAnswerTab]()
        if let synthesis {
            tabs.append(.synthesis(messageID: synthesis.id))
        }
        tabs.append(contentsOf: memberMessages.map { .model(messageID: $0.id, label: $0.modelDisplayName) })
        if !sources.isEmpty {
            tabs.append(.sources)
        }

        return CouncilAnswerTabModel(
            tabs: tabs,
            defaultTabID: tabs.first?.id,
            sources: sources,
            sourceAttributions: sourceAttributions(in: memberMessages)
        )
    }

    private static func uniqueSources(in messages: [ChatMessage]) -> [WebSearchSource] {
        var seen = Set<String>()
        var unique = [WebSearchSource]()
        for source in messages.flatMap(\.sources) {
            let key = source.safeURL?.absoluteString ?? source.url
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(source)
        }
        return unique
    }

    static func sourceAttributions(in messages: [ChatMessage]) -> [String: [String]] {
        var attributions = [String: [String]]()
        var seen = [String: Set<String>]()
        for message in messages {
            let modelName = message.modelDisplayName
            for source in message.sources {
                let key = source.safeURL?.absoluteString ?? source.url
                if seen[key, default: []].contains(modelName) {
                    continue
                }
                seen[key, default: []].insert(modelName)
                attributions[key, default: []].append(modelName)
            }
        }
        return attributions
    }
}

struct CouncilAnswerTab: Identifiable, Equatable {
    enum Kind: Equatable {
        case synthesis
        case model
        case sources
    }

    let id: String
    let kind: Kind
    let label: String
    let messageID: String?

    var displayLabel: String {
        switch kind {
        case .model:
            return Self.compactModelLabel(label)
        case .synthesis, .sources:
            return label
        }
    }

    static func synthesis(messageID: String) -> CouncilAnswerTab {
        CouncilAnswerTab(id: "synthesis", kind: .synthesis, label: "Synthesis", messageID: messageID)
    }

    static func model(messageID: String, label: String) -> CouncilAnswerTab {
        CouncilAnswerTab(id: "model-\(messageID)", kind: .model, label: label, messageID: messageID)
    }

    static var sources: CouncilAnswerTab {
        CouncilAnswerTab(id: "sources", kind: .sources, label: "Sources", messageID: nil)
    }

    static func compactModelLabel(_ rawLabel: String) -> String {
        let label = rawLabel
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return "Model" }

        let lowercased = label.lowercased()
        if lowercased.contains("glm") {
            if let version = versionText(in: label) {
                return "GLM \(version)"
            }
            return "GLM"
        }
        if lowercased.contains("qwen") {
            if lowercased.contains("vl") {
                return "Qwen VL"
            }
            if let version = versionText(in: label) {
                return "Qwen \(version)"
            }
            return "Qwen"
        }
        if lowercased.contains("deepseek") {
            if let version = versionText(in: label) {
                return "DeepSeek \(version)"
            }
            return "DeepSeek"
        }
        if lowercased.contains("claude") || lowercased.contains("sonnet") || lowercased.contains("opus") {
            if lowercased.contains("opus"), let version = versionText(in: label) {
                return "Opus \(version)"
            }
            if lowercased.contains("sonnet"), let version = versionText(in: label) {
                return "Sonnet \(version)"
            }
            if let version = versionText(in: label) {
                return "Claude \(version)"
            }
        }
        if label.count <= 16 {
            return label
        }
        let tokens = label.split(separator: " ").filter { token in
            !["FP8", "A3B", "A10B", "Instruct", "2507"].contains(String(token))
        }
        let shortened = tokens.prefix(2).joined(separator: " ")
        if !shortened.isEmpty, shortened.count <= 18 {
            return shortened
        }
        return String(label.prefix(15)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func versionText(in label: String) -> String? {
        let pattern = #"(?i)(?:v)?(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              let range = Range(match.range(at: 1), in: label) else {
            return nil
        }
        return String(label[range])
    }
}

struct CouncilAnswerTabs: View {
    let messages: [ChatMessage]
    let chatStore: ChatStore

    @State private var selectedTabID: String?
    @State private var expandedSections = Set<CouncilSynthesisSections.Kind>()
    @State private var tappedSource: SourceSheetPresentation?

    private var tabModel: CouncilAnswerTabModel {
        CouncilAnswerTabModel.build(from: messages)
    }

    private var selectedTab: CouncilAnswerTab? {
        let tabs = tabModel.tabs
        guard !tabs.isEmpty else { return nil }
        let currentID = selectedTabID ?? tabModel.defaultTabID
        return tabs.first(where: { $0.id == currentID }) ?? tabs.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            tabStrip

            if let selectedTab {
                tabContent(for: selectedTab)
            }
        }
        .onAppear {
            selectedTabID = selectedTabID ?? tabModel.defaultTabID
        }
        .onChange(of: tabModel.tabs.map(\.id)) { _, tabIDs in
            guard let selectedTabID, tabIDs.contains(selectedTabID) else {
                self.selectedTabID = tabModel.defaultTabID
                return
            }
        }
        .sheet(item: $tappedSource) { presentation in
            SourceSheet(index: presentation.index + 1, source: presentation.source)
        }
    }

    private var tabStrip: some View {
        ChipFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(tabModel.tabs) { tab in
                CouncilAnswerTabButton(
                    title: tab.displayLabel,
                    accessibilityLabel: tab.label,
                    isSelected: tab.id == selectedTab?.id
                ) {
                    selectedTabID = tab.id
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func tabContent(for tab: CouncilAnswerTab) -> some View {
        switch tab.kind {
        case .synthesis:
            if let message = message(for: tab) {
                CouncilSynthesisTabContent(
                    message: message,
                    expandedSections: $expandedSections
                )
            }
        case .model:
            if let message = message(for: tab) {
                MessageBubble(message: message, chatStore: chatStore)
            }
        case .sources:
            CouncilSourcesTabContent(
                sources: tabModel.sources,
                sourceAttributions: tabModel.sourceAttributions
            ) { index in
                tappedSource = SourceSheetPresentation(index: index, source: tabModel.sources[index])
            }
        }
    }

    private func message(for tab: CouncilAnswerTab) -> ChatMessage? {
        guard let messageID = tab.messageID else { return nil }
        return messages.first(where: { $0.id == messageID })
    }
}

private struct CouncilAnswerTabButton: View {
    let title: String
    let accessibilityLabel: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? Color.white : Color.routeCouncil)
                .padding(.horizontal, 13)
                .frame(maxWidth: 118)
                .frame(minHeight: 44)
                .background(isSelected ? Color.actionPrimary : Color.clear, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.routeCouncil.opacity(isSelected ? 0 : 0.45), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("council.tab.\(accessibilityName)")
    }

    private var accessibilityName: String {
        let folded = title
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
        return String(folded)
            .split(separator: "-")
            .joined(separator: "-")
    }
}

private struct CouncilSynthesisTabContent: View {
    let message: ChatMessage
    @Binding var expandedSections: Set<CouncilSynthesisSections.Kind>

    private var sections: [CouncilSynthesisSections.ParsedSection] {
        CouncilSynthesisSections.split(message.text)
    }

    private var directAnswer: String {
        CouncilSynthesisSections.text(in: sections, for: .directAnswer)
    }

    private var chipSections: [CouncilSynthesisSections.Kind] {
        [.agreement, .disagreement, .nextStep].filter {
            !CouncilSynthesisSections.text(in: sections, for: $0).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !chipSections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chipSections, id: \.self) { section in
                            CouncilSynthesisChip(
                                title: section.chipTitle ?? section.heading,
                                isSelected: expandedSections.contains(section)
                            ) {
                                if expandedSections.contains(section) {
                                    expandedSections.remove(section)
                                } else {
                                    expandedSections.insert(section)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 2)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                MarkdownMessageText(
                    text: directAnswer.isEmpty ? message.text : directAnswer,
                    sources: message.sources
                )

                ForEach(chipSections, id: \.self) { section in
                    if expandedSections.contains(section) {
                        MarkdownMessageText(
                            text: expandedText(for: section),
                            sources: message.sources
                        )
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func expandedText(for section: CouncilSynthesisSections.Kind) -> String {
        let text = CouncilSynthesisSections.text(in: sections, for: section)
        return "## \(section.heading)\n\(text)"
    }
}

private struct CouncilSynthesisChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : Color.routeCouncil)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(isSelected ? Color.actionPrimary : Color.clear, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.routeCouncil.opacity(isSelected ? 0 : 0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct CouncilSourcesTabContent: View {
    let sources: [WebSearchSource]
    let sourceAttributions: [String: [String]]
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SourceCarousel(sources: sources, onSelect: onSelect)
            if !attributionLines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(attributionLines, id: \.source.id) { line in
                        Text(line.text)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var attributionLines: [(source: WebSearchSource, text: String)] {
        sources.compactMap { source in
            let key = source.safeURL?.absoluteString ?? source.url
            guard let models = sourceAttributions[key], !models.isEmpty else { return nil }
            return (source, "\(source.host) · cited by \(models.joined(separator: ", "))")
        }
    }
}

private extension ChatMessage {
    var isCouncilSynthesisMessage: Bool {
        guard let modelID = model?.trimmingCharacters(in: .whitespacesAndNewlines),
              !modelID.isEmpty else {
            return false
        }
        return modelID == ModelOption.llmCouncilSynthesisModelID ||
            modelID.localizedCaseInsensitiveContains("council/synthesis") ||
            modelID.localizedCaseInsensitiveContains("synthesis")
    }
}
