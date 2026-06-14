import Foundation

@MainActor
protocol ChatSendCoordinatorHost: AnyObject {
    var sendDraftText: String { get set }
    var sendPendingAttachments: [ChatAttachment] { get set }
    var sendPendingLargePasteTexts: [String: String] { get set }
    var sendPendingSharedFileURLs: [String: URL] { get set }
    var sendIsStreaming: Bool { get set }
    var sendRouteReadinessIssue: ChatRouteReadinessIssue? { get set }
    var sendProxyRetryOffer: ProxyRetryOffer? { get set }
    var sendPendingHostedHandoffPreflight: HostedIronclawHandoffPreflight? { get set }
    var sendSelectedModel: String { get set }
    var sendSelectedConversation: ConversationSummary? { get }
    var sendSelectedProjectID: String? { get }
    var sendMessages: [ChatMessage] { get set }
    var sendCurrentAssistantMessageID: String? { get set }
    var sendCurrentCouncilAssistantMessageIDs: [String] { get set }
    var sendCouncilStopRequestedBatchID: String? { get set }
    var sendStreamTask: Task<Void, Never>? { get set }
    var sendMessageTimelineStore: MessageTimelineStore { get }
    var sendCurrentUserMessageMetadata: MessageMetadata? { get }
    var sendModelsAreEmpty: Bool { get }
    var sendBillingSnapshotIsMissing: Bool { get }

    func normalizedSendDraftInput(_ draft: String) -> String
    func promptSourcePrivacyOverrideForSend(for prompt: String, hasAttachments: Bool) -> ChatPromptSourcePrivacyOverride
    func applyPromptSourcePrivacyOverrideForSend(_ override: ChatPromptSourcePrivacyOverride)
    func activeAttachmentsForSend(promptAttachments: [ChatAttachment]) -> [ChatAttachment]
    func promptOnlyAttachmentsForSend(from attachments: [ChatAttachment]) -> [ChatAttachment]
    func consumeLocalSendFastPathIfNeeded(text: String, promptAttachments: [ChatAttachment], activeAttachments: [ChatAttachment]) -> Bool
    func actionSurfaceTextForSend(text: String, attachments: [ChatAttachment], override: ChatPromptSourcePrivacyOverride) -> String
    func routeCurrentPromptIfNeededForSend(_ text: String, attachments: [ChatAttachment])
    func hostedHandoffPreflightForSend(text: String, promptAttachments: [ChatAttachment]) -> HostedIronclawHandoffPreflight?
    func currentRouteReadinessIssueForSend(for text: String, appendUserMessage: Bool) -> ChatRouteReadinessIssue?
    func blockSendForRouteReadinessForSend(_ issue: ChatRouteReadinessIssue)
    func captureInferredMemoryForSend(from text: String)
    func discardActiveDraftForSend()
    func resolvePromptAttachmentsForSendBridge(_ promptAttachments: [ChatAttachment]) async throws -> [ChatAttachment]
    func displayFailureMessageForSend(_ rawValue: String) -> String
    func localFailureMessageForSend(from text: String) -> String?
    func privacyProxyModelIDForSend() -> String?
    func isRestrictedRouteErrorForSend(_ error: Error) -> Bool
    func isExternalModelForSend(_ modelID: String) -> Bool
    func refreshModelsForSend() async
    func scheduleAccountBackgroundRefreshForSend()
    func ensureSelectedModelIsAvailableForSend()
    func phoneAgentMissionPromptIfNeededForSend(for text: String) -> String?
    func requestCouncilModelIDsForSend(for modelID: String) -> [String]
    func localDocumentPayloadsForSend(attachments: [ChatAttachment]) -> [DocumentTextExtractor.LocalDocumentContextPayload]
    func documentAugmentedPromptForSend(_ prompt: String, question: String, attachments: [ChatAttachment]) -> String
    func ensureDocumentTextsForSend(attachments: [ChatAttachment]) async
    func ensureConversationForSend(firstMessage: String, attachments: [ChatAttachment]) async throws -> ConversationSummary
    func activateConversationForSend(_ conversation: ConversationSummary)
    func organizePhoneAgentConversationIfNeededForSend(conversation: ConversationSummary, originalText: String, routedText: String)
    func sendCouncilTurnBridge(
        text: String,
        routedText: String,
        attachments: [ChatAttachment],
        conversation: ConversationSummary,
        modelIDs: [String],
        previousResponseID: String?,
        initiator: String
    ) async throws
    func assistantTrustMetadataForSend(for model: String?, webSearchUsed: Bool?, capturedAt: Date) -> MessageTrustMetadata?
    func streamResponseWithFallbackForSend(
        initialModel: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        initiator: String
    ) async throws -> String
    func saveLocalMessagesForSend(conversationID: String)
    func scheduleMessageLoadForSend(conversation: ConversationSummary, preferCached: Bool)
    func scheduleConversationListRefreshForSend()
    func showBannerForSend(_ message: String)
}

@MainActor
final class ChatSendCoordinator {
    private weak var host: ChatSendCoordinatorHost?
    private var pendingHostedHandoffContinuation: HostedHandoffContinuation?
    private var approvedHostedHandoffFingerprint: String?

    private enum HostedHandoffContinuation {
        case draft
        case regenerate(ChatMessage)
        case edit(ChatMessage, String)
        case directSend(
            text: String,
            attachments: [ChatAttachment],
            previousResponseIDOverride: String?,
            initiator: String?,
            appendUserMessage: Bool
        )
    }

    init(host: ChatSendCoordinatorHost) {
        self.host = host
    }

    func reset() {
        host?.sendStreamTask?.cancel()
        host?.sendStreamTask = nil
        host?.sendMessageTimelineStore.cancelPendingTextDeltaFlushes()
        host?.sendCurrentAssistantMessageID = nil
        host?.sendCurrentCouncilAssistantMessageIDs = []
        host?.sendCouncilStopRequestedBatchID = nil
        pendingHostedHandoffContinuation = nil
        approvedHostedHandoffFingerprint = nil
    }

    func sendDraft() {
        guard let host else { return }
        let text = host.normalizedSendDraftInput(host.sendDraftText).trimmingCharacters(in: .whitespacesAndNewlines)
        let promptAttachments = host.sendPendingAttachments
        let pendingLargePasteTextsSnapshot = host.sendPendingLargePasteTexts
        let pendingSharedFileURLsSnapshot = host.sendPendingSharedFileURLs
        let attachments = host.activeAttachmentsForSend(promptAttachments: promptAttachments)
        guard (!text.isEmpty || !attachments.isEmpty), !host.sendIsStreaming else { return }

        let promptSourceOverride = host.promptSourcePrivacyOverrideForSend(
            for: text,
            hasAttachments: !attachments.isEmpty
        )
        host.applyPromptSourcePrivacyOverrideForSend(promptSourceOverride)

        if host.consumeLocalSendFastPathIfNeeded(
            text: text,
            promptAttachments: promptAttachments,
            activeAttachments: attachments
        ) {
            return
        }

        let preflightText = host.actionSurfaceTextForSend(
            text: text,
            attachments: attachments,
            override: promptSourceOverride
        )
        host.routeCurrentPromptIfNeededForSend(preflightText, attachments: attachments)
        if blockLocalOnlyDocumentsIfNeeded(
            text: text,
            actionSurfaceText: preflightText,
            attachments: attachments,
            appendUserMessage: true,
            modelOverride: nil
        ) {
            return
        }
        if let preflight = host.hostedHandoffPreflightForSend(text: preflightText, promptAttachments: promptAttachments),
           approvedHostedHandoffFingerprint != preflight.fingerprint {
            pendingHostedHandoffContinuation = .draft
            host.sendPendingHostedHandoffPreflight = preflight
            return
        }
        if let issue = host.currentRouteReadinessIssueForSend(for: text, appendUserMessage: true) {
            host.blockSendForRouteReadinessForSend(issue)
            return
        }

        host.sendRouteReadinessIssue = nil
        if attachments.isEmpty {
            host.captureInferredMemoryForSend(from: text)
        }
        host.discardActiveDraftForSend()
        host.sendDraftText = ""
        host.sendPendingAttachments = []
        host.sendStreamTask = Task { [weak self] in
            await self?.sendResolvedDraft(
                text: text,
                promptAttachments: promptAttachments,
                pendingLargePasteTextsSnapshot: pendingLargePasteTextsSnapshot,
                pendingSharedFileURLsSnapshot: pendingSharedFileURLsSnapshot
            )
        }
    }

    func confirmHostedHandoff(_ preflight: HostedIronclawHandoffPreflight) {
        guard let host else { return }
        let continuation = pendingHostedHandoffContinuation
        approvedHostedHandoffFingerprint = preflight.fingerprint
        pendingHostedHandoffContinuation = nil
        host.sendPendingHostedHandoffPreflight = nil
        switch continuation {
        case .draft, .none:
            sendDraft()
        case let .regenerate(message):
            regenerateResponse(for: message)
        case let .edit(message, replacementText):
            editAndResend(message, replacementText: replacementText)
        case let .directSend(text, attachments, previousResponseIDOverride, initiator, appendUserMessage):
            host.sendDraftText = ""
            host.sendPendingAttachments = []
            host.sendPendingSharedFileURLs = [:]
            host.sendStreamTask = Task { [weak self] in
                _ = await self?.send(
                    text,
                    attachments: attachments,
                    previousResponseIDOverride: previousResponseIDOverride,
                    initiator: initiator,
                    appendUserMessage: appendUserMessage
                )
            }
        }
    }

    func cancelHostedHandoff() {
        guard let host else { return }
        host.sendPendingHostedHandoffPreflight = nil
        pendingHostedHandoffContinuation = nil
        approvedHostedHandoffFingerprint = nil
        host.showBannerForSend("Hosted IronClaw handoff cancelled.")
    }

    func cancelStream() {
        guard let host else { return }
        host.sendStreamTask?.cancel()
        host.sendStreamTask = nil
        host.sendIsStreaming = false
        host.sendMessageTimelineStore.markStreamingMessagesCancelled(
            assistantMessageID: host.sendCurrentAssistantMessageID,
            councilAssistantMessageIDs: host.sendCurrentCouncilAssistantMessageIDs
        )
        host.sendCurrentCouncilAssistantMessageIDs = []
        host.sendCouncilStopRequestedBatchID = nil
        // Always persist: partial private/council text must survive a cancel
        // (the merge rules preserve "cancelled" turns on re-open).
        if let selectedConversation = host.sendSelectedConversation {
            host.saveLocalMessagesForSend(conversationID: selectedConversation.id)
        }
    }

    func regenerateResponse(for message: ChatMessage) {
        guard let host, !host.sendIsStreaming else { return }
        guard message.role == .assistant,
              let assistantIndex = host.sendMessages.firstIndex(where: { $0.id == message.id }),
              let userMessage = host.sendMessages[..<assistantIndex].last(where: { $0.role == .user }) else {
            host.showBannerForSend("No prompt found to regenerate.")
            return
        }
        let promptAttachments = host.promptOnlyAttachmentsForSend(from: userMessage.attachments)
        let attachments = host.activeAttachmentsForSend(promptAttachments: promptAttachments)
        let parentResponseID = message.previousResponseID ??
            host.sendMessages[..<assistantIndex].last(where: { $0.role == .assistant })?.responseID
        host.routeCurrentPromptIfNeededForSend(userMessage.text, attachments: attachments)
        if blockLocalOnlyDocumentsIfNeeded(
            text: userMessage.text,
            actionSurfaceText: userMessage.text,
            attachments: attachments,
            appendUserMessage: false,
            modelOverride: nil
        ) {
            return
        }
        if let preflight = host.hostedHandoffPreflightForSend(text: userMessage.text, promptAttachments: promptAttachments),
           approvedHostedHandoffFingerprint != preflight.fingerprint {
            pendingHostedHandoffContinuation = .regenerate(message)
            host.sendPendingHostedHandoffPreflight = preflight
            return
        }
        if let issue = host.currentRouteReadinessIssueForSend(for: userMessage.text, appendUserMessage: false) {
            host.blockSendForRouteReadinessForSend(issue)
            return
        }
        if let conversationID = host.sendSelectedConversation?.id {
            host.sendMessageTimelineStore.clearSelectedResponseVariant(for: conversationID)
        }
        var updatedMessages = host.sendMessages
        updatedMessages.removeSubrange(assistantIndex..<updatedMessages.endIndex)
        host.sendMessages = updatedMessages
        host.showBannerForSend("Regenerating response.")
        host.sendStreamTask = Task { [weak self] in
            _ = await self?.send(
                userMessage.text,
                attachments: attachments,
                previousResponseIDOverride: parentResponseID,
                initiator: "regenerate",
                appendUserMessage: false
            )
        }
    }

    func regenerateResponseViaPrivacyProxy(for message: ChatMessage) {
        guard let host, !host.sendIsStreaming else { return }
        guard let proxyModelID = host.privacyProxyModelIDForSend() else {
            host.showBannerForSend("Connect NEAR AI Cloud in Account, then send again.")
            return
        }
        guard message.role == .assistant,
              let assistantIndex = host.sendMessages.firstIndex(where: { $0.id == message.id }),
              let userMessage = host.sendMessages[..<assistantIndex].last(where: { $0.role == .user }) else {
            host.showBannerForSend("No prompt found to retry through the privacy proxy.")
            return
        }
        let promptAttachments = host.promptOnlyAttachmentsForSend(from: userMessage.attachments)
        let attachments = host.activeAttachmentsForSend(promptAttachments: promptAttachments)
        let parentResponseID = message.previousResponseID ??
            host.sendMessages[..<assistantIndex].last(where: { $0.role == .assistant })?.responseID
        if blockLocalOnlyDocumentsIfNeeded(
            text: userMessage.text,
            actionSurfaceText: userMessage.text,
            attachments: attachments,
            appendUserMessage: false,
            modelOverride: proxyModelID
        ) {
            return
        }
        if let conversationID = host.sendSelectedConversation?.id {
            host.sendMessageTimelineStore.clearSelectedResponseVariant(for: conversationID)
        }
        var updatedMessages = host.sendMessages
        updatedMessages.removeSubrange(assistantIndex..<updatedMessages.endIndex)
        host.sendMessages = updatedMessages
        host.showBannerForSend("Answering via privacy proxy for this turn. Your default model is unchanged.")
        host.sendStreamTask = Task { [weak self] in
            _ = await self?.send(
                userMessage.text,
                attachments: attachments,
                previousResponseIDOverride: parentResponseID,
                initiator: "proxy_retry",
                appendUserMessage: false,
                modelOverride: proxyModelID
            )
        }
    }

    func editAndResend(_ message: ChatMessage, replacementText: String) {
        guard let host, !host.sendIsStreaming else { return }
        let text = host.normalizedSendDraftInput(replacementText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.role == .user,
              let userIndex = host.sendMessages.firstIndex(where: { $0.id == message.id }),
              (!text.isEmpty || !message.attachments.isEmpty) else {
            host.showBannerForSend("No prompt found to edit.")
            return
        }

        let promptAttachments = host.promptOnlyAttachmentsForSend(from: message.attachments)
        let attachments = host.activeAttachmentsForSend(promptAttachments: promptAttachments)
        let parentResponseID = message.previousResponseID
        host.routeCurrentPromptIfNeededForSend(text, attachments: attachments)
        if blockLocalOnlyDocumentsIfNeeded(
            text: text,
            actionSurfaceText: text,
            attachments: attachments,
            appendUserMessage: true,
            modelOverride: nil
        ) {
            return
        }
        if let preflight = host.hostedHandoffPreflightForSend(text: text, promptAttachments: promptAttachments),
           approvedHostedHandoffFingerprint != preflight.fingerprint {
            pendingHostedHandoffContinuation = .edit(message, replacementText)
            host.sendPendingHostedHandoffPreflight = preflight
            return
        }
        if let issue = host.currentRouteReadinessIssueForSend(for: text, appendUserMessage: true) {
            host.blockSendForRouteReadinessForSend(issue)
            return
        }
        if let conversationID = host.sendSelectedConversation?.id {
            host.sendMessageTimelineStore.clearSelectedResponseVariant(for: conversationID)
        }
        var updatedMessages = host.sendMessages
        updatedMessages.removeSubrange(userIndex..<updatedMessages.endIndex)
        host.sendMessages = updatedMessages
        host.showBannerForSend("Branching from edited prompt.")
        host.sendStreamTask = Task { [weak self] in
            _ = await self?.send(
                text,
                attachments: attachments,
                previousResponseIDOverride: parentResponseID,
                initiator: "edit_message",
                appendUserMessage: true
            )
        }
    }

    func sendResolvedDraftForBridge(
        text: String,
        promptAttachments: [ChatAttachment],
        pendingLargePasteTextsSnapshot: [String: String],
        pendingSharedFileURLsSnapshot: [String: URL]
    ) async {
        await sendResolvedDraft(
            text: text,
            promptAttachments: promptAttachments,
            pendingLargePasteTextsSnapshot: pendingLargePasteTextsSnapshot,
            pendingSharedFileURLsSnapshot: pendingSharedFileURLsSnapshot
        )
    }

    @discardableResult
    func sendForBridge(
        _ text: String,
        attachments: [ChatAttachment],
        previousResponseIDOverride: String? = nil,
        initiator: String? = nil,
        appendUserMessage: Bool = true
    ) async -> Bool {
        await send(
            text,
            attachments: attachments,
            previousResponseIDOverride: previousResponseIDOverride,
            initiator: initiator,
            appendUserMessage: appendUserMessage
        )
    }

    private func sendResolvedDraft(
        text: String,
        promptAttachments: [ChatAttachment],
        pendingLargePasteTextsSnapshot: [String: String],
        pendingSharedFileURLsSnapshot: [String: URL]
    ) async {
        guard let host else { return }
        do {
            let resolvedPromptAttachments = try await host.resolvePromptAttachmentsForSendBridge(promptAttachments)
            let attachments = host.activeAttachmentsForSend(promptAttachments: resolvedPromptAttachments)
            let didStartSend = await send(text, attachments: attachments)
            if !didStartSend {
                restoreDraft(
                    text: text,
                    promptAttachments: promptAttachments,
                    pendingLargePasteTextsSnapshot: pendingLargePasteTextsSnapshot,
                    pendingSharedFileURLsSnapshot: pendingSharedFileURLsSnapshot
                )
            }
        } catch is CancellationError {
            restoreDraft(
                text: text,
                promptAttachments: promptAttachments,
                pendingLargePasteTextsSnapshot: pendingLargePasteTextsSnapshot,
                pendingSharedFileURLsSnapshot: pendingSharedFileURLsSnapshot
            )
        } catch {
            restoreDraft(
                text: text,
                promptAttachments: promptAttachments,
                pendingLargePasteTextsSnapshot: pendingLargePasteTextsSnapshot,
                pendingSharedFileURLsSnapshot: pendingSharedFileURLsSnapshot
            )
            host.showBannerForSend(host.displayFailureMessageForSend(error.localizedDescription))
        }
    }

    private func restoreDraft(
        text: String,
        promptAttachments: [ChatAttachment],
        pendingLargePasteTextsSnapshot: [String: String],
        pendingSharedFileURLsSnapshot: [String: URL]
    ) {
        guard let host else { return }
        host.sendDraftText = text
        host.sendPendingAttachments = promptAttachments
        host.sendPendingLargePasteTexts = pendingLargePasteTextsSnapshot
        host.sendPendingSharedFileURLs = pendingSharedFileURLsSnapshot
    }

    private func send(
        _ text: String,
        attachments: [ChatAttachment],
        previousResponseIDOverride: String? = nil,
        initiator: String? = nil,
        appendUserMessage: Bool = true,
        modelOverride: String? = nil
    ) async -> Bool {
        guard let host else { return false }
        host.sendProxyRetryOffer = nil
        let promptAttachments = host.promptOnlyAttachmentsForSend(from: attachments)
        let promptSourceOverride = host.promptSourcePrivacyOverrideForSend(
            for: text,
            hasAttachments: !attachments.isEmpty
        )
        host.applyPromptSourcePrivacyOverrideForSend(promptSourceOverride)
        let actionSurfaceText = host.actionSurfaceTextForSend(
            text: text,
            attachments: attachments,
            override: promptSourceOverride
        )
        if blockLocalOnlyDocumentsIfNeeded(
            text: text,
            actionSurfaceText: actionSurfaceText,
            attachments: attachments,
            appendUserMessage: appendUserMessage,
            modelOverride: modelOverride
        ) {
            return false
        }
        if let preflight = host.hostedHandoffPreflightForSend(text: actionSurfaceText, promptAttachments: promptAttachments),
           approvedHostedHandoffFingerprint != preflight.fingerprint {
            pendingHostedHandoffContinuation = .directSend(
                text: text,
                attachments: attachments,
                previousResponseIDOverride: previousResponseIDOverride,
                initiator: initiator,
                appendUserMessage: appendUserMessage
            )
            host.sendPendingHostedHandoffPreflight = preflight
            return false
        }

        host.sendIsStreaming = true
        let approvedHandoffForTurn = approvedHostedHandoffFingerprint
        defer {
            host.sendIsStreaming = false
            host.sendCurrentAssistantMessageID = nil
            host.sendCurrentCouncilAssistantMessageIDs = []
            host.sendCouncilStopRequestedBatchID = nil
            if approvedHostedHandoffFingerprint == approvedHandoffForTurn {
                approvedHostedHandoffFingerprint = nil
            }
            host.sendStreamTask = nil
        }

        var failureModel = host.sendSelectedModel
        var failurePreviousResponseID = previousResponseIDOverride

        do {
            if host.sendModelsAreEmpty {
                await host.refreshModelsForSend()
            }
            if host.sendBillingSnapshotIsMissing {
                host.scheduleAccountBackgroundRefreshForSend()
            }
            host.ensureSelectedModelIsAvailableForSend()
            host.routeCurrentPromptIfNeededForSend(text, attachments: attachments)
            if blockLocalOnlyDocumentsIfNeeded(
                text: text,
                actionSurfaceText: actionSurfaceText,
                attachments: attachments,
                appendUserMessage: appendUserMessage,
                modelOverride: modelOverride
            ) {
                return false
            }
            if let preflight = host.hostedHandoffPreflightForSend(text: actionSurfaceText, promptAttachments: promptAttachments),
               approvedHostedHandoffFingerprint != preflight.fingerprint {
                pendingHostedHandoffContinuation = .directSend(
                    text: text,
                    attachments: attachments,
                    previousResponseIDOverride: previousResponseIDOverride,
                    initiator: initiator,
                    appendUserMessage: appendUserMessage
                )
                host.sendPendingHostedHandoffPreflight = preflight
                return false
            }
            if let issue = host.currentRouteReadinessIssueForSend(for: text, appendUserMessage: appendUserMessage) {
                host.blockSendForRouteReadinessForSend(issue)
                return false
            }
            host.sendRouteReadinessIssue = nil

            let mission = host.phoneAgentMissionPromptIfNeededForSend(for: text)
            var routedText = mission ?? actionSurfaceText
            let existingConversation = host.sendSelectedConversation
            // modelOverride = single-turn disclosed route switch (proxy retry);
            // the user's selected model is deliberately left unchanged.
            let requestModel = modelOverride ?? host.sendSelectedModel
            let apiAttachments = attachments.filter { !$0.isLocalOnly }
            let previousAssistantMessage = host.sendMessages.last(where: { $0.role == .assistant })
            let candidatePreviousResponseID = previousResponseIDOverride ??
                previousAssistantMessage.flatMap { host.isExternalModelForSend($0.model ?? "") ? nil : $0.responseID }
            let previousResponseID = apiAttachments.isEmpty ? candidatePreviousResponseID : nil
            failureModel = requestModel
            failurePreviousResponseID = previousResponseID
            let requestInitiator = initiator ?? (existingConversation == nil ? "new_chat" : "new_message")
            // Proxy retries are single-model by design — no council fan-out.
            let councilModelIDs = (appendUserMessage && modelOverride == nil)
                ? host.requestCouncilModelIDsForSend(for: requestModel)
                : []
            let localDocPayloads = host.localDocumentPayloadsForSend(attachments: attachments.filter(\.isLocalOnly))
            if !localDocPayloads.isEmpty {
                let localDocQuery = DocumentTextExtractor.localDocumentQuery(
                    userText: text,
                    actionSurfaceText: actionSurfaceText
                )
                if let context = DocumentTextExtractor.localDocumentContextBlock(for: localDocQuery, payloads: localDocPayloads, topK: 4) {
                    routedText = "\(context)\n\nUsing those excerpts (my attached on-device document) where relevant:\n\(routedText)"
                }
            }
            if councilModelIDs.count > 1 {
                let conversation = try await host.ensureConversationForSend(firstMessage: text, attachments: apiAttachments)
                host.activateConversationForSend(conversation)
                host.organizePhoneAgentConversationIfNeededForSend(
                    conversation: conversation,
                    originalText: text,
                    routedText: mission ?? actionSurfaceText
                )
                // Council members get the same document excerpts as single-model
                // sends (previously skipped — file turns reached members as bare
                // filenames). Same all-private privacy gate as on-device docs.
                await host.ensureDocumentTextsForSend(attachments: apiAttachments)
                let councilText = DocumentTextExtractor.localDocsAllowedForRoute(
                    councilModelIDs: councilModelIDs,
                    singleModelID: requestModel
                )
                    ? host.documentAugmentedPromptForSend(routedText, question: text, attachments: apiAttachments)
                    : routedText
                try await host.sendCouncilTurnBridge(
                    text: text,
                    routedText: councilText,
                    attachments: apiAttachments,
                    conversation: conversation,
                    modelIDs: councilModelIDs,
                    previousResponseID: previousResponseID,
                    initiator: requestInitiator
                )
                return true
            }

            let userMessage = ChatMessage(
                id: "local-user-\(UUID().uuidString)",
                role: .user,
                text: text,
                model: requestModel,
                createdAt: Date(),
                status: "completed",
                responseID: nil,
                previousResponseID: previousResponseID,
                isStreaming: false,
                attachments: attachments,
                metadata: host.sendCurrentUserMessageMetadata
            )
            let assistantCreatedAt = Date()
            let assistantMessage = ChatMessage(
                id: "local-assistant-\(UUID().uuidString)",
                role: .assistant,
                text: "",
                model: requestModel,
                createdAt: assistantCreatedAt,
                status: "streaming",
                responseID: nil,
                previousResponseID: previousResponseID,
                isStreaming: true,
                trustMetadata: host.assistantTrustMetadataForSend(for: requestModel, webSearchUsed: nil, capturedAt: assistantCreatedAt)
            )
            host.sendCurrentAssistantMessageID = assistantMessage.id
            if appendUserMessage {
                host.sendMessages.append(userMessage)
            }
            host.sendMessages.append(assistantMessage)

            let conversation = try await host.ensureConversationForSend(firstMessage: text, attachments: apiAttachments)
            host.activateConversationForSend(conversation)
            host.organizePhoneAgentConversationIfNeededForSend(
                conversation: conversation,
                originalText: text,
                routedText: mission ?? actionSurfaceText
            )

            if mission == nil {
                // Re-stage extracted text lost to an app restart (it is held
                // in memory only) so the context block below has content.
                await host.ensureDocumentTextsForSend(attachments: apiAttachments)
            }
            let finalText = mission == nil
                ? host.documentAugmentedPromptForSend(routedText, question: text, attachments: apiAttachments)
                : routedText
            let finalModel = try await host.streamResponseWithFallbackForSend(
                initialModel: requestModel,
                text: finalText,
                attachments: apiAttachments,
                conversationID: conversation.id,
                previousResponseID: previousResponseID,
                initiator: requestInitiator
            )

            if let currentAssistantMessageID = host.sendCurrentAssistantMessageID {
                host.sendMessageTimelineStore.updateMessage(currentAssistantMessageID) { message in
                    message.isStreaming = false
                    if message.status != "failed", message.status != "approval" {
                        message.status = "completed"
                    }
                    message.trustMetadata = host.assistantTrustMetadataForSend(
                        for: finalModel,
                        webSearchUsed: !message.sources.isEmpty ? true : nil,
                        capturedAt: message.createdAt
                    )
                }
            }

            if host.isExternalModelForSend(finalModel) {
                host.saveLocalMessagesForSend(conversationID: conversation.id)
            } else {
                host.saveLocalMessagesForSend(conversationID: conversation.id)
                host.scheduleMessageLoadForSend(conversation: conversation, preferCached: false)
            }
            host.scheduleConversationListRefreshForSend()
            return true
        } catch is CancellationError {
            cancelStream()
            return true
        } catch {
            let displayError = host.displayFailureMessageForSend(error.localizedDescription)
            markVisibleFailureTurnIfNeeded(
                host: host,
                text: text,
                model: failureModel,
                previousResponseID: failurePreviousResponseID,
                attachments: attachments,
                appendUserMessage: appendUserMessage,
                displayError: displayError
            )
            offerProxyRetryIfApplicable(
                host: host,
                error: error,
                failedModel: failureModel,
                attemptedModelOverride: modelOverride,
                text: text,
                attachments: attachments,
                previousResponseID: failurePreviousResponseID
            )
            if let selectedConversation = host.sendSelectedConversation,
               host.sendMessages.contains(where: { message in
                   host.isExternalModelForSend(message.model ?? "") ||
                       ["failed", "cancelled", "approval"].contains(message.status.lowercased())
               }) {
                host.saveLocalMessagesForSend(conversationID: selectedConversation.id)
            }
            host.showBannerForSend(displayError)
            return true
        }
    }

    private func blockLocalOnlyDocumentsIfNeeded(
        text: String,
        actionSurfaceText: String,
        attachments: [ChatAttachment],
        appendUserMessage: Bool,
        modelOverride: String?
    ) -> Bool {
        guard let host else { return true }
        let localDocPayloads = host.localDocumentPayloadsForSend(attachments: attachments.filter(\.isLocalOnly))
        guard !localDocPayloads.isEmpty else { return false }
        let requestModel = modelOverride ?? host.sendSelectedModel
        let councilModelIDs = (appendUserMessage && modelOverride == nil)
            ? host.requestCouncilModelIDsForSend(for: requestModel)
            : []
        guard !DocumentTextExtractor.localDocsAllowedForRoute(councilModelIDs: councilModelIDs, singleModelID: requestModel) else {
            return false
        }
        host.sendPendingHostedHandoffPreflight = nil
        host.showBannerForSend("Switch to a private model to use this on-device document. Cloud, Council-with-cloud, and Hosted Agent routes cannot receive local-only document text.")
        return true
    }

    /// A restricted PRIVATE-route failure gets a one-tap "answer via privacy
    /// proxy" offer. Never built for cloud/agent failures or for a turn that
    /// was already a proxy retry.
    private func offerProxyRetryIfApplicable(
        host: ChatSendCoordinatorHost,
        error: Error,
        failedModel: String,
        attemptedModelOverride: String?,
        text: String,
        attachments: [ChatAttachment],
        previousResponseID: String?
    ) {
        guard attemptedModelOverride == nil,
              host.isRestrictedRouteErrorForSend(error),
              ChatStore.routeKind(forModelID: failedModel) == .nearPrivate else {
            return
        }
        host.sendProxyRetryOffer = ProxyRetryOffer(
            id: host.sendCurrentAssistantMessageID ?? "proxy-retry-\(UUID().uuidString)",
            originalModelID: failedModel,
            proxyModelID: host.privacyProxyModelIDForSend(),
            text: text,
            attachments: attachments,
            previousResponseID: previousResponseID,
            conversationID: host.sendSelectedConversation?.id
        )
    }

    /// Re-sends the offered turn through the privacy proxy. The selected model
    /// stays unchanged; the proxy answer is labeled by its own trust metadata.
    func acceptProxyRetry() {
        guard let host, let offer = host.sendProxyRetryOffer, !host.sendIsStreaming else { return }
        host.sendProxyRetryOffer = nil
        guard let proxyModelID = offer.proxyModelID else { return }
        host.showBannerForSend("Answering via privacy proxy for this turn. Your default model is unchanged.")
        host.sendStreamTask = Task { [weak self] in
            _ = await self?.send(
                offer.text,
                attachments: offer.attachments,
                previousResponseIDOverride: offer.previousResponseID,
                initiator: "proxy_retry",
                appendUserMessage: false,
                modelOverride: proxyModelID
            )
        }
    }

    func declineProxyRetry() {
        host?.sendProxyRetryOffer = nil
    }

    private func markVisibleFailureTurnIfNeeded(
        host: ChatSendCoordinatorHost,
        text: String,
        model: String,
        previousResponseID: String?,
        attachments: [ChatAttachment],
        appendUserMessage: Bool,
        displayError: String
    ) {
        func markFailure(_ message: inout ChatMessage) {
            message.isStreaming = false
            message.status = "failed"
            if let localFailure = host.localFailureMessageForSend(from: message.text) {
                message.text = localFailure
            } else if message.text.isEmpty {
                message.text = displayError
            } else if !message.text.localizedCaseInsensitiveContains(displayError) {
                message.text += "\n\nResponse failed: \(displayError)"
            }
        }

        if let currentAssistantMessageID = host.sendCurrentAssistantMessageID {
            host.sendMessageTimelineStore.updateMessage(currentAssistantMessageID, mutate: markFailure)
            return
        }

        if !host.sendCurrentCouncilAssistantMessageIDs.isEmpty {
            for messageID in host.sendCurrentCouncilAssistantMessageIDs {
                host.sendMessageTimelineStore.updateMessage(messageID, mutate: markFailure)
            }
            return
        }

        guard appendUserMessage else { return }

        let userMessage = ChatMessage(
            id: "local-user-\(UUID().uuidString)",
            role: .user,
            text: text,
            model: model,
            createdAt: Date(),
            status: "completed",
            responseID: nil,
            previousResponseID: previousResponseID,
            isStreaming: false,
            attachments: attachments,
            metadata: host.sendCurrentUserMessageMetadata
        )
        let assistantCreatedAt = Date().addingTimeInterval(0.01)
        let assistantMessage = ChatMessage(
            id: "local-assistant-\(UUID().uuidString)",
            role: .assistant,
            text: displayError,
            model: model,
            createdAt: assistantCreatedAt,
            status: "failed",
            responseID: nil,
            previousResponseID: previousResponseID,
            isStreaming: false,
            trustMetadata: host.assistantTrustMetadataForSend(
                for: model,
                webSearchUsed: nil,
                capturedAt: assistantCreatedAt
            )
        )
        host.sendMessages.append(userMessage)
        host.sendMessages.append(assistantMessage)
    }
}
