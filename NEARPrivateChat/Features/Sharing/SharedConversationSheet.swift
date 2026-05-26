import SwiftUI

struct SharedConversationSheet: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("private.near.ai/c/conv_...", text: $linkText)
                        .textFieldStyle(.plain)
                        .tokenInputTraits()
                        .padding(12)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 10) {
                        Button {
                            Task { await chatStore.openSharedConversation(from: linkText) }
                        } label: {
                            Label("Open", systemImage: "arrow.down.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.brandBlue)
                        .disabled(linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatStore.isLoadingSharedPreview)

                        Button {
                            linkText = ""
                            chatStore.closeSharedPreview()
                        } label: {
                            Image(systemName: "xmark")
                                .frame(width: 40, height: 34)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Clear")
                    }

                    if chatStore.isLoadingSharedPreview {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading conversation")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()

                Divider()

                if let snapshot = chatStore.sharedPreview {
                    SharedConversationPreview(snapshot: snapshot)
                } else {
                    ContentUnavailableView(
                        "Open a shared conversation",
                        systemImage: "link",
                        description: Text("Paste a public or shared NEAR AI Private Chat link.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Shared Link")
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

private struct SharedConversationPreview: View {
    @EnvironmentObject private var chatStore: ChatStore
    let snapshot: SharedConversationSnapshot

    private var transcript: String {
        snapshot.messages
            .map { "\($0.role == .user ? "You" : $0.modelDisplayName): \($0.text)" }
            .joined(separator: "\n\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.brandBlue)
                        .frame(width: 34, height: 34)
                        .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.conversation.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text("\(snapshot.messages.count) messages")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                ChipFlowLayout(spacing: 7, lineSpacing: 7) {
                    SharedAccessPill(
                        title: snapshot.accessBadgeTitle,
                        symbolName: snapshot.canWrite ? "square.and.pencil" : "eye",
                        tint: snapshot.canWrite ? Color.primaryAction : Color.orange
                    )
                    SharedAccessPill(
                        title: snapshot.sourceBadgeTitle,
                        symbolName: "link",
                        tint: Color.textSecondary
                    )
                }

                Text(snapshot.accessDescription)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.textSecondary)

                Text(snapshot.sourceDescription)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        previewActions
                    }
                    VStack(spacing: 10) {
                        previewActions
                    }
                }
            }
            .padding(16)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Divider()
                .padding(.top, 16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if snapshot.messages.isEmpty {
                        ContentUnavailableView("No messages", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else {
                        ForEach(snapshot.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
            }
        }
        .background(Color.appBackground)
    }

    @ViewBuilder
    private var previewActions: some View {
        if snapshot.canWrite {
            SharedPreviewActionButton(title: "Open chat", systemImage: "square.and.pencil", isPrimary: true) {
                chatStore.openSharedPreviewForWriting()
            }
            .accessibilityLabel("Open shared conversation for writing")
        }

        SharedPreviewActionButton(title: "Copy & Continue", systemImage: "doc.on.doc", isPrimary: false) {
            chatStore.cloneSharedPreviewToChat()
        }
        .accessibilityLabel("Copy and Continue")

        SharedPreviewActionButton(title: "Copy text", systemImage: "doc.text", isPrimary: false) {
            Clipboard.copy(transcript)
        }
        .accessibilityLabel("Copy Transcript")
    }
}

private struct SharedWithMeView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SharedAccessSummaryCard(conversationCount: chatStore.sharedWithMe.count)
                        .padding(.vertical, 4)
                }

                Section("Conversations") {
                    if chatStore.isLoadingSharedWithMe && chatStore.sharedWithMe.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading shared conversations")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if chatStore.sharedWithMe.isEmpty {
                        ContentUnavailableView("No shared conversations", systemImage: "person.2.slash")
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(chatStore.sharedWithMe) { item in
                            NavigationLink(value: item) {
                                SharedWithMeRow(item: item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shared")
            .platformInlineNavigationTitle()
            .refreshable {
                await chatStore.refreshSharedWithMe()
            }
            .navigationDestination(for: SharedConversationInfo.self) { item in
                SharedWithMePreviewView(item: item)
                    .environmentObject(chatStore)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await chatStore.refreshSharedWithMe() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(chatStore.isLoadingSharedWithMe)
                    .accessibilityLabel("Refresh shared conversations")
                }
            }
            .task {
                await chatStore.refreshSharedWithMe(showErrors: false)
            }
            .onChange(of: chatStore.openSelectedConversationToken) { _, token in
                if token != nil {
                    dismiss()
                }
            }
        }
        .platformLargeDetent()
    }
}

struct SharedWithMeRow: View {
    let item: SharedConversationInfo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.canWrite ? "square.and.pencil" : "eye")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.canWrite ? Color.primaryAction : Color.orange)
                .frame(width: 32, height: 32)
                .background(
                    (item.canWrite ? Color.primaryAction : Color.orange).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(item.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    SharedAccessPill(
                        title: item.accessBadgeTitle,
                        symbolName: item.canWrite ? "square.and.pencil" : "eye",
                        tint: item.canWrite ? Color.primaryAction : Color.orange
                    )
                }

                Text(item.sourceLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let createdAt = item.createdAt {
            parts.append(Date(timeIntervalSince1970: createdAt).formatted(date: .abbreviated, time: .omitted))
        }
        if let error = item.error, !error.isEmpty {
            parts.append(error)
        }
        if parts.isEmpty {
            return item.canWrite ? "Open in place or fork a private copy." : "Copy and Continue makes a private draft."
        }
        return parts.joined(separator: " · ")
    }
}

struct SharedWithMePreviewView: View {
    @EnvironmentObject private var chatStore: ChatStore
    let item: SharedConversationInfo

    var body: some View {
        Group {
            if chatStore.isLoadingSharedPreview {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Opening shared conversation")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            } else if let snapshot = chatStore.sharedPreview,
                      snapshot.conversation.id == item.conversationID {
                SharedConversationPreview(snapshot: snapshot)
            } else {
                ContentUnavailableView(
                    "Could not open conversation",
                    systemImage: "exclamationmark.triangle",
                    description: Text(item.error ?? "Pull to refresh or try again.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            }
        }
        .navigationTitle(item.displayTitle)
        .platformInlineNavigationTitle()
        .task(id: item.conversationID) {
            await chatStore.openSharedConversation(
                from: item.conversationID,
                knownCanWrite: item.canWrite,
                sourceLabel: item.sourceLabel
            )
        }
    }
}

struct SharedAccessSummaryCard: View {
    let conversationCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.2")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 34, height: 34)
                    .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Shared with you")
                        .font(.headline)
                    Text("Read-only chats stay locked. Editable shares open in place when the owner granted write access.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ChipFlowLayout(spacing: 7, lineSpacing: 7) {
                SharedAccessPill(title: "Read-only", symbolName: "eye", tint: Color.orange)
                SharedAccessPill(title: "Can edit", symbolName: "square.and.pencil", tint: Color.primaryAction)
                SharedAccessPill(title: conversationCountLabel, symbolName: "bubble.left.and.bubble.right", tint: Color.textSecondary)
            }
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var conversationCountLabel: String {
        conversationCount == 1 ? "1 conversation" : "\(conversationCount) conversations"
    }
}

private struct SharedAccessPill: View {
    let title: String
    let symbolName: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct SharedPreviewActionButton: View {
    let title: String
    let systemImage: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isPrimary ? Color.brandBlack : Color.primaryAction)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    isPrimary ? Color.brandSky : Color.appSecondaryBackground,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}
