import Foundation

extension ChatStore {
    private func apply(streamEvent event: ResponseStreamEvent, conversationID: String) async {
        await apply(streamEvent: event, conversationID: conversationID, assistantMessageID: currentAssistantMessageID)
    }

    func apply(
        streamEvent event: ResponseStreamEvent,
        conversationID: String,
        assistantMessageID: String?
    ) async {
        messageTimelineStore.applyIfConversationMatches(
            selectedConversationID: selectedConversation?.id,
            streamEvent: event,
            conversationID: conversationID,
            assistantMessageID: assistantMessageID
        ) { [weak self] conversationID, title in
            self?.conversationStore.setTitle(title, for: conversationID)
        }
    }

    @discardableResult
    func updateMessage(_ messageID: String, mutate: (inout ChatMessage) -> Void) -> Bool {
        messageTimelineStore.updateMessage(messageID, mutate: mutate)
    }

    func finishAssistantMessage(_ messageID: String) {
        messageTimelineStore.finishAssistantMessage(messageID) { [weak self] message in
            self?.assistantTrustMetadata(
                for: message.model,
                webSearchUsed: !message.sources.isEmpty ? true : nil,
                capturedAt: message.createdAt
            )
        }
    }

    func flushPendingTextDelta(for messageID: String) {
        messageTimelineStore.flushPendingTextDelta(for: messageID)
    }

    func resolveIronclawApproval(
        messageID: String,
        approval: IronclawPendingGate,
        action: IronclawApprovalAction
    ) {
        guard !isStreaming else { return }
        streamTask = Task { [weak self] in
            await self?.resolveIronclawApprovalAction(messageID: messageID, approval: approval, action: action)
        }
    }

    func resolveIronclawCredential(
        messageID: String,
        approval: IronclawPendingGate,
        token: String
    ) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isStreaming, !trimmedToken.isEmpty else { return }
        streamTask = Task { [weak self] in
            await self?.resolveIronclawCredentialAction(messageID: messageID, approval: approval, token: trimmedToken)
        }
    }

    private func resolveIronclawApprovalAction(
        messageID: String,
        approval: IronclawPendingGate,
        action: IronclawApprovalAction
    ) async {
        guard let conversationID = selectedConversation?.id else { return }
        isStreaming = true
        currentAssistantMessageID = messageID
        defer {
            isStreaming = false
            currentAssistantMessageID = nil
            streamTask = nil
        }

        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let settings = ironclawSettingsForConversation(conversationID)

        messages[index].pendingApproval = nil
        messages[index].isStreaming = action != .deny
        messages[index].status = action == .deny ? "failed" : "reasoning"
        if action == .deny {
            messages[index].text = approval.isAuthenticationGate ?
                "Cancelled \(approval.authenticationDisplayName) authentication." :
                "Denied \(approval.toolName) approval."
        }
        saveLocalMessages(for: conversationID)

        do {
            try await ironclawAPI.resolveGate(
                settings: settings,
                authToken: loadIronclawAuthToken(),
                approval: approval,
                action: action
            )

            guard action != .deny else {
                showBanner(approval.isAuthenticationGate ? "IronClaw authentication cancelled." : "IronClaw approval denied.")
                saveLocalMessages(for: conversationID)
                return
            }

            await ironclawAPI.waitForThread(
                settings: settings,
                authToken: loadIronclawAuthToken(),
                threadID: approval.threadID,
                runID: approval.runID ?? ""
            ) { [weak self] event in
                await self?.apply(streamEvent: event, conversationID: conversationID)
            }

            guard selectedConversation?.id == conversationID else { return }
            if let resolvedIndex = messages.firstIndex(where: { $0.id == messageID }) {
                messages[resolvedIndex].isStreaming = false
                if messages[resolvedIndex].status != "failed", messages[resolvedIndex].status != "approval", messages[resolvedIndex].status != "gate_denied" {
                    messages[resolvedIndex].status = "completed"
                }
            }

            let threadID = approval.threadID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !threadID.isEmpty {
                let files = await ironclawAPI.fetchProjectFiles(
                    threadID: threadID,
                    settings: settings,
                    authToken: loadIronclawAuthToken()
                )
                if !files.isEmpty {
                    _ = updateMessage(messageID) { $0.projectFiles = files }
                }
            }

            saveLocalMessages(for: conversationID)
        } catch {
            let displayError = Self.displayFailureMessage(error.localizedDescription)
            if let errorIndex = messages.firstIndex(where: { $0.id == messageID }) {
                messages[errorIndex].isStreaming = false
                messages[errorIndex].status = "failed"
                if messages[errorIndex].text.isEmpty {
                    messages[errorIndex].text = displayError
                }
            }
            showBanner(displayError)
            saveLocalMessages(for: conversationID)
        }
    }

    private func resolveIronclawCredentialAction(
        messageID: String,
        approval: IronclawPendingGate,
        token: String
    ) async {
        guard let conversationID = selectedConversation?.id else { return }
        isStreaming = true
        currentAssistantMessageID = messageID
        defer {
            isStreaming = false
            currentAssistantMessageID = nil
            streamTask = nil
        }

        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let settings = ironclawSettingsForConversation(conversationID)

        messages[index].pendingApproval = nil
        messages[index].isStreaming = true
        messages[index].status = "reasoning"
        saveLocalMessages(for: conversationID)

        do {
            try await ironclawAPI.submitGateCredential(
                settings: settings,
                authToken: loadIronclawAuthToken(),
                approval: approval,
                token: token
            )

            await ironclawAPI.waitForThread(
                settings: settings,
                authToken: loadIronclawAuthToken(),
                threadID: approval.threadID,
                runID: approval.runID ?? ""
            ) { [weak self] event in
                await self?.apply(streamEvent: event, conversationID: conversationID)
            }

            guard selectedConversation?.id == conversationID else { return }
            if let resolvedIndex = messages.firstIndex(where: { $0.id == messageID }) {
                messages[resolvedIndex].isStreaming = false
                if messages[resolvedIndex].status != "failed", messages[resolvedIndex].status != "approval", messages[resolvedIndex].status != "gate_denied" {
                    messages[resolvedIndex].status = "completed"
                }
            }

            let credThreadID = approval.threadID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !credThreadID.isEmpty {
                let files = await ironclawAPI.fetchProjectFiles(
                    threadID: credThreadID,
                    settings: settings,
                    authToken: loadIronclawAuthToken()
                )
                if !files.isEmpty {
                    _ = updateMessage(messageID) { $0.projectFiles = files }
                }
            }

            saveLocalMessages(for: conversationID)
        } catch {
            let displayError = Self.displayFailureMessage(error.localizedDescription)
            if let errorIndex = messages.firstIndex(where: { $0.id == messageID }) {
                messages[errorIndex].pendingApproval = approval
                messages[errorIndex].isStreaming = false
                messages[errorIndex].status = "approval"
                if messages[errorIndex].text.isEmpty {
                    messages[errorIndex].text = displayError
                }
            }
            showBanner(displayError)
            saveLocalMessages(for: conversationID)
        }
    }

    func ironclawSettingsForConversation(_ conversationID: String) -> IronclawSettings {
        agentStore.ironclawSettings(for: conversationID)
    }

    func showBanner(_ message: String) {
        bannerMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if bannerMessage == message {
                bannerMessage = nil
            }
        }
    }
}
