import Foundation

@MainActor
extension ChatStore {
    func loadAccountScopedState() {
        modelCatalogStore.configure(accountID: storageAccountID)
        agentStore.configure(accountID: storageAccountID)
        accountStore.configure(accountID: storageAccountID)
        soulPromptProfile = SoulPromptComposer.Profile.parse(soulMarkdown)
        conversationStore.configure(accountID: storageAccountID)
        messageRepository.configure(accountID: storageAccountID)
        messageLoadCoordinator.configure(accountID: storageAccountID)
        draftScopeStore.configure(accountID: storageAccountID)
        projectStore.configure(accountID: storageAccountID)
        projectStore.replaceConversations(conversations)
        messageTimelineStore.reset()
        transitionDraftScopeToCurrentSelection(loadDraft: true)
    }

    var settingsPersistence: SettingsPersistence {
        SettingsPersistence(accountID: storageAccountID)
    }

    var currentDraftScopeID: String {
        draftScopeStore.currentScopeID(
            selectedConversationID: selectedConversation?.id,
            selectedProjectID: selectedProjectID
        )
    }

    func transitionDraftScopeToCurrentSelection(loadDraft: Bool) {
        draftScopeStore.transition(to: currentDraftScopeID, loadDraft: loadDraft) { persistedState in
            draft = persistedState.text
            pendingAttachments = persistedState.attachments
            pendingLargePasteTexts = persistedState.pendingLargePasteTexts
            pendingDocumentTexts = persistedState.pendingDocumentTexts
        }
    }

    func persistCurrentDraftIfNeeded() {
        let state = DraftPersistence.DraftState(
            text: draft,
            attachments: pendingAttachments,
            pendingLargePasteTexts: pendingLargePasteTexts,
            pendingDocumentTexts: pendingDocumentTexts
        )
        draftScopeStore.persistIfNeeded(state, isResettingAccountScopedState: isResettingAccountScopedState) {
            showBanner("Draft state could not be saved securely.")
        }
    }

    func discardActiveDraft() {
        draftScopeStore.removeCurrentScope()
    }

    func handleDraftChange(from previous: String, to current: String) {
        guard !isNormalizingDraft, !draftScopeStore.isSuppressingPersistence else { return }

        var currentValue = current
        let normalizedValue = Self.normalizedDraftInput(current)
        if normalizedValue != current {
            isNormalizingDraft = true
            draft = normalizedValue
            isNormalizingDraft = false
            currentValue = normalizedValue
        }

        guard largeTextAsFileEnabled,
              !isUploadingAttachment,
              attachmentStagingStore.shouldPromoteLargePaste(
                previous: previous,
                current: currentValue,
                thresholdBytes: Self.largePasteThresholdBytes,
                thresholdCharacters: Self.largePasteThresholdCharacters
              ) else {
            return
        }
        switch FileStore.promptAttachmentLimit(
            pendingCount: pendingAttachments.count,
            projectContextCount: activeProjectContextAttachments.count,
            maxPromptAttachments: Self.maxPromptAttachments,
            maxContextAttachments: Self.maxProjectAttachments
        ) {
        case .allowed:
            break
        case let .blocked(message):
            showBanner(message)
            return
        }
        guard currentValue.utf8.count <= Self.maxFileUploadBytes else {
            showBanner("Large paste exceeds the 10 MB file cap.")
            return
        }

        isNormalizingDraft = true
        draft = ""
        isNormalizingDraft = false

        stageLargePasteForSend(currentValue)
    }

    func stageLargePasteForSend(_ text: String, suggestedName: String? = nil) {
        _ = attachmentStagingStore.stageLargePasteForSend(text, suggestedName: suggestedName)
        showBanner("Text staged. It uploads only when you send.")
    }

    static func normalizedDraftInput(_ text: String) -> String {
        text
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(
                of: #"(^|[\s\(\[\{])(?:–|—|−)(?=[A-Za-z0-9])"#,
                with: "$1--",
                options: .regularExpression
            )
    }

    func loadIronclawAuthToken() -> String? {
        agentStore.loadIronclawAuthToken()
    }

    func loadNearCloudAPIKey() -> String? {
        accountStore.loadNearCloudAPIKey()
    }

    func loadLocalMessages(for conversationID: String) -> [ChatMessage]? {
        messageRepository.loadLocalMessages(for: conversationID)
    }

    func cachedConversationPreview(for conversationID: String) -> String? {
        messageRepository.cachedConversationPreview(
            for: conversationID,
            selectedConversationID: selectedConversation?.id,
            currentMessages: messages
        )
    }

    func cachedConversationHasSourceCue(for conversationID: String) -> Bool {
        messageRepository.cachedConversationHasSourceCue(
            for: conversationID,
            selectedConversationID: selectedConversation?.id,
            currentMessages: messages
        )
    }

    func cachedConversationSourceSummary(for conversationID: String) -> String? {
        messageRepository.cachedConversationSourceSummary(
            for: conversationID,
            selectedConversationID: selectedConversation?.id,
            currentMessages: messages
        )
    }

    func loadLocalMessageCache() -> [String: [ChatMessage]] {
        messageRepository.loadLocalMessageCache()
    }

    func saveProjects() {
        projectStore.persistProjects()
    }

    func saveLocalMessages(for conversationID: String) {
        if !messageRepository.saveLocalMessages(messages, for: conversationID) {
            showBanner("Local message cache could not be saved securely.")
        }
    }

    func removeLocalMessages(for conversationID: String) {
        if !messageRepository.removeLocalMessages(for: conversationID) {
            showBanner("Local message cache could not be updated securely.")
        }
        agentStore.removeIronclawThreadID(for: conversationID)
    }
}
