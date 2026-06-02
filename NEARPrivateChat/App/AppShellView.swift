import SwiftUI

struct AppShellView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var conversationStore: ConversationStore
    @EnvironmentObject private var agentStore: AgentStore
    @State private var showingCompactChat = false
    let onRunSetupAgain: () -> Void

    init(onRunSetupAgain: @escaping () -> Void = {}) {
        self.onRunSetupAgain = onRunSetupAgain
    }

    var body: some View {
        NavigationStack {
            ConversationListView(
                onOpenChat: { showingCompactChat = true },
                onStartNewChat: { showingCompactChat = true },
                onRunSetupAgain: onRunSetupAgain
            )
            .navigationDestination(isPresented: $showingCompactChat) {
                ChatView()
                    .navigationTitle(conversationStore.selectedConversationTitle)
                    .platformInlineNavigationTitle()
            }
        }
        .tint(.brandBlue)
        .onChange(of: conversationStore.openSelectedConversationToken) { _, token in
            if token != nil {
                showingCompactChat = true
            }
        }
        .confirmationDialog(
            "Delete this conversation?",
            isPresented: deleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            if let conversation = conversationStore.pendingDeleteConversation {
                Button("Archive Instead") {
                    chatStore.archiveConversation(conversation)
                    conversationStore.cancelPendingDelete()
                }
                Button("Delete Permanently", role: .destructive) {
                    chatStore.confirmPendingDelete()
                }
            }
            Button("Cancel", role: .cancel) {
                conversationStore.cancelPendingDelete()
            }
        } message: {
            if let conversation = conversationStore.pendingDeleteConversation {
                Text("\"\(conversation.title)\" will be permanently deleted. Archive keeps it recoverable.")
            }
        }
        .confirmationDialog(
            "Open external shortcut?",
            isPresented: externalDeepLinkConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Open Shortcut") {
                chatStore.confirmPendingExternalDeepLink()
            }
            Button("Cancel", role: .cancel) {
                chatStore.cancelPendingExternalDeepLink()
            }
        } message: {
            Text(chatStore.pendingExternalDeepLinkDescription)
        }
        .sheet(item: $agentStore.pendingHostedHandoffPreflight) { preflight in
            HostedHandoffPreflightSheet(
                preflight: preflight,
                onConfirm: { chatStore.confirmHostedHandoff($0) },
                onCancel: { chatStore.cancelHostedHandoff() }
            )
                .platformMediumDetent()
        }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { conversationStore.pendingDeleteConversation != nil },
            set: { isPresented in
                if !isPresented {
                    conversationStore.cancelPendingDelete()
                }
            }
        )
    }

    private var externalDeepLinkConfirmationPresented: Binding<Bool> {
        Binding(
            get: { chatStore.pendingExternalDeepLink != nil },
            set: { isPresented in
                if !isPresented {
                    chatStore.cancelPendingExternalDeepLink()
                }
            }
        )
    }
}
