import Foundation

@MainActor
extension ChatStore {
    var selectedConversation: ConversationSummary? {
        get { conversationStore.selectedConversation }
        set { conversationStore.selectedConversation = newValue }
    }

    var visibleConversations: [ConversationSummary] {
        projectStore.selectedProject == nil ? conversationStore.visibleConversations : projectStore.visibleConversations
    }

    var allVisibleConversations: [ConversationSummary] {
        conversationStore.allVisibleConversations
    }

    var archivedConversations: [ConversationSummary] {
        conversationStore.archivedConversations
    }

    var selectedConversationTitle: String {
        conversationStore.selectedConversationTitle
    }

    func refreshConversations(showErrors: Bool = true) async {
        await conversationStore.refreshConversations(showErrors: showErrors)
    }

    /// Opens a conversation by id (e.g. from a CoreSpotlight result) if it's in
    /// the loaded list. No-op otherwise — the app still foregrounds to home.
    func openConversation(byID id: String) {
        guard let conversation = conversationStore.openConversation(byID: id) else { return }
        selectConversation(conversation)
    }

    func selectConversation(_ conversation: ConversationSummary) {
        chatSessionCoordinator.openConversation(
            conversation,
            isStreaming: isStreaming,
            cancelActiveStream: { self.cancelStream() },
            persistCurrentDraft: { self.persistCurrentDraftIfNeeded() },
            scheduleMessageLoad: { self.scheduleMessageLoad(for: $0) },
            transitionDraftScope: { self.transitionDraftScopeToCurrentSelection(loadDraft: true) },
            showBanner: { self.showBanner($0) }
        )
    }

    func startNewConversation(resetInteractionDefaults: Bool = true) {
        let didStart = chatSessionCoordinator.startNewConversation(
            isStreaming: isStreaming,
            cancelActiveStream: { self.cancelStream() },
            persistCurrentDraft: { self.persistCurrentDraftIfNeeded() },
            cancelMessageLoad: { self.cancelMessageLoad() },
            transitionDraftScope: { self.transitionDraftScopeToCurrentSelection(loadDraft: true) },
            showBanner: { self.showBanner($0) }
        )
        if didStart, resetInteractionDefaults {
            modelCatalogStore.resetInteractionDefaults()
        }
    }

    func ensureConversation(for firstMessage: String, attachments: [ChatAttachment]) async throws -> ConversationSummary {
        if let selectedConversation {
            return selectedConversation
        }

        let title = Self.initialConversationTitle(from: firstMessage, attachments: attachments)
        var created = try await conversationStore.createConversation(title: title)
        if created.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            created.metadata = ConversationMetadata(title: title)
            conversationStore.insertOrReplace(created, atFront: true)
        }
        if selectedProjectID != nil {
            assign(conversationID: created.id, to: selectedProjectID)
        }
        return created
    }

    func confirmPendingDelete() {
        Task {
            await conversationActionCoordinator.confirmPendingDelete(
                selectedConversationID: selectedConversation?.id,
                removeLocalMessages: { self.removeLocalMessages(for: $0) },
                removeConversationFromProjects: { self.projectStore.removeConversationFromAllProjects($0) },
                startNewConversation: { self.startNewConversation() },
                showBanner: { self.showBanner($0) }
            )
        }
    }

    func cloneConversation(_ conversation: ConversationSummary) {
        Task {
            await conversationActionCoordinator.cloneConversation(
                conversation,
                selectedProjectID: selectedProjectID,
                assignToProject: { self.assign(conversationID: $0, to: $1) },
                loadMessages: { await self.loadMessages(for: $0, preferCached: false) },
                refreshConversations: { await self.refreshConversations() },
                showBanner: { self.showBanner($0) }
            )
        }
    }

    func archiveConversation(_ conversation: ConversationSummary) {
        Task {
            await conversationActionCoordinator.archiveConversation(
                conversation,
                selectedConversationID: selectedConversation?.id,
                refreshConversations: { await self.refreshConversations() },
                startNewConversation: { self.startNewConversation() },
                showBanner: { self.showBanner($0) }
            )
        }
    }

    func togglePinConversation(_ conversation: ConversationSummary) {
        Task {
            await conversationActionCoordinator.togglePinConversation(
                conversation,
                refreshConversations: { await self.refreshConversations() },
                showBanner: { self.showBanner($0) }
            )
        }
    }

    func openSharedPreviewForWriting(_ snapshot: SharedConversationSnapshot) {
        chatSessionCoordinator.openWritablePreview(
            conversation: snapshot.conversation,
            messages: snapshot.messages,
            canWrite: snapshot.canWrite,
            cancelMessageLoad: { [weak self] in self?.cancelMessageLoad() },
            showBanner: { [weak self] message in self?.showBanner(message) }
        )
    }

    func loadMessages(for conversation: ConversationSummary, preferCached: Bool = true) async {
        await messageLoadCoordinator.loadMessages(
            for: conversation,
            preferCached: preferCached,
            callbacks: messageLoadCallbacks()
        )
    }

    func scheduleMessageLoad(for conversation: ConversationSummary, preferCached: Bool = true) {
        messageLoadCoordinator.scheduleMessagesLoad(
            for: conversation,
            preferCached: preferCached,
            callbacks: messageLoadCallbacks()
        )
    }

    func cancelMessageLoad() {
        messageLoadCoordinator.cancel()
    }

    private static func initialConversationTitle(from firstMessage: String, attachments: [ChatAttachment]) -> String {
        if let agentMissionTitle = agentMissionConversationTitle(from: firstMessage) {
            return clippedTitle(agentMissionTitle)
        }

        let normalizedMessage = firstMessage
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedMessage.isEmpty else {
            if let firstAttachment = attachments.first, attachments.count == 1 {
                return clippedTitle("Review \(firstAttachment.name)")
            }
            if !attachments.isEmpty {
                return "Review \(attachments.count) files"
            }
            return "New conversation"
        }

        // Short greetings and conversational openers shouldn't become
        // literal titles ("hello", "hi", "what's up today?") because they do
        // not describe the topic. The backend can replace this via title SSE.
        let lowered = normalizedMessage.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!,'\""))
        let greetingOpeners: Set<String> = [
            "hello", "hi", "hey", "hiya", "howdy", "yo",
            "sup", "wassup", "what's up", "whats up", "whatsup",
            "what's up today", "whats up today",
            "morning", "good morning", "good afternoon", "good evening",
            "gm", "gn", "lol"
        ]
        if greetingOpeners.contains(lowered) || lowered.count <= 3 {
            return "New chat"
        }

        let withoutInstructions = strippedStarterInstruction(from: normalizedMessage)
        let title = withoutInstructions.trimmingCharacters(in: CharacterSet(charactersIn: "#*` ").union(.whitespacesAndNewlines))
        return clippedTitle(title.isEmpty ? normalizedMessage : title)
    }

    private static func agentMissionConversationTitle(from text: String) -> String? {
        let missionMarkers = ["Hosted IronClaw Mission:", "Agent Mission:"]
        guard missionMarkers.contains(where: { text.localizedCaseInsensitiveContains($0) }) else {
            return nil
        }
        let lines = text.components(separatedBy: .newlines)
        let missionTitle = lines
            .first { line in
                missionMarkers.contains { line.range(of: $0, options: [.caseInsensitive]) != nil }
            }?
            .components(separatedBy: ":")
            .dropFirst()
            .joined(separator: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let brief = AgentStore.agentMissionBrief(from: text)
        if let missionTitle, !missionTitle.isEmpty,
           let brief, !brief.isEmpty {
            return "\(missionTitle): \(brief)"
        }
        if let brief, !brief.isEmpty {
            return brief
        }
        if let missionTitle, !missionTitle.isEmpty {
            return "Agent: \(missionTitle)"
        }
        return nil
    }

    private static func strippedStarterInstruction(from text: String) -> String {
        let separators = [
            "? Use ",
            ". Use ",
            "? Cite ",
            ". Cite ",
            "? Please ",
            ". Please ",
            "? Include ",
            ". Include "
        ]

        for separator in separators {
            if let range = text.range(of: separator, options: [.caseInsensitive]) {
                let punctuationEnd = text.index(after: range.lowerBound)
                let prefix = String(text[..<punctuationEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                if prefix.count >= 12 {
                    return prefix
                }
            }
        }
        return text
    }

    private static func clippedTitle(_ rawTitle: String, maxLength: Int = 64) -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "New conversation" }
        guard title.count > maxLength else { return title }

        let prefix = String(title.prefix(maxLength))
        if let lastSpace = prefix.lastIndex(where: { $0 == " " }), prefix.distance(from: prefix.startIndex, to: lastSpace) > 24 {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    func selectResponseVariant(_ responseID: String) {
        guard !isStreaming else { return }
        guard let conversation = selectedConversation else { return }
        messageTimelineStore.selectResponseVariant(responseID, for: conversation.id)
        scheduleMessageLoad(for: conversation, preferCached: false)
    }

    nonisolated static func mergedMessages(remoteMessages: [ChatMessage], localCache: [ChatMessage]?) -> [ChatMessage] {
        MessageRepository.mergedMessages(remoteMessages: remoteMessages, localCache: localCache)
    }
}
