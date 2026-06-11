import SwiftUI

#if DEBUG
struct DemoCouncilComparisonView: View {
    @EnvironmentObject private var chatStore: ChatStore

    private var councilMessages: [ChatMessage] {
        let messages = chatStore.messages.filter { $0.councilBatchID?.isEmpty == false }
        return messages.sorted { $0.createdAt < $1.createdAt }
    }

    private var synthesis: ChatMessage? {
        councilMessages.first { $0.model == ModelOption.llmCouncilSynthesisModelID } ?? councilMessages.first
    }

    private var rawModels: [ChatMessage] {
        councilMessages.filter { $0.model != ModelOption.llmCouncilSynthesisModelID }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                            .id("top")

                        if let synthesis {
                            CouncilFocusedCard(
                                title: "Synthesis",
                                subtitle: "Combined answer with visible disagreement",
                                symbolName: "sparkles",
                                tint: .actionPrimary,
                                text: synthesis.text,
                                sources: synthesis.sources,
                                searchQuery: synthesis.searchQuery
                            )
                            .id("synthesis")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Model Differences")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            ForEach(rawModels) { message in
                                CouncilFocusedCard(
                                    title: message.modelDisplayName,
                                    subtitle: modelAngle(for: message),
                                    symbolName: "cpu",
                                    tint: .trustVerified,
                                    text: message.text,
                                    sources: message.sources,
                                    searchQuery: message.searchQuery
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
                .background(Color.appBackground)
                .navigationTitle("Council")
                .platformInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {}
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Image(systemName: "rectangle.expand.vertical")
                            .foregroundStyle(Color.actionPrimary)
                            .accessibilityLabel("Expanded Council output")
                    }
                }
                .task {
                    guard let last = rawModels.last else { return }
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 2.6)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Same prompt. Three model views. One synthesis.", systemImage: "square.grid.2x2")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("The comparison shows why Council is useful: it exposes disagreement before turning it into a better answer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modelAngle(for message: ChatMessage) -> String {
        switch message.model {
        case ChatStore.defaultModelID:
            return "Private model answer"
        case "near-cloud/anthropic/claude-sonnet-4-6":
            return "NEAR AI Cloud answer"
        case "near-cloud/Qwen/Qwen3.6-35B-A3B-FP8":
            return "NEAR AI Cloud answer"
        default:
            return "Raw model view"
        }
    }
}

struct DemoIronClawResultView: View {
    @EnvironmentObject private var chatStore: ChatStore

    private var userMessage: ChatMessage? {
        chatStore.messages.first { $0.role == .user }
    }

    private var resultMessage: ChatMessage? {
        chatStore.messages.first { $0.role == .assistant && $0.model == ModelOption.ironclawModelID }
            ?? chatStore.messages.last { $0.role == .assistant }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                            .id("top")

                        if let userMessage {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Task")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                Text(userMessage.text)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        if let resultMessage {
                            CouncilFocusedCard(
                                title: "Hosted IronClaw",
                                subtitle: "Completed agent output returned to chat",
                                symbolName: "terminal",
                                tint: .actionPrimary,
                                text: resultMessage.text,
                                sources: resultMessage.sources,
                                searchQuery: resultMessage.searchQuery
                            )
                            .id("result")
                        }

                        HStack(spacing: 8) {
                            Label("IronClaw Reborn Plan", systemImage: "folder")
                            Label("reborn-project-plan.md", systemImage: "paperclip")
                            Label("3 PRs", systemImage: "link")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .id("bottom")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
                .background(Color.appBackground)
                .navigationTitle("IronClaw")
                .platformInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {}
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Image(systemName: "rectangle.expand.vertical")
                            .foregroundStyle(Color.actionPrimary)
                            .accessibilityLabel("Expanded IronClaw output")
                    }
                }
                .task {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 2.8)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("IronClaw ran against project context.", systemImage: "terminal")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("This is the completed Hosted IronClaw result, not a setup screen. It updates the attached plan from the latest IronClaw GitHub PRs and returns the artifact into the conversation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CouncilFocusedCard: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color
    let text: String
    var sources: [WebSearchSource] = []
    var searchQuery: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            MarkdownMessageText(text: text, sources: sources)
                .font(.subheadline)
                .lineSpacing(2)

            if !sources.isEmpty {
                SearchContextStrip(query: searchQuery, sources: sources)
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}
#endif
