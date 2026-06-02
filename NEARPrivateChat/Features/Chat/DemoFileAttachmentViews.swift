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
                    VStack(alignment: .leading, spacing: 14) {
                        header
                            .id("top")

                        if let user = chatStore.messages.first(where: { $0.role == .user }) {
                            Text(user.text)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        if let answer {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    AssistantAvatar()
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Private model")
                                            .font(.subheadline.weight(.bold))
                                        Text("NEAR Private route")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                MarkdownMessageText(text: answer.text, sources: answer.sources)
                                    .font(.body)

                                SearchContextStrip(query: answer.searchQuery, sources: answer.sources)
                                    .id("sources")

                                DemoVerifiedProofCard()
                                    .id("proof")
                            }
                            .padding(12)
                            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }
                .background(Color.appBackground)
                .navigationTitle("Private answer")
                .platformInlineNavigationTitle()
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

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(Color.trustVerified)
                .frame(width: 34, height: 34)
                .background(Color.trustVerified.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Private answer first")
                    .font(.headline.weight(.semibold))
                Text("One private model, live web sources, then proof.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#endif
