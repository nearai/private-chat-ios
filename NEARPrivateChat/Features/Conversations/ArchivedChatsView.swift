import SwiftUI

struct ArchivedChatsView: View {
    @EnvironmentObject private var conversationStore: ConversationStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingArchiveExporter = false
    @State private var archiveDocument = ConversationExportDocument()

    private var archived: [ConversationSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return conversationStore.archivedConversations }
        return conversationStore.archivedConversations.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
                $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private var archivedJSON: String {
        guard let data = try? JSONEncoder().encode(conversationStore.archivedConversations),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: prettyData, encoding: .utf8) else {
            return "[]"
        }
        return pretty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "archivebox")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.actionPrimary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(conversationStore.archivedConversations.count) archived conversations")
                                .font(.headline)
                            Text("Restore chats when you need them, or delete them permanently.")
                                .font(.footnote)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Conversations") {
                    if archived.isEmpty {
                        ContentUnavailableView("No archived conversations", systemImage: "archivebox")
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(archived) { conversation in
                            HStack(spacing: 10) {
                                Image(systemName: "bubble.left")
                                    .foregroundStyle(Color.actionPrimary)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conversation.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    if let createdAt = conversation.createdAt {
                                        Text(Date(timeIntervalSince1970: createdAt), style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 0)

                                Button {
                                    Task { await conversationStore.restoreArchivedConversation(conversation) }
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Unarchive")

                                Button(role: .destructive) {
                                    conversationStore.requestDeleteConversation(conversation)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Delete")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                if !conversationStore.archivedConversations.isEmpty {
                    Section {
                        Button {
                            Task { await conversationStore.restoreAllArchivedConversations() }
                        } label: {
                            Label("Unarchive All", systemImage: "arrow.uturn.backward.circle")
                        }

                        Button {
                            Clipboard.copy(archivedJSON)
                            conversationStore.showBanner("Archived JSON copied.")
                        } label: {
                            Label("Copy Archive JSON", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            archiveDocument = ConversationExportDocument(data: Data(archivedJSON.utf8))
                            showingArchiveExporter = true
                        } label: {
                            Label("Export Archive JSON", systemImage: "square.and.arrow.up.on.square")
                        }
                    }
                }
            }
            .navigationTitle("Archived")
            .platformInlineNavigationTitle()
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search archived chats")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onChange(of: conversationStore.openSelectedConversationToken) { _, token in
                if token != nil {
                    dismiss()
                }
            }
            .fileExporter(
                isPresented: $showingArchiveExporter,
                document: archiveDocument,
                contentType: .json,
                defaultFilename: archiveFilename
            ) { result in
                switch result {
                case .success:
                    conversationStore.showBanner("Archive JSON exported.")
                case let .failure(error):
                    conversationStore.showBanner(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))
                }
            }
        }
    }

    private var archiveFilename: String {
        let date = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return "near-private-chat-archive-\(date).json"
    }
}
