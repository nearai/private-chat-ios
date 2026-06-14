import Foundation

extension ChatStore {
    func sendDraft() {
        sendCoordinator.sendDraft()
    }

    func confirmHostedHandoff(_ preflight: HostedIronclawHandoffPreflight) {
        sendCoordinator.confirmHostedHandoff(preflight)
    }

    func cancelHostedHandoff() {
        sendCoordinator.cancelHostedHandoff()
    }

    func hostedHandoffPreflightIfNeeded(
        text: String,
        promptAttachments: [ChatAttachment]
    ) -> HostedIronclawHandoffPreflight? {
        agentStore.hostedHandoffPreflight(
            text: text,
            promptAttachments: promptAttachments,
            selectedModelID: selectedModel,
            promptNeedsHostedWorkstation: Self.promptNeedsRemoteWorkstation(text),
            projectDisclosure: projectStore.selectedHostedHandoffDisclosure
        )
    }

    func currentRouteReadinessIssue(
        for text: String,
        appendUserMessage: Bool = true
    ) -> RouteReadinessIssue? {
        let promptWantsCouncil = Self.promptRequestsCouncil(text)
        let councilRequested = appendUserMessage &&
            (isCouncilModeEnabled || councilModelIDs.count > 1 || promptWantsCouncil)
        let requestedCouncilIDs: [String]
        if councilRequested {
            if promptWantsCouncil, !isCouncilModeEnabled, councilModelIDs.count <= 1 {
                requestedCouncilIDs = defaultCouncilModelIDs()
            } else {
                requestedCouncilIDs = requestCouncilModelIDs(for: selectedModel)
            }
        } else {
            requestedCouncilIDs = []
        }

        return Self.routeReadinessIssue(
            selectedModelID: selectedModel,
            requestedCouncilModelIDs: requestedCouncilIDs,
            isCouncilRequested: councilRequested,
            nearCloudKeyConfigured: nearCloudKeyConfigured,
            hostedIronclawEndpointUsable: ironclawRemoteWorkstationAvailable,
            hostedIronclawEndpointMessage: hostedIronclawReadinessMessage
        )
    }

    private var hostedIronclawReadinessMessage: String? {
        if ironclawSettings.hasUsableHostedEndpoint, !ironclawSettings.isEnabled {
            return "Turn on Hosted IronClaw in Account before sending."
        }
        return ironclawSettings.endpointValidationMessage
    }

    func blockSendForRouteReadiness(_ issue: RouteReadinessIssue) {
        routeReadinessIssue = issue
        showBanner(issue.title)
    }

    private func sendResolvedDraft(
        text: String,
        promptAttachments: [ChatAttachment],
        pendingLargePasteTextsSnapshot: [String: String],
        pendingSharedFileURLsSnapshot: [String: URL]
    ) async {
        await sendCoordinator.sendResolvedDraftForBridge(
            text: text,
            promptAttachments: promptAttachments,
            pendingLargePasteTextsSnapshot: pendingLargePasteTextsSnapshot,
            pendingSharedFileURLsSnapshot: pendingSharedFileURLsSnapshot
        )
    }

    func cancelStream() {
        sendCoordinator.cancelStream()
    }

    /// One-tap disclosed retry of a restricted private turn via the privacy
    /// proxy. The user's selected model is unchanged.
    func acceptProxyRetry() {
        sendCoordinator.acceptProxyRetry()
    }

    func declineProxyRetry() {
        sendCoordinator.declineProxyRetry()
    }

    /// Manual "Try private now" — clears the private route's cooldown so the
    /// next send probes it immediately.
    func retryPrivateRouteNow() {
        routeHealth.resetRoute(.nearPrivate)
        showBanner("Private route re-enabled — the next message will try it.")
    }

    /// Retry a failed private answer immediately instead of waiting for the
    /// local route breaker window. Used only from disclosed failed-turn actions.
    func retryFailedPrivateResponseNow(for message: ChatMessage) {
        routeHealth.resetRoute(.nearPrivate)
        sendCoordinator.regenerateResponse(for: message)
    }

    func retryFailedResponseViaPrivacyProxy(for message: ChatMessage) {
        sendCoordinator.regenerateResponseViaPrivacyProxy(for: message)
    }

    func retryFailedCouncilMemberNow(for message: ChatMessage) {
        guard !isStreaming else {
            showBanner("Wait for the current run to finish first.")
            return
        }
        guard message.role == .assistant,
              message.status == "failed",
              let batchID = message.councilBatchID,
              !batchID.isEmpty,
              let modelID = message.model,
              !Self.isCouncilSynthesisModelID(modelID) else {
            retryFailedPrivateResponseNow(for: message)
            return
        }
        guard let conversation = selectedConversation else {
            showBanner("Open a Council conversation first.")
            return
        }
        let batchMessages = councilMessages(for: batchID)
        guard let prompt = Self.councilBatchPrompt(from: batchMessages) else {
            showBanner("No Council prompt found to retry.")
            return
        }
        guard councilRoutesAreReady([modelID]) else { return }
        if Self.routeKind(forModelID: modelID) == .nearPrivate {
            routeHealth.resetRoute(.nearPrivate)
        }

        let previousResponseID = Self.latestResponseID(in: batchMessages, modelID: modelID)
        let attachments = batchMessages
            .filter { $0.role == .user }
            .sorted { $0.createdAt < $1.createdAt }
            .first?
            .attachments ?? []
        routeReadinessIssue = nil
        streamTask = Task { [weak self] in
            await self?.retryCouncilMember(
                messageID: message.id,
                modelID: modelID,
                prompt: prompt,
                attachments: attachments,
                conversation: conversation,
                previousResponseID: previousResponseID
            )
        }
    }

    func stopWaitingForCouncil(batchID: String?) {
        guard let batchID, isStreaming else {
            return
        }
        let activeMessages = currentCouncilAssistantMessageIDs.compactMap { messageID in
            messages.first(where: { $0.id == messageID && $0.councilBatchID == batchID })
        }
        guard !activeMessages.isEmpty else {
            showBanner("That Council batch is not running.")
            return
        }
        if activeMessages.allSatisfy({ Self.isCouncilSynthesisModelID($0.model) }) {
            cancelStream()
            showBanner("Stopped Council synthesis.")
            return
        }
        councilStopRequestedBatchID = batchID
        showBanner("Stopping slow Council legs. Completed answers will be synthesized.")
    }

    func sendCouncilRoomFollowUp(_ text: String, batchID: String?, target: CouncilTarget) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isStreaming else {
            showBanner("Wait for the current run to finish first.")
            return
        }
        guard let conversation = selectedConversation else {
            showBanner("Open a Council conversation first.")
            return
        }

        let batchMessages = councilMessages(for: batchID)
        let modelIDs: [String]
        switch target {
        case .room:
            modelIDs = Self.councilBatchModelIDs(from: batchMessages, batchID: batchID)
        case let .model(id):
            modelIDs = [id]
        }
        guard !modelIDs.isEmpty else {
            showBanner("No Council model is available for this follow-up.")
            return
        }
        guard councilRoutesAreReady(modelIDs) else { return }

        let previousResponseID: String?
        let previousAnswer: String?
        switch target {
        case .room:
            previousResponseID = Self.latestCouncilResponseID(in: batchMessages)
            previousAnswer = nil
        case let .model(id):
            previousResponseID = Self.latestResponseID(in: batchMessages, modelID: id)
            previousAnswer = Self.latestAnswerText(in: batchMessages, modelID: id)
        }

        routeReadinessIssue = nil
        streamTask = Task { [weak self] in
            await self?.runCouncilRoomFollowUp(
                text: trimmed,
                target: target,
                conversation: conversation,
                modelIDs: modelIDs,
                previousResponseID: previousResponseID,
                previousAnswer: previousAnswer
            )
        }
    }

    func synthesizeCouncilBatch(batchID: String?) {
        guard let batchID else {
            showBanner("Open a Council batch first.")
            return
        }
        if isStreaming {
            stopWaitingForCouncil(batchID: batchID)
            return
        }
        guard let conversation = selectedConversation else {
            showBanner("Open a Council conversation first.")
            return
        }
        let batchMessages = councilMessages(for: batchID)
        let modelIDs = Self.councilBatchModelIDs(from: batchMessages, batchID: batchID)
        let successfulResults = Self.councilStreamResults(from: batchMessages, batchID: batchID)
        guard successfulResults.count > 1, !modelIDs.isEmpty else {
            showBanner("Need at least two completed Council answers to synthesize.")
            return
        }
        guard councilRoutesAreReady([successfulResults.first?.modelID ?? selectedModel]) else { return }

        let originalPrompt = Self.councilBatchPrompt(from: batchMessages) ?? "Synthesize this Council batch."
        routeReadinessIssue = nil
        streamTask = Task { [weak self] in
            guard let self else { return }
            self.isStreaming = true
            self.currentAssistantMessageID = nil
            self.currentCouncilAssistantMessageIDs = []
            let previousResponseID = Self.latestCouncilResponseID(in: batchMessages)
            defer {
                self.isStreaming = false
                self.currentAssistantMessageID = nil
                self.currentCouncilAssistantMessageIDs = []
                self.councilStopRequestedBatchID = nil
                self.streamTask = nil
            }
            await self.synthesizeCouncilTurn(
                prompt: originalPrompt,
                routedPrompt: originalPrompt,
                conversationID: conversation.id,
                previousResponseID: previousResponseID,
                batchID: batchID,
                modelIDs: modelIDs,
                successfulResults: successfulResults
            )
            self.saveLocalMessages(for: conversation.id)
            self.scheduleConversationListRefresh()
            self.showBanner("Council synthesis updated.")
        }
    }

    private func councilMessages(for batchID: String?) -> [ChatMessage] {
        guard let batchID, !batchID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return messages.filter { $0.councilBatchID == batchID }
    }

    private func councilRoutesAreReady(_ modelIDs: [String]) -> Bool {
        let needsNearCloud = modelIDs.contains { Self.routeKind(forModelID: $0) == .nearCloud }
        if needsNearCloud, !nearCloudKeyConfigured {
            showBanner("Connect NEAR AI Cloud in Account before asking that Council model.")
            return false
        }
        let needsHosted = modelIDs.contains { $0 == ModelOption.ironclawModelID }
        if needsHosted, !ironclawRemoteWorkstationAvailable {
            showBanner(hostedIronclawReadinessMessage ?? "Configure Hosted IronClaw before asking that Council model.")
            return false
        }
        return true
    }

    nonisolated static func councilBatchModelIDs(from messages: [ChatMessage], batchID: String?) -> [String] {
        CouncilStreamService.batchModelIDs(from: messages, batchID: batchID)
    }

    nonisolated static func councilBatchPrompt(from messages: [ChatMessage]) -> String? {
        CouncilStreamService.batchPrompt(from: messages)
    }

    nonisolated static func councilTargetedPrompt(
        text: String,
        modelDisplayName: String,
        previousAnswer: String? = nil
    ) -> String {
        CouncilStreamService.targetedPrompt(
            text: text,
            modelDisplayName: modelDisplayName,
            previousAnswer: previousAnswer
        )
    }

    private static func councilStreamResults(from messages: [ChatMessage], batchID: String) -> [CouncilStreamResult] {
        CouncilStreamService.streamResults(from: messages, batchID: batchID)
    }

    private static func latestCouncilResponseID(in messages: [ChatMessage]) -> String? {
        CouncilStreamService.latestCouncilResponseID(in: messages)
    }

    private static func latestResponseID(in messages: [ChatMessage], modelID: String) -> String? {
        CouncilStreamService.latestResponseID(in: messages, modelID: modelID)
    }

    private static func latestAnswerText(in messages: [ChatMessage], modelID: String) -> String? {
        CouncilStreamService.latestAnswerText(in: messages, modelID: modelID)
    }

    nonisolated static func isCouncilSynthesisModelID(_ modelID: String?) -> Bool {
        CouncilStreamService.isSynthesisModelID(modelID)
    }

    func copySignedSnippet(for message: ChatMessage) {
        guard message.role == .assistant,
              !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showBanner("No assistant answer to sign.")
            return
        }

        do {
            let snippetMessages = signedSnippetMessages(endingAt: message)
            let data = try ConversationExportBuilder.signedTranscriptData(
                conversation: selectedConversation,
                messages: snippetMessages,
                context: signedTranscriptExportContext
            )
            guard let json = String(data: data, encoding: .utf8) else {
                showBanner("Could not encode signed snippet.")
                return
            }
            Clipboard.copy(json)
            showBanner("Device-signed snippet copied. Verifies export integrity, not answer truth; device key ID may link repeated exports.")
        } catch {
            showBanner(Self.displayFailureMessage(error.localizedDescription))
        }
    }

    private func signedSnippetMessages(endingAt message: ChatMessage) -> [ChatMessage] {
        guard let messageIndex = messages.firstIndex(where: { $0.id == message.id }) else {
            return [message]
        }

        var snippet: [ChatMessage] = []
        if let userIndex = messages[..<messageIndex].lastIndex(where: { $0.role == .user }) {
            snippet.append(messages[userIndex])
        }
        snippet.append(message)
        return snippet
    }

    func regenerateResponse(for message: ChatMessage) {
        sendCoordinator.regenerateResponse(for: message)
    }

    func editAndResend(_ message: ChatMessage, replacementText: String) {
        sendCoordinator.editAndResend(message, replacementText: replacementText)
    }

    typealias PromptSourcePrivacyOverride = ChatPromptSourcePrivacyOverride

    nonisolated static func promptSourcePrivacyOverride(
        for prompt: String,
        hasAttachments: Bool = false
    ) -> PromptSourcePrivacyOverride {
        RoutePlanner.promptSourcePrivacyOverride(for: prompt, hasAttachments: hasAttachments)
    }

    private func send(
        _ text: String,
        attachments: [ChatAttachment],
        previousResponseIDOverride: String? = nil,
        initiator: String? = nil,
        appendUserMessage: Bool = true
    ) async -> Bool {
        await sendCoordinator.sendForBridge(
            text,
            attachments: attachments,
            previousResponseIDOverride: previousResponseIDOverride,
            initiator: initiator,
            appendUserMessage: appendUserMessage
        )
    }
}
