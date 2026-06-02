import Foundation

@MainActor
struct ChatMessageLoadCoordinatorCallbacks {
    let restoreSelectedModel: @MainActor ([ChatMessage]) -> Void
    let refreshExternalLatestResponse: @MainActor (String) async -> Void
    let showBanner: @MainActor (String) -> Void
}

@MainActor
final class ChatMessageLoadCoordinator {
    private var repository: MessageRepository
    private let conversationStore: ConversationStore
    private let timelineStore: MessageTimelineStore
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    init(
        repository: MessageRepository,
        conversationStore: ConversationStore,
        timelineStore: MessageTimelineStore
    ) {
        self.repository = repository
        self.conversationStore = conversationStore
        self.timelineStore = timelineStore
    }

    func configure(accountID: String) {
        repository.configure(accountID: accountID)
    }

    func reset() {
        cancel()
    }

    func cancel() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
    }

    func scheduleMessagesLoad(
        for conversation: ConversationSummary,
        preferCached: Bool = true,
        callbacks: ChatMessageLoadCoordinatorCallbacks
    ) {
        generation += 1
        let generation = generation
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            await self?.loadMessages(
                for: conversation,
                preferCached: preferCached,
                generation: generation,
                callbacks: callbacks
            )
        }
    }

    func loadMessages(
        for conversation: ConversationSummary,
        preferCached: Bool = true,
        callbacks: ChatMessageLoadCoordinatorCallbacks
    ) async {
        generation += 1
        let generation = generation
        loadTask?.cancel()
        await loadMessages(
            for: conversation,
            preferCached: preferCached,
            generation: generation,
            callbacks: callbacks
        )
    }

    private func loadMessages(
        for conversation: ConversationSummary,
        preferCached: Bool,
        generation: Int,
        callbacks: ChatMessageLoadCoordinatorCallbacks
    ) async {
        let cachedMessages = repository.loadLocalMessages(for: conversation.id)
        if preferCached, let cachedMessages, !cachedMessages.isEmpty {
            let normalizedMessages = MessageRepository.normalizedMessages(cachedMessages, assumingStreamLost: true)
            if canApplyMessageLoad(for: conversation.id, generation: generation) {
                apply(normalizedMessages)
                callbacks.restoreSelectedModel(normalizedMessages)
                if normalizedMessages != cachedMessages {
                    saveLocalMessages(normalizedMessages, for: conversation.id, callbacks: callbacks)
                }
            }
            if cachedMessages.contains(where: { MessageRepository.isExternalModel($0.model ?? "") }) {
                await callbacks.refreshExternalLatestResponse(conversation.id)
            }
        }

        do {
            let remoteMessages = try await repository.loadRemoteMessages(
                for: conversation.id,
                preferredResponseID: timelineStore.selectedResponseVariant(for: conversation.id)
            )
            guard canApplyMessageLoad(for: conversation.id, generation: generation) else { return }
            let loadedMessages = MessageRepository.mergedMessages(
                remoteMessages: remoteMessages,
                localCache: cachedMessages
            )
            apply(loadedMessages)
            callbacks.restoreSelectedModel(loadedMessages)
            if loadedMessages != cachedMessages {
                saveLocalMessages(loadedMessages, for: conversation.id, callbacks: callbacks)
            }
        } catch is CancellationError {
            return
        } catch {
            guard canApplyMessageLoad(for: conversation.id, generation: generation) else { return }
            if cachedMessages?.isEmpty == false {
                callbacks.showBanner("Could not refresh this chat. Showing cached messages.")
            } else {
                callbacks.showBanner(error.localizedDescription)
            }
        }
    }

    private func apply(_ messages: [ChatMessage]) {
        guard timelineStore.messages != messages else { return }
        timelineStore.messages = messages
    }

    private func saveLocalMessages(
        _ messages: [ChatMessage],
        for conversationID: String,
        callbacks: ChatMessageLoadCoordinatorCallbacks
    ) {
        guard !repository.saveLocalMessages(messages, for: conversationID) else { return }
        callbacks.showBanner("Local message cache could not be saved securely.")
    }

    private func canApplyMessageLoad(for conversationID: String, generation: Int) -> Bool {
        !Task.isCancelled &&
            self.generation == generation &&
            conversationStore.selectedConversation?.id == conversationID
    }
}
