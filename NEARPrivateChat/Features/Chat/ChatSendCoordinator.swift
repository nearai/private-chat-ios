import Foundation

@MainActor
protocol ChatSendCoordinatorHost: AnyObject {
    var sendDraftText: String { get set }
    var sendPendingAttachments: [ChatAttachment] { get set }
    var sendPendingLargePasteTexts: [String: String] { get set }
    var sendPendingSharedFileURLs: [String: URL] { get set }
    var sendIsStreaming: Bool { get set }
    var sendRouteReadinessIssue: ChatRouteReadinessIssue? { get set }
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
    func isExternalModelForSend(_ modelID: String) -> Bool
    func refreshModelsForSend() async
    func scheduleAccountBackgroundRefreshForSend()
    func ensureSelectedModelIsAvailableForSend()
    func phoneAgentMissionPromptIfNeededForSend(for text: String) -> String?
    func requestCouncilModelIDsForSend(for modelID: String) -> [String]
    func localDocumentPayloadsForSend(attachments: [ChatAttachment]) -> [DocumentTextExtractor.LocalDocumentContextPayload]
    func documentAugmentedPromptForSend(_ prompt: String, question: String, attachments: [ChatAttachment]) -> String
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
        if let selectedConversation = host.sendSelectedConversation,
           host.sendMessages.contains(where: { host.isExternalModelForSend($0.model ?? "") }) {
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
        appendUserMessage: Bool = true
    ) async -> Bool {
        guard let host else { return false }
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
            let requestModel = host.sendSelectedModel
            let apiAttachments = attachments.filter { !$0.isLocalOnly }
            let previousAssistantMessage = host.sendMessages.last(where: { $0.role == .assistant })
            let candidatePreviousResponseID = previousResponseIDOverride ??
                previousAssistantMessage.flatMap { host.isExternalModelForSend($0.model ?? "") ? nil : $0.responseID }
            let previousResponseID = apiAttachments.isEmpty ? candidatePreviousResponseID : nil
            failureModel = requestModel
            failurePreviousResponseID = previousResponseID
            let requestInitiator = initiator ?? (existingConversation == nil ? "new_chat" : "new_message")
            let councilModelIDs = appendUserMessage ? host.requestCouncilModelIDsForSend(for: requestModel) : []
            let localDocPayloads = host.localDocumentPayloadsForSend(attachments: attachments.filter(\.isLocalOnly))
            if !localDocPayloads.isEmpty {
                if DocumentTextExtractor.localDocsAllowedForRoute(councilModelIDs: councilModelIDs, singleModelID: requestModel) {
                    let localDocQuery = DocumentTextExtractor.localDocumentQuery(
                        userText: text,
                        actionSurfaceText: actionSurfaceText
                    )
                    if let context = DocumentTextExtractor.localDocumentContextBlock(for: localDocQuery, payloads: localDocPayloads, topK: 4) {
                        routedText = "\(context)\n\nUsing those excerpts (my attached on-device document) where relevant:\n\(routedText)"
                    }
                } else {
                    host.showBannerForSend("Your on-device document stays private — its text isn’t sent to cloud or hosted models. Switch to the private model to use it here.")
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
                try await host.sendCouncilTurnBridge(
                    text: text,
                    routedText: routedText,
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
            if let selectedConversation = host.sendSelectedConversation,
               host.sendMessages.contains(where: { host.isExternalModelForSend($0.model ?? "") }) {
                host.saveLocalMessagesForSend(conversationID: selectedConversation.id)
            }
            host.showBannerForSend(displayError)
            return true
        }
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
