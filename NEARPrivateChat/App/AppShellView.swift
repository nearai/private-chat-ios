import SwiftUI

struct AppShellView: View {
    @EnvironmentObject private var chatStore: ChatStore
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
                    .navigationTitle(chatStore.selectedConversationTitle)
                    .platformInlineNavigationTitle()
            }
        }
        .tint(.brandBlue)
        .onChange(of: chatStore.openSelectedConversationToken) { _, token in
            if token != nil {
                showingCompactChat = true
            }
        }
        .confirmationDialog(
            "Delete this conversation?",
            isPresented: deleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            if let conversation = chatStore.pendingDeleteConversation {
                Button("Archive Instead") {
                    chatStore.archiveConversation(conversation)
                    chatStore.cancelPendingDelete()
                }
                Button("Delete Permanently", role: .destructive) {
                    chatStore.confirmPendingDelete()
                }
            }
            Button("Cancel", role: .cancel) {
                chatStore.cancelPendingDelete()
            }
        } message: {
            if let conversation = chatStore.pendingDeleteConversation {
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
        .sheet(item: $chatStore.pendingHostedHandoffPreflight) { preflight in
            HostedHandoffPreflightSheet(preflight: preflight)
                .environmentObject(chatStore)
                .platformMediumDetent()
        }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { chatStore.pendingDeleteConversation != nil },
            set: { isPresented in
                if !isPresented {
                    chatStore.cancelPendingDelete()
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
