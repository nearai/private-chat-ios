import Foundation
import Combine

enum ChatDisplayItem: Identifiable, Hashable {
    case message(ChatMessage)
    case council(batchID: String, messages: [ChatMessage])

    var id: String {
        switch self {
        case let .message(message):
            return message.id
        case let .council(batchID, _):
            return batchID
        }
    }

    static func items(from messages: [ChatMessage]) -> [ChatDisplayItem] {
        MessageTimelineStore.displayItems(from: messages)
    }
}

@MainActor
final class MessageTimelineStore: ObservableObject {
    @Published private(set) var state = ChatTranscriptState()
    private var selectedResponseVariantByConversationID: [String: String] = [:]
    private var pendingTextDeltaByMessageID: [String: String] = [:]
    private var pendingTextDeltaFlushTask: Task<Void, Never>?

    var messages: [ChatMessage] {
        get { state.messages }
        set {
            guard state.messages != newValue else { return }
            state = state.updating(messages: newValue)
        }
    }

    var isStreaming: Bool {
        get { state.isStreaming }
        set {
            guard state.isStreaming != newValue else { return }
            state = state.updating(isStreaming: newValue)
        }
    }

    func reset() {
        cancelPendingTextDeltaFlushes()
        state = ChatTranscriptState()
        selectedResponseVariantByConversationID = [:]
    }

    func selectResponseVariant(_ responseID: String, for conversationID: String) {
        selectedResponseVariantByConversationID[conversationID] = responseID
    }

    func selectedResponseVariant(for conversationID: String) -> String? {
        selectedResponseVariantByConversationID[conversationID]
    }

    func clearSelectedResponseVariant(for conversationID: String) {
        selectedResponseVariantByConversationID.removeValue(forKey: conversationID)
    }

    @discardableResult
    func updateMessage(_ messageID: String, mutate: (inout ChatMessage) -> Void) -> Bool {
        var updatedMessages = messages
        guard let index = updatedMessages.firstIndex(where: { $0.id == messageID }) else {
            return false
        }
        let originalMessage = updatedMessages[index]
        mutate(&updatedMessages[index])
        guard updatedMessages[index] != originalMessage else {
            return false
        }
        messages = updatedMessages
        return true
    }

    func apply(
        streamEvent event: ResponseStreamEvent,
        conversationID: String,
        assistantMessageID: String?,
        onTitleUpdated: ((String, String) -> Void)? = nil
    ) {
        guard let assistantMessageID else {
            return
        }

        switch event {
        case let .created(responseID):
            flushPendingTextDelta(for: assistantMessageID)
            updateMessage(assistantMessageID) { message in
                message.responseID = responseID
            }
        case .reasoningStarted:
            updateMessage(assistantMessageID) { message in
                if message.text.isEmpty {
                    message.status = "reasoning"
                }
            }
        case let .approvalNeeded(approval):
            flushPendingTextDelta(for: assistantMessageID)
            updateMessage(assistantMessageID) { message in
                message.pendingApproval = approval
                message.status = "approval"
                message.isStreaming = false
            }
        case let .webSearchStarted(query):
            updateMessage(assistantMessageID) { message in
                message.status = "searching"
                message.searchQuery = query
            }
        case let .webSearchCompleted(query, sources):
            updateMessage(assistantMessageID) { message in
                message.status = message.text.isEmpty ? "thinking" : message.status
                message.searchQuery = query ?? message.searchQuery
                message.sources = MessageRepository.uniqueSources(message.sources + sources)
            }
        case let .textDelta(delta):
            if !delta.isEmpty {
                let messageNeedsFirstTokenUpdate = messages.first(where: { $0.id == assistantMessageID }).map { message in
                    message.firstTokenAt == nil || (message.text.isEmpty && message.status == "searching")
                } ?? false
                if messageNeedsFirstTokenUpdate {
                    updateMessage(assistantMessageID) { message in
                        if message.text.isEmpty && message.status == "searching" {
                            message.status = "streaming"
                        }
                        if message.firstTokenAt == nil {
                            message.firstTokenAt = Date()
                        }
                    }
                }
            }
            appendBufferedTextDelta(delta, to: assistantMessageID)
        case let .itemDone(text):
            flushPendingTextDelta(for: assistantMessageID)
            if let text, !text.isEmpty {
                updateMessage(assistantMessageID) { message in
                    let existingText = message.text
                    if message.firstTokenAt == nil {
                        message.firstTokenAt = Date()
                    }
                    let shouldReplaceFailure = message.status == "failed" || MessageRepository.localFailureMessage(from: existingText) != nil
                    if existingText.isEmpty || shouldReplaceFailure || text.contains(existingText) {
                        message.text = text
                    } else if !existingText.contains(text) {
                        message.text += "\n\n\(text)"
                    }
                    if message.status != "approval" {
                        message.status = "streaming"
                        message.isStreaming = true
                    }
                }
            }
        case let .titleUpdated(title):
            guard !title.isEmpty else { return }
            onTitleUpdated?(conversationID, title)
        case let .completed(responseID):
            flushPendingTextDelta(for: assistantMessageID)
            updateMessage(assistantMessageID) { message in
                guard message.status != "failed", message.status != "approval" else {
                    message.responseID = responseID ?? message.responseID
                    message.isStreaming = false
                    return
                }
                message.responseID = responseID ?? message.responseID
                if message.sources.isEmpty {
                    message.sources = MessageRepository.inferredSources(from: message.text)
                }
                message.status = "completed"
                message.isStreaming = false
                if let localFailure = MessageRepository.localFailureMessage(from: message.text) {
                    message.status = "failed"
                    message.text = localFailure
                }
            }
        case let .failed(message):
            flushPendingTextDelta(for: assistantMessageID)
            let displayMessage = MessageRepository.displayFailureMessage(message)
            updateMessage(assistantMessageID) { message in
                message.status = "failed"
                message.isStreaming = false
                if message.text.isEmpty || MessageRepository.localFailureMessage(from: message.text) != nil {
                    message.text = displayMessage
                } else if !message.text.localizedCaseInsensitiveContains(displayMessage) {
                    message.text += "\n\nResponse failed: \(displayMessage)"
                }
            }
        }
    }

    func finishAssistantMessage(
        _ messageID: String,
        trustMetadata: (ChatMessage) -> MessageTrustMetadata?
    ) {
        flushPendingTextDelta(for: messageID)
        updateMessage(messageID) { message in
            message.isStreaming = false
            if message.status != "failed", message.status != "approval" {
                message.status = "completed"
            }
            if message.firstTokenAt == nil,
               !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message.firstTokenAt = Date()
            }
            if message.widget == nil {
                let extraction = MessageWidget.extract(from: message.text)
                if let widget = extraction.widget {
                    message.widget = widget
                    message.text = extraction.cleanedText
                }
            }
            if message.sources.isEmpty {
                message.sources = MessageRepository.inferredSources(from: message.text)
            }
            message.trustMetadata = trustMetadata(message)
        }
    }

    func markStreamingMessagesCancelled(
        assistantMessageID: String?,
        councilAssistantMessageIDs: [String]
    ) {
        if let assistantMessageID {
            flushPendingTextDelta(for: assistantMessageID)
            updateMessage(assistantMessageID) { message in
                message.isStreaming = false
                message.status = "cancelled"
            }
        }
        for messageID in councilAssistantMessageIDs {
            flushPendingTextDelta(for: messageID)
            updateMessage(messageID) { message in
                message.isStreaming = false
                message.status = "cancelled"
            }
        }
    }

    func flushPendingTextDelta(for messageID: String) {
        guard let delta = pendingTextDeltaByMessageID.removeValue(forKey: messageID),
              !delta.isEmpty,
              let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        var updatedMessages = messages
        updatedMessages[index].text += delta
        messages = updatedMessages
        if pendingTextDeltaByMessageID.isEmpty {
            pendingTextDeltaFlushTask?.cancel()
            pendingTextDeltaFlushTask = nil
        }
    }

    func cancelPendingTextDeltaFlushes() {
        pendingTextDeltaFlushTask?.cancel()
        pendingTextDeltaFlushTask = nil
        pendingTextDeltaByMessageID.removeAll()
    }

    private func appendBufferedTextDelta(_ delta: String, to messageID: String) {
        guard !delta.isEmpty else { return }
        pendingTextDeltaByMessageID[messageID, default: ""] += delta
        guard pendingTextDeltaFlushTask == nil else { return }
        let flushDelay = pendingTextDeltaFlushNanoseconds()
        pendingTextDeltaFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: flushDelay)
            guard !Task.isCancelled else { return }
            self?.flushPendingTextDeltas()
        }
    }

    private func pendingTextDeltaFlushNanoseconds() -> UInt64 {
        let pendingIDs = Set(pendingTextDeltaByMessageID.keys)
        guard !pendingIDs.isEmpty,
              pendingIDs.allSatisfy({ messageID in
                  messages.first(where: { $0.id == messageID })?.councilBatchID != nil
              }) else {
            return MessageStreamService.textDeltaFlushNanoseconds
        }
        return MessageStreamService.councilTextDeltaFlushNanoseconds
    }

    private func flushPendingTextDeltas() {
        pendingTextDeltaFlushTask = nil
        let pendingDeltas = pendingTextDeltaByMessageID
        pendingTextDeltaByMessageID.removeAll()
        guard !pendingDeltas.isEmpty else { return }

        var updatedMessages = messages
        var didApplyDelta = false
        for (messageID, delta) in pendingDeltas where !delta.isEmpty {
            guard let index = updatedMessages.firstIndex(where: { $0.id == messageID }) else {
                continue
            }
            updatedMessages[index].text += delta
            didApplyDelta = true
        }
        if didApplyDelta {
            messages = updatedMessages
        }
    }

    nonisolated static func displayItems(from messages: [ChatMessage]) -> [ChatDisplayItem] {
        let grouped = Dictionary(
            grouping: messages.filter { $0.role == .assistant && $0.councilBatchID?.isEmpty == false },
            by: { $0.councilBatchID ?? "" }
        )
        let groupCounts = grouped.mapValues(\.count)
        var renderedCouncilIDs = Set<String>()
        var items: [ChatDisplayItem] = []

        for message in messages {
            guard message.role == .assistant,
                  let batchID = message.councilBatchID,
                  (groupCounts[batchID] ?? 0) > 1 else {
                items.append(.message(message))
                continue
            }

            guard !renderedCouncilIDs.contains(batchID) else {
                continue
            }
            let councilMessages = (grouped[batchID] ?? [])
                .sorted { $0.createdAt < $1.createdAt }
            items.append(.council(batchID: batchID, messages: councilMessages))
            renderedCouncilIDs.insert(batchID)
        }
        return items
    }
}
