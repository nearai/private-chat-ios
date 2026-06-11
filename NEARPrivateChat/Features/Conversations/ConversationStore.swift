import Foundation
import Combine

@MainActor
final class ConversationStore: ObservableObject {
    @Published private(set) var conversations: [ConversationSummary] = []
    @Published var selectedConversation: ConversationSummary?
    @Published private(set) var openSelectedConversationToken: UUID?
    @Published private(set) var pendingDeleteConversation: ConversationSummary?

    var bannerHandler: (@MainActor (String) -> Void)?
    var conversationsDidChange: (@MainActor ([ConversationSummary]) -> Void)?

    private var repository: ConversationRepository

    init(repository: ConversationRepository) {
        self.repository = repository
    }

    func configure(accountID: String) {
        repository.configure(accountID: accountID)
        replaceConversations(repository.loadCachedConversations(), shouldCache: false)
    }

    func reset() {
        replaceConversations([], shouldCache: false)
        selectedConversation = nil
        openSelectedConversationToken = nil
        pendingDeleteConversation = nil
    }

    var selectedConversationTitle: String {
        selectedConversation?.title ?? "New chat"
    }

    var visibleConversations: [ConversationSummary] {
        conversations
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return (lhs.createdAt ?? 0) > (rhs.createdAt ?? 0)
            }
    }

    var allVisibleConversations: [ConversationSummary] {
        conversations
            .filter { !$0.isArchived }
            .sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
    }

    var archivedConversations: [ConversationSummary] {
        conversations
            .filter(\.isArchived)
            .sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
    }

    func refreshConversations(showErrors: Bool = true) async {
        do {
            let fetchedConversations = try await repository.fetchConversations()
            replaceConversations(fetchedConversations)
            ConversationSpotlightIndex.index(fetchedConversations)
            refreshSelectedConversation(from: fetchedConversations)
        } catch {
            if conversations.isEmpty {
                replaceConversations(repository.loadCachedConversations(), shouldCache: false)
            }
            if showErrors {
                showBanner(conversations.isEmpty ? "Could not refresh chats. Pull to retry." : "Could not refresh chats. Showing cached list.")
            }
        }
    }

    func openConversation(byID id: String) -> ConversationSummary? {
        conversations.first(where: { $0.id == id })
    }

    func selectConversation(_ conversation: ConversationSummary) {
        selectedConversation = conversation
    }

    func startNewConversation() {
        selectedConversation = nil
    }

    func requestOpenSelectedConversation() {
        openSelectedConversationToken = UUID()
    }

    func requestDeleteConversation(_ conversation: ConversationSummary) {
        pendingDeleteConversation = conversation
    }

    func cancelPendingDelete() {
        pendingDeleteConversation = nil
    }

    func createConversation(title: String) async throws -> ConversationSummary {
        let created = try await repository.createConversation(title: title)
        insertOrReplace(created, atFront: true)
        return created
    }

    func createConversation(title: String, metadata: [String: String]) async throws -> ConversationSummary {
        let created = try await repository.createConversation(title: title, metadata: metadata)
        insertOrReplace(created, atFront: true)
        return created
    }

    func deleteConversation(_ conversation: ConversationSummary) async throws {
        try await repository.deleteConversation(conversation.id)
        removeConversation(id: conversation.id)
    }

    func cloneConversation(_ conversation: ConversationSummary) async throws -> ConversationSummary {
        let cloned = try await repository.cloneConversation(conversation.id)
        insertOrReplace(cloned, atFront: true)
        selectedConversation = cloned
        return cloned
    }

    func archiveConversation(_ conversation: ConversationSummary) async throws {
        try await repository.archiveConversation(conversation.id)
        setArchived(true, for: conversation.id)
    }

    func unarchiveConversation(_ conversation: ConversationSummary) async throws {
        try await repository.unarchiveConversation(conversation.id)
        setArchived(false, for: conversation.id)
    }

    func unarchiveAllConversations() async throws {
        let archived = archivedConversations
        guard !archived.isEmpty else { return }
        for conversation in archived {
            try await repository.unarchiveConversation(conversation.id)
            setArchived(false, for: conversation.id)
        }
    }

    func restoreArchivedConversation(_ conversation: ConversationSummary) async {
        do {
            try await unarchiveConversation(conversation)
            await refreshConversations(showErrors: false)
            showBanner("Conversation restored.")
        } catch {
            showBanner(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))
        }
    }

    func restoreAllArchivedConversations() async {
        let archived = archivedConversations
        guard !archived.isEmpty else { return }

        do {
            try await unarchiveAllConversations()
            await refreshConversations(showErrors: false)
            showBanner("Archived conversations restored.")
        } catch {
            showBanner(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))
        }
    }

    func togglePinConversation(_ conversation: ConversationSummary) async throws -> Bool {
        let shouldPin = !conversation.isPinned
        try await setPinState(shouldPin, conversationID: conversation.id)
        return shouldPin
    }

    func renameConversation(_ conversation: ConversationSummary, title: String) async throws {
        try await renameConversation(id: conversation.id, title: title)
    }

    func renameConversation(id conversationID: String, title: String) async throws {
        try await repository.updateConversationTitle(conversationID, title: title)
        setTitle(title, for: conversationID)
    }

    func setPinState(_ pinned: Bool, conversationID: String) async throws {
        if pinned {
            try await repository.pinConversation(conversationID)
        } else {
            try await repository.unpinConversation(conversationID)
        }
        setPinned(pinned, for: conversationID)
    }

    func setArchiveState(_ archived: Bool, conversationID: String) async throws {
        if archived {
            try await repository.archiveConversation(conversationID)
        } else {
            try await repository.unarchiveConversation(conversationID)
        }
        setArchived(archived, for: conversationID)
    }

    func setTitle(_ title: String, for conversationID: String) {
        mutateConversation(id: conversationID) { conversation in
            if conversation.metadata == nil {
                conversation.metadata = ConversationMetadata()
            }
            conversation.metadata?.title = title
        }
    }

    func setPinned(_ pinned: Bool, for conversationID: String) {
        let timestamp = pinned ? ISO8601DateFormatter().string(from: Date()) : nil
        mutateConversation(id: conversationID) { conversation in
            if conversation.metadata == nil {
                conversation.metadata = ConversationMetadata()
            }
            conversation.metadata?.pinnedAt = timestamp
        }
    }

    func setArchived(_ archived: Bool, for conversationID: String) {
        let timestamp = archived ? ISO8601DateFormatter().string(from: Date()) : nil
        mutateConversation(id: conversationID) { conversation in
            if conversation.metadata == nil {
                conversation.metadata = ConversationMetadata()
            }
            conversation.metadata?.archivedAt = timestamp
        }
    }

    func insertOrReplace(_ conversation: ConversationSummary, atFront: Bool = false) {
        var updated = conversations
        updated.removeAll { $0.id == conversation.id }
        if atFront {
            updated.insert(conversation, at: 0)
        } else {
            updated.append(conversation)
        }
        replaceConversations(updated)
    }

    func replaceConversations(_ conversations: [ConversationSummary], shouldCache: Bool = true) {
        self.conversations = conversations
        conversationsDidChange?(conversations)
        guard shouldCache, !repository.saveCachedConversations(conversations) else { return }
        showBanner("Chat list cache could not be saved securely.")
    }

    func removeConversation(id conversationID: String) {
        var updated = conversations
        updated.removeAll { $0.id == conversationID }
        replaceConversations(updated)
        if selectedConversation?.id == conversationID {
            selectedConversation = nil
        }
    }

    private func refreshSelectedConversation(from conversations: [ConversationSummary]) {
        guard let selectedConversation,
              let refreshed = conversations.first(where: { $0.id == selectedConversation.id }),
              self.selectedConversation != refreshed else {
            return
        }
        self.selectedConversation = refreshed
    }

    private func mutateConversation(id conversationID: String, mutate: (inout ConversationSummary) -> Void) {
        var didMutateList = false
        var updated = conversations
        if let index = updated.firstIndex(where: { $0.id == conversationID }) {
            mutate(&updated[index])
            didMutateList = true
        }
        if didMutateList {
            replaceConversations(updated)
            if selectedConversation?.id == conversationID,
               let refreshed = updated.first(where: { $0.id == conversationID }) {
                selectedConversation = refreshed
            }
        } else if selectedConversation?.id == conversationID {
            guard var refreshed = selectedConversation else { return }
            mutate(&refreshed)
            selectedConversation = refreshed
        }
    }

    func showBanner(_ message: String) {
        bannerHandler?(message)
    }
}

@MainActor
final class ConversationActionCoordinator {
    private let conversationStore: ConversationStore

    init(conversationStore: ConversationStore) {
        self.conversationStore = conversationStore
    }

    func confirmPendingDelete(
        selectedConversationID: String?,
        removeLocalMessages: (String) -> Void,
        removeConversationFromProjects: (String) -> Void,
        startNewConversation: () -> Void,
        showBanner: (String) -> Void
    ) async {
        guard let conversation = conversationStore.pendingDeleteConversation else { return }
        conversationStore.cancelPendingDelete()
        await deleteConversation(
            conversation,
            selectedConversationID: selectedConversationID,
            removeLocalMessages: removeLocalMessages,
            removeConversationFromProjects: removeConversationFromProjects,
            startNewConversation: startNewConversation,
            showBanner: showBanner
        )
    }

    func deleteConversation(
        _ conversation: ConversationSummary,
        selectedConversationID: String?,
        removeLocalMessages: (String) -> Void,
        removeConversationFromProjects: (String) -> Void,
        startNewConversation: () -> Void,
        showBanner: (String) -> Void
    ) async {
        do {
            let wasSelected = selectedConversationID == conversation.id
            try await conversationStore.deleteConversation(conversation)
            removeLocalMessages(conversation.id)
            removeConversationFromProjects(conversation.id)
            if wasSelected {
                startNewConversation()
            }
            showBanner("Conversation deleted.")
        } catch {
            showBanner(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))
        }
    }

    func cloneConversation(
        _ conversation: ConversationSummary,
        selectedProjectID: String?,
        assignToProject: (String, String) -> Void,
        loadMessages: (ConversationSummary) async -> Void,
        refreshConversations: () async -> Void,
        showBanner: (String) -> Void
    ) async {
        do {
            let cloned = try await conversationStore.cloneConversation(conversation)
            if let selectedProjectID {
                assignToProject(cloned.id, selectedProjectID)
            }
            await loadMessages(cloned)
            await refreshConversations()
            showBanner("Conversation copied.")
        } catch {
            showBanner(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))
        }
    }

    func archiveConversation(
        _ conversation: ConversationSummary,
        selectedConversationID: String?,
        refreshConversations: () async -> Void,
        startNewConversation: () -> Void,
        showBanner: (String) -> Void
    ) async {
        do {
            try await conversationStore.archiveConversation(conversation)
            await refreshConversations()
            if selectedConversationID == conversation.id {
                startNewConversation()
            }
            showBanner("Conversation archived.")
        } catch {
            showBanner(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))
        }
    }

    func togglePinConversation(
        _ conversation: ConversationSummary,
        refreshConversations: () async -> Void,
        showBanner: (String) -> Void
    ) async {
        do {
            let shouldPin = try await conversationStore.togglePinConversation(conversation)
            await refreshConversations()
            showBanner(shouldPin ? "Conversation pinned." : "Conversation unpinned.")
        } catch {
            showBanner(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))
        }
    }
}
