import SwiftUI

#if DEBUG
struct DemoFileAttachmentFlowView: View {
    @State private var phase = 0

    private let files = [
        ("reborn-project-plan.md", "Markdown plan · 42 KB", "doc.text"),
        ("latest-ironclaw-prs.json", "GitHub PR snapshot · 19 KB", "curlybraces")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if phase < 2 {
                    List {
                        Section {
                            ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                                HStack(spacing: 12) {
                                    Image(systemName: file.2)
                                        .font(.headline.weight(.medium))
                                        .foregroundStyle(Color.actionPrimary)
                                        .frame(width: 34, height: 34)
                                        .background(Color.actionPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.0)
                                            .font(.subheadline.weight(.semibold))
                                        Text(file.1)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: index <= phase ? "checkmark.circle.fill" : "circle")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(index <= phase ? Color.trustVerified : Color.secondary)
                                }
                                .frame(height: 52)
                            }
                        } header: {
                            Text("iCloud Drive / IronClaw Reborn")
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationTitle("Files")
                    .platformInlineNavigationTitle()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {}
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(phase >= 1 ? "Open" : "Add") {}
                                .fontWeight(.semibold)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("New chat")
                                .font(.headline.weight(.semibold))
                            Spacer()
                            ComposerRouteChip(title: "Hosted IronClaw", symbolName: "terminal", isActive: true, showsChevron: true)
                        }

                        Text("Attached from Files")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        VStack(spacing: 8) {
                            ForEach(files, id: \.0) { file in
                                HStack(spacing: 10) {
                                    Image(systemName: file.2)
                                        .foregroundStyle(Color.actionPrimary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(file.0)
                                            .font(.subheadline.weight(.semibold))
                                        Text(file.1)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.appBorder, lineWidth: 1)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Update this project plan based on the latest IronClaw PRs.")
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            HStack {
                                Image(systemName: "paperclip")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "arrow.up")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.actionPrimary, in: Circle())
                            }
                        }

                        Spacer()
                    }
                    .padding(18)
                    .background(Color.appBackground)
                    .navigationTitle("New chat")
                    .platformInlineNavigationTitle()
                }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    phase = 1
                }
            }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                    phase = 2
                }
            }
        }
    }
}

struct DemoPrivateAnswerView: View {
    @EnvironmentObject private var chatStore: ChatStore

    private var answer: ChatMessage? {
        chatStore.messages.first { $0.role == .assistant && $0.model == ChatStore.defaultModelID }
            ?? chatStore.messages.last { $0.role == .assistant }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let user = chatStore.messages.first(where: { $0.role == .user }) {
                            HStack {
                                Spacer(minLength: 44)
                                Text(user.text)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 11)
                                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .id("top")
                        }

                        if let answer {
                            HStack(alignment: .top, spacing: 10) {
                                AssistantAvatar()
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 10) {
                                    MarkdownMessageText(
                                        text: answer.text,
                                        sources: answer.sources,
                                        textSelectionEnabled: false
                                    )
                                        .font(.body)

                                    SearchContextStrip(query: answer.searchQuery, sources: answer.sources)
                                        .id("sources")

                                    DemoAnswerStatusFooter(sourceCount: answer.sources.count)
                                        .id("proof")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
                .background(Color.appBackground)
                .navigationTitle(conversationTitle)
                .platformInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: {}) {
                            Image(systemName: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityLabel("Back")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {}) {
                            Image(systemName: "ellipsis")
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityLabel("More")
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    DemoThreadComposerBar(projectName: "IronClaw Reborn Plan")
                }
                .task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 2.8)) {
                            proxy.scrollTo("proof", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var conversationTitle: String {
        let title = chatStore.selectedConversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Iran war status today" : title
    }
}

private struct DemoThreadComposerBar: View {
    let projectName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                ComposerRouteChip(
                    title: "Private + Cloud",
                    symbolName: "lock.shield",
                    isActive: false,
                    showsChevron: true
                )
                ComposerRouteChip(
                    title: projectName,
                    symbolName: "folder",
                    isActive: false,
                    showsChevron: false
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)

            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)

                Text("Ask a follow-up.")
                    .font(.body)
                    .foregroundStyle(.secondary.opacity(0.72))

                Spacer(minLength: 0)

                Image(systemName: "arrow.up")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.actionPrimary, in: Circle())
            }
            .padding(.leading, 9)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .frame(minHeight: 48)
            .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.pill))
            .overlay {
                RoundedRectangle.app(AppRadius.pill)
                    .stroke(Color.actionPrimary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.brandBlack.opacity(0.08), radius: 16, y: 7)
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Private and Cloud route, \(projectName), ask a follow-up")
    }
}

#endif
