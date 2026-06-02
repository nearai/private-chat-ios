import SwiftUI

struct ArtifactOutputView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    let message: ChatMessage

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 32, height: 32)
                            .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.modelDisplayName)
                                .font(.headline.weight(.semibold))
                            Text(message.createdAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    Divider()

                    MarkdownMessageText(text: message.text, sources: message.sources)
                        .font(.body)

                    if !message.sources.isEmpty {
                        SearchContextStrip(query: message.searchQuery, sources: message.sources)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.appBackground)
            .navigationTitle("Output")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Clipboard.copy(message.text)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copy Output")

                    Button {
                        chatStore.copySignedSnippet(for: message)
                    } label: {
                        Image(systemName: "checkmark.shield")
                    }
                    .accessibilityLabel("Copy Device-Signed Snippet")

                    Button {
                        chatStore.requestProjectNoteSave(for: message)
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .accessibilityLabel("Save Output to Project")
                }
            }
        }
    }
}

extension ChatMessage {
    var isArtifactCandidate: Bool {
        guard role == .assistant, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return text.count > 1_200 ||
            text.contains("```") ||
            text.contains("\n|") ||
            text.localizedCaseInsensitiveContains("# ")
    }
}
