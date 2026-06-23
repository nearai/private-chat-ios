import Foundation

extension ChatStore: ChatSendCoordinatorHost {
    var sendDraftText: String {
        get { draft }
        set { draft = newValue }
    }

    var sendPendingAttachments: [ChatAttachment] {
        get { pendingAttachments }
        set { pendingAttachments = newValue }
    }

    var sendPendingLargePasteTexts: [String: String] {
        get { pendingLargePasteTexts }
        set { pendingLargePasteTexts = newValue }
    }

    var sendPendingSharedFileURLs: [String: URL] {
        get { pendingSharedFileURLs }
        set { pendingSharedFileURLs = newValue }
    }

    var sendIsStreaming: Bool {
        get { isStreaming }
        set { isStreaming = newValue }
    }

    var sendRouteReadinessIssue: ChatRouteReadinessIssue? {
        get { routeReadinessIssue }
        set { routeReadinessIssue = newValue }
    }

    var sendProxyRetryOffer: ProxyRetryOffer? {
        get { composerStore.proxyRetryOffer }
        set { composerStore.proxyRetryOffer = newValue }
    }

    var sendPendingHostedHandoffPreflight: HostedIronclawHandoffPreflight? {
        get { pendingHostedHandoffPreflight }
        set { pendingHostedHandoffPreflight = newValue }
    }

    var sendSelectedModel: String {
        get { selectedModel }
        set { selectedModel = newValue }
    }

    var sendSelectedConversation: ConversationSummary? {
        selectedConversation
    }

    var sendSelectedProjectID: String? { selectedProjectID }

    var sendMessages: [ChatMessage] {
        get { messages }
        set { messages = newValue }
    }

    var sendCurrentAssistantMessageID: String? {
        get { currentAssistantMessageID }
        set { currentAssistantMessageID = newValue }
    }

    var sendCurrentCouncilAssistantMessageIDs: [String] {
        get { currentCouncilAssistantMessageIDs }
        set { currentCouncilAssistantMessageIDs = newValue }
    }

    var sendCouncilStopRequestedBatchID: String? {
        get { councilStopRequestedBatchID }
        set { councilStopRequestedBatchID = newValue }
    }

    var sendStreamTask: Task<Void, Never>? {
        get { streamTask }
        set { streamTask = newValue }
    }

    var sendMessageTimelineStore: MessageTimelineStore { messageTimelineStore }
    var sendCurrentUserMessageMetadata: MessageMetadata? { currentUserMessageMetadata }
    var sendModelsAreEmpty: Bool { models.isEmpty }
    var sendBillingSnapshotIsMissing: Bool { billingSnapshot == nil }

    func normalizedSendDraftInput(_ draft: String) -> String {
        Self.normalizedDraftInput(draft)
    }

    func promptSourcePrivacyOverrideForSend(for prompt: String, hasAttachments: Bool) -> PromptSourcePrivacyOverride {
        Self.promptSourcePrivacyOverride(for: prompt, hasAttachments: hasAttachments)
    }

    func applyPromptSourcePrivacyOverrideForSend(_ override: PromptSourcePrivacyOverride) {
        applyPromptSourcePrivacyOverride(override)
    }

    func activeAttachmentsForSend(promptAttachments: [ChatAttachment]) -> [ChatAttachment] {
        activeAttachments(promptAttachments: promptAttachments)
    }

    func promptOnlyAttachmentsForSend(from attachments: [ChatAttachment]) -> [ChatAttachment] {
        promptOnlyAttachments(from: attachments)
    }

    func consumeLocalSendFastPathIfNeeded(
        text: String,
        promptAttachments: [ChatAttachment],
        activeAttachments: [ChatAttachment]
    ) -> Bool {
        // Phase 8 bridge: quick intents / trackers still live in the local tools
        // bucket. The send coordinator owns when this branch is tried.
        guard activeAttachments.isEmpty else { return false }
        guard let dispatch = ChatLocalIntentDispatcher.dispatch(
            text: text,
            pendingNearAccountTrackerSchedule: pendingNearAccountTrackerSchedule
        ) else {
            return false
        }
        if dispatch.clearsPendingNearAccountTracker {
            pendingNearAccountTrackerSchedule = nil
        }

        guard let action = dispatch.action else {
            return false
        }
        discardActiveDraft()
        draft = ""
        routeReadinessIssue = nil

        switch action {
        case let .completePendingNearAccountTracker(account, schedule):
            completePendingNearAccountTracker(account: account, schedule: schedule, prompt: text)
        case let .compound(intents):
            handleCompoundIntent(intents, prompt: text)
        case let .single(intent):
            handleQuickIntent(intent, prompt: text)
        }
        return true
    }

    func actionSurfaceTextForSend(
        text: String,
        attachments: [ChatAttachment],
        override: PromptSourcePrivacyOverride
    ) -> String {
        ActionSurfacePlanner.augmentedPrompt(
            text: text,
            attachmentNames: attachments.map(\.name),
            sourceInstruction: override.sourceInstruction(attachmentNames: attachments.map(\.name))
        )
    }

    func routeCurrentPromptIfNeededForSend(_ text: String, attachments: [ChatAttachment]) {
        routeCurrentPromptIfNeeded(text, attachments: attachments)
    }

    func hostedHandoffPreflightForSend(
        text: String,
        promptAttachments: [ChatAttachment]
    ) -> HostedIronclawHandoffPreflight? {
        hostedHandoffPreflightIfNeeded(text: text, promptAttachments: promptAttachments)
    }

    func currentRouteReadinessIssueForSend(
        for text: String,
        appendUserMessage: Bool
    ) -> ChatRouteReadinessIssue? {
        currentRouteReadinessIssue(for: text, appendUserMessage: appendUserMessage)
    }

    func blockSendForRouteReadinessForSend(_ issue: ChatRouteReadinessIssue) {
        blockSendForRouteReadiness(issue)
    }

    func captureInferredMemoryForSend(from text: String) {
        captureInferredMemory(from: text)
    }

    func discardActiveDraftForSend() {
        discardActiveDraft()
    }

    func resolvePromptAttachmentsForSendBridge(_ promptAttachments: [ChatAttachment]) async throws -> [ChatAttachment] {
        try await resolvePromptAttachmentsForSend(promptAttachments)
    }

    func ensureDocumentTextsForSend(attachments: [ChatAttachment]) async {
        await attachmentStagingStore.ensureDocumentTextsAvailable(for: attachments, using: fileService)
    }

    func displayFailureMessageForSend(_ rawValue: String) -> String {
        Self.displayFailureMessage(rawValue)
    }

    func displayFailureMessageForSend(_ error: Error) -> String {
        Self.displayFailureMessage(error)
    }

    func localFailureMessageForSend(from text: String) -> String? {
        Self.localFailureMessage(from: text)
    }

    func privacyProxyModelIDForSend() -> String? {
        modelCatalogStore.preferredPrivacyProxyModel(nearCloudKeyConfigured: nearCloudKeyConfigured)
    }

    func isRestrictedRouteErrorForSend(_ error: Error) -> Bool {
        RouteHealthMonitor.isRestrictedClassError(error)
    }

    func isExternalModelForSend(_ modelID: String) -> Bool {
        Self.isExternalModel(modelID)
    }

    func refreshModelsForSend() async {
        await refreshModels()
    }

    func scheduleAccountBackgroundRefreshForSend() {
        scheduleAccountBackgroundRefresh()
    }

    func ensureSelectedModelIsAvailableForSend() {
        ensureSelectedModelIsAvailable(shouldShowBanner: true)
    }

    func phoneAgentMissionPromptIfNeededForSend(for text: String) -> String? {
        phoneAgentMissionPromptIfNeeded(for: text)
    }

    func requestCouncilModelIDsForSend(for modelID: String) -> [String] {
        requestCouncilModelIDs(for: modelID)
    }

    func localDocumentPayloadsForSend(attachments: [ChatAttachment]) -> [DocumentTextExtractor.LocalDocumentContextPayload] {
        attachmentStagingStore.documentPayloads(for: attachments)
    }

    func documentAugmentedPromptForSend(
        _ prompt: String,
        question: String,
        attachments: [ChatAttachment]
    ) -> String {
        attachmentStagingStore.documentAugmentedPrompt(prompt, question: question, attachments: attachments)
    }

    func ensureConversationForSend(firstMessage: String, attachments: [ChatAttachment]) async throws -> ConversationSummary {
        try await ensureConversation(for: firstMessage, attachments: attachments)
    }

    func activateConversationForSend(_ conversation: ConversationSummary) {
        chatSessionCoordinator.activateConversationForSend(conversation) {
            transitionDraftScopeToCurrentSelection(loadDraft: false)
        }
    }

    func organizePhoneAgentConversationIfNeededForSend(
        conversation: ConversationSummary,
        originalText: String,
        routedText: String
    ) {
        organizePhoneAgentConversationIfNeeded(
            conversation: conversation,
            originalText: originalText,
            routedText: routedText
        )
    }

    func sendCouncilTurnBridge(
        text: String,
        routedText: String,
        attachments: [ChatAttachment],
        conversation: ConversationSummary,
        modelIDs: [String],
        previousResponseID: String?,
        initiator: String
    ) async throws {
        try await sendCouncilTurn(
            text: text,
            routedText: routedText,
            attachments: attachments,
            conversation: conversation,
            modelIDs: modelIDs,
            previousResponseID: previousResponseID,
            initiator: initiator
        )
    }

    func assistantTrustMetadataForSend(
        for model: String?,
        webSearchUsed: Bool?,
        capturedAt: Date
    ) -> MessageTrustMetadata? {
        assistantTrustMetadata(for: model, webSearchUsed: webSearchUsed, capturedAt: capturedAt)
    }

    func streamResponseWithFallbackForSend(
        initialModel: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        initiator: String
    ) async throws -> String {
        try await streamResponseWithFallback(
            initialModel: initialModel,
            text: text,
            attachments: attachments,
            conversationID: conversationID,
            previousResponseID: previousResponseID,
            initiator: initiator
        )
    }

    func saveLocalMessagesForSend(conversationID: String) {
        saveLocalMessages(for: conversationID)
    }

    func scheduleMessageLoadForSend(conversation: ConversationSummary, preferCached: Bool) {
        scheduleMessageLoad(for: conversation, preferCached: preferCached)
    }

    func scheduleConversationListRefreshForSend() {
        scheduleConversationListRefresh()
    }

    func showBannerForSend(_ message: String) {
        showBanner(message)
    }
}
