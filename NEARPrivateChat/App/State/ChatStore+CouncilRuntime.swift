import Foundation

extension ChatStore {
    private enum CouncilLegWaitEvent {
        case finished
        case firstToken
        case noTokenTimeout
    }

    private func streamCouncilLegWithNoTokenTimeout(
        modelID: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        initiator: String,
        assistantMessageID: String
    ) async throws {
        let timeoutSeconds = Self.councilLegNoTokenTimeoutSeconds
        try await withThrowingTaskGroup(of: CouncilLegWaitEvent.self) { group in
            group.addTask { @MainActor [weak self] in
                guard let self else { throw CancellationError() }
                try await self.streamResponse(
                    model: modelID,
                    text: text,
                    attachments: attachments,
                    conversationID: conversationID,
                    previousResponseID: previousResponseID,
                    initiator: initiator,
                    assistantMessageID: assistantMessageID
                )
                return .finished
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { throw CancellationError() }
                let startedAt = Date()
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    if self.messages.first(where: { $0.id == assistantMessageID })?.firstTokenAt != nil {
                        return .firstToken
                    }
                    if Date().timeIntervalSince(startedAt) >= timeoutSeconds {
                        return .noTokenTimeout
                    }
                }
                throw CancellationError()
            }

            while let event = try await group.next() {
                switch event {
                case .finished:
                    group.cancelAll()
                    return
                case .firstToken:
                    continue
                case .noTokenTimeout:
                    group.cancelAll()
                    throw CouncilStreamService.NoTokenTimeoutError(seconds: Int(timeoutSeconds.rounded()))
                }
            }
        }
    }

    func sendCouncilTurn(
        text: String,
        routedText: String,
        attachments: [ChatAttachment],
        conversation: ConversationSummary,
        modelIDs: [String],
        previousResponseID: String?,
        initiator: String
    ) async throws {
        let batchID = "council-\(UUID().uuidString)"
        let userMessage = ChatMessage(
            id: "local-user-\(UUID().uuidString)",
            role: .user,
            text: text,
            model: selectedModel,
            createdAt: Date(),
            status: "completed",
            responseID: nil,
            previousResponseID: previousResponseID,
            councilBatchID: batchID,
            isStreaming: false,
            attachments: attachments,
            metadata: currentUserMessageMetadata
        )
        let assistantMessages = modelIDs.enumerated().map { offset, modelID in
            let createdAt = Date().addingTimeInterval(Double(offset) * 0.01)
            return ChatMessage(
                id: "local-council-\(offset)-\(UUID().uuidString)",
                role: .assistant,
                text: "",
                model: modelID,
                createdAt: createdAt,
                status: "streaming",
                responseID: nil,
                previousResponseID: previousResponseID,
                councilBatchID: batchID,
                isStreaming: true,
                trustMetadata: assistantTrustMetadata(for: modelID, capturedAt: createdAt)
            )
        }
        let assistantIDByModel = zip(modelIDs, assistantMessages.map(\.id)).reduce(into: [String: String]()) { mapping, pair in
            if mapping[pair.0] == nil {
                mapping[pair.0] = pair.1
            }
        }

        currentAssistantMessageID = nil
        currentCouncilAssistantMessageIDs = assistantMessages.map(\.id)
        messages.append(userMessage)
        messages.append(contentsOf: assistantMessages)
        showBanner("LLM Council running \(modelIDs.count) models.")

        let outcome = await withTaskGroup(of: CouncilStreamResult.self, returning: CouncilRunOutcome.self) { group in
            var pendingModelIDs = modelIDs

            func enqueueModel(_ modelID: String) {
                guard let assistantID = assistantIDByModel[modelID] else { return }
                group.addTask { @MainActor [weak self] in
                    guard let self else {
                        return CouncilStreamResult(
                            modelID: modelID,
                            messageID: assistantID,
                            didComplete: false,
                            failureSummary: "The app released the request before it completed.",
                            errorKind: .transportError
                        )
                    }

                    // A tripped route fails the leg instantly with the
                    // restriction copy, instead of spending another doomed
                    // stream attempt on the same route.
                    if !self.routeHealth.shouldAttempt(modelID: modelID),
                       let notice = self.routeHealth.restrictionNotice(for: Self.routeKind(forModelID: modelID)) {
                        await self.apply(
                            streamEvent: .failed(notice),
                            conversationID: conversation.id,
                            assistantMessageID: assistantID
                        )
                        return CouncilStreamResult(
                            modelID: modelID,
                            messageID: assistantID,
                            didComplete: false,
                            failureSummary: notice,
                            errorKind: CouncilStreamService.errorKind(forFailureSummary: notice)
                        )
                    }

                    // A council leg gets one retry on a transient failure
                    // (rate limit / transport / no-token timeout). Two concurrent
                    // web-grounded streams on a starter plan routinely trip a
                    // transient 429 on one leg; re-attempting after a short backoff
                    // recovers it instead of surfacing "N failed" to the user.
                    var attempt = 0
                    while true {
                        do {
                            try Task.checkCancellation()
                            try await self.streamCouncilLegWithNoTokenTimeout(
                                modelID: modelID,
                                text: routedText,
                                attachments: attachments,
                                conversationID: conversation.id,
                                previousResponseID: previousResponseID,
                                initiator: initiator,
                                assistantMessageID: assistantID
                            )
                            self.finishAssistantMessage(assistantID)
                            self.routeHealth.recordSuccess(modelID: modelID)
                            return CouncilStreamResult(
                                modelID: modelID,
                                messageID: assistantID,
                                didComplete: true,
                                failureSummary: nil
                            )
                        } catch is CancellationError {
                            await self.apply(
                                streamEvent: .failed("Cancelled."),
                                conversationID: conversation.id,
                                assistantMessageID: assistantID
                            )
                            return CouncilStreamResult(
                                modelID: modelID,
                                messageID: assistantID,
                                didComplete: false,
                                failureSummary: "cancelled"
                            )
                        } catch {
                            let errorKind = CouncilStreamService.errorKind(for: error)
                            let isTransient = errorKind == .rateLimit
                                || errorKind == .transportError
                                || errorKind == .timeout
                            if attempt < Self.maxCouncilLegRetries,
                               isTransient,
                               !Task.isCancelled {
                                attempt += 1
                                self.resetCouncilLegForRetry(assistantMessageID: assistantID)
                                try? await Task.sleep(
                                    nanoseconds: UInt64(attempt) * 1_500_000_000
                                )
                                continue
                            }
                            self.routeHealth.recordFailure(modelID: modelID, error: error)
                            let summary = Self.modelFailureSummary(error)
                            await self.apply(
                                streamEvent: .failed(summary),
                                conversationID: conversation.id,
                                assistantMessageID: assistantID
                            )
                            return CouncilStreamResult(
                                modelID: modelID,
                                messageID: assistantID,
                                didComplete: false,
                                failureSummary: summary,
                                errorKind: errorKind
                            )
                        }
                    }
                }
            }

            let initialTaskCount = min(Self.maxConcurrentCouncilStreams, pendingModelIDs.count)
            for _ in 0..<initialTaskCount {
                enqueueModel(pendingModelIDs.removeFirst())
            }

            group.addTask { @MainActor [weak self] in
                await self?.waitForCouncilStopSignal(batchID: batchID) ?? .stopSignal(batchID: batchID)
            }

            var collected: [CouncilStreamResult] = []
            var stoppedEarly = false
            while collected.count < modelIDs.count, let result = await group.next() {
                if result.isStopSignal {
                    stoppedEarly = true
                    group.cancelAll()
                    continue
                }
                collected.append(result)
                if !stoppedEarly, !pendingModelIDs.isEmpty {
                    enqueueModel(pendingModelIDs.removeFirst())
                }
            }
            group.cancelAll()
            return CouncilRunOutcome(results: collected, stoppedEarly: stoppedEarly)
        }

        try Task.checkCancellation()
        let results = outcome.results
        let successfulResults = results.filter { result in
            result.didComplete &&
                (messages.first(where: { $0.id == result.messageID })?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        }
        if successfulResults.count > 1 {
            await synthesizeCouncilTurn(
                prompt: text,
                routedPrompt: routedText,
                conversationID: conversation.id,
                previousResponseID: previousResponseID,
                batchID: batchID,
                modelIDs: modelIDs,
                successfulResults: successfulResults
            )
        }

        let failureCount = results.filter { !$0.didComplete }.count
        if outcome.stoppedEarly, successfulResults.count > 1 {
            showBanner("Council stopped waiting and synthesized \(successfulResults.count) answers.")
        } else if outcome.stoppedEarly, successfulResults.count == 1 {
            showBanner("Council stopped waiting with one usable answer.")
        } else if successfulResults.isEmpty {
            showBanner("No council model returned a usable answer.")
        } else if failureCount > 0 {
            showBanner("Council finished: \(successfulResults.count) answered, \(failureCount) failed.")
        } else {
            showBanner("Council finished with \(successfulResults.count) answers.")
        }
        // Council member + synthesis turns exist only locally (the server's
        // /items feed never returns them), so persist or they vanish on re-open.
        saveLocalMessages(for: conversation.id)
        scheduleConversationListRefresh()
    }

    /// Clears a single council leg's partial output back to a clean streaming
    /// state before a retry, so the re-attempt fills an empty message instead of
    /// appending to a half-streamed or failed one.
    private func resetCouncilLegForRetry(assistantMessageID: String) {
        guard let index = messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            return
        }
        flushPendingTextDelta(for: assistantMessageID)
        messages[index].text = ""
        messages[index].status = "streaming"
        messages[index].responseID = nil
        messages[index].isStreaming = true
        messages[index].searchQuery = nil
        messages[index].sources = []
        messages[index].pendingApproval = nil
    }

    func runCouncilRoomFollowUp(
        text: String,
        target: CouncilTarget,
        conversation: ConversationSummary,
        modelIDs: [String],
        previousResponseID: String?,
        previousAnswer: String?
    ) async {
        isStreaming = true
        currentAssistantMessageID = nil
        currentCouncilAssistantMessageIDs = []
        defer {
            isStreaming = false
            currentAssistantMessageID = nil
            currentCouncilAssistantMessageIDs = []
            councilStopRequestedBatchID = nil
            streamTask = nil
        }

        do {
            switch target {
            case .room:
                try await sendCouncilTurn(
                    text: text,
                    routedText: text,
                    attachments: [],
                    conversation: conversation,
                    modelIDs: modelIDs,
                    previousResponseID: previousResponseID,
                    initiator: "council_room_followup"
                )
            case let .model(id):
                try await sendTargetedCouncilFollowUp(
                    text: text,
                    modelID: id,
                    conversation: conversation,
                    previousResponseID: previousResponseID,
                    previousAnswer: previousAnswer
                )
            }
            saveLocalMessages(for: conversation.id)
            scheduleConversationListRefresh()
        } catch is CancellationError {
            cancelStream()
        } catch {
            showBanner(Self.displayFailureMessage(error.localizedDescription))
        }
    }

    private func sendTargetedCouncilFollowUp(
        text: String,
        modelID: String,
        conversation: ConversationSummary,
        previousResponseID: String?,
        previousAnswer: String?
    ) async throws {
        let batchID = "council-target-\(UUID().uuidString)"
        let modelName = modelDisplayName(for: modelID)
        let userMessage = ChatMessage(
            id: "local-user-\(UUID().uuidString)",
            role: .user,
            text: "To \(modelName): \(text)",
            model: modelID,
            createdAt: Date(),
            status: "completed",
            responseID: nil,
            previousResponseID: previousResponseID,
            councilBatchID: batchID,
            isStreaming: false,
            metadata: currentUserMessageMetadata
        )
        let assistantID = "local-council-target-\(UUID().uuidString)"
        let assistantCreatedAt = Date().addingTimeInterval(0.01)
        let assistantMessage = ChatMessage(
            id: assistantID,
            role: .assistant,
            text: "",
            model: modelID,
            createdAt: assistantCreatedAt,
            status: "streaming",
            responseID: nil,
            previousResponseID: previousResponseID,
            councilBatchID: batchID,
            isStreaming: true,
            trustMetadata: assistantTrustMetadata(for: modelID, capturedAt: assistantCreatedAt)
        )
        messages.append(userMessage)
        messages.append(assistantMessage)
        currentCouncilAssistantMessageIDs = [assistantID]
        showBanner("Asking \(modelName).")

        do {
            try await streamCouncilLegWithNoTokenTimeout(
                modelID: modelID,
                text: Self.councilTargetedPrompt(
                    text: text,
                    modelDisplayName: modelName,
                    previousAnswer: previousAnswer
                ),
                attachments: [],
                conversationID: conversation.id,
                previousResponseID: previousResponseID,
                initiator: "council_room_targeted_followup",
                assistantMessageID: assistantID
            )
            finishAssistantMessage(assistantID)
            showBanner("\(modelName) answered.")
        } catch {
            await apply(
                streamEvent: .failed(Self.modelFailureSummary(error)),
                conversationID: conversation.id,
                assistantMessageID: assistantID
            )
            throw error
        }
    }

    func retryCouncilMember(
        messageID: String,
        modelID: String,
        prompt: String,
        attachments: [ChatAttachment],
        conversation: ConversationSummary,
        previousResponseID: String?
    ) async {
        isStreaming = true
        currentAssistantMessageID = nil
        currentCouncilAssistantMessageIDs = [messageID]
        councilStopRequestedBatchID = nil
        let modelName = modelDisplayName(for: modelID)
        updateMessage(messageID) { message in
            message.text = ""
            message.status = "streaming"
            message.isStreaming = true
            message.responseID = nil
            message.firstTokenAt = nil
            message.sources = []
            message.searchQuery = nil
            message.pendingApproval = nil
            message.trustMetadata = assistantTrustMetadata(for: modelID, capturedAt: Date())
        }
        showBanner("Retrying \(modelName).")
        defer {
            isStreaming = false
            currentAssistantMessageID = nil
            currentCouncilAssistantMessageIDs = []
            councilStopRequestedBatchID = nil
            streamTask = nil
            saveLocalMessages(for: conversation.id)
            scheduleConversationListRefresh()
        }

        do {
            let apiAttachments = attachments.filter { !$0.isLocalOnly }
            if !apiAttachments.isEmpty {
                await ensureDocumentTextsForSend(attachments: apiAttachments)
            }
            let routedPrompt = documentAugmentedPromptForSend(prompt, question: prompt, attachments: apiAttachments)
            try await streamCouncilLegWithNoTokenTimeout(
                modelID: modelID,
                text: routedPrompt,
                attachments: apiAttachments,
                conversationID: conversation.id,
                previousResponseID: previousResponseID,
                initiator: "council_member_retry",
                assistantMessageID: messageID
            )
            finishAssistantMessage(messageID)
            showBanner("\(modelName) answered.")
        } catch is CancellationError {
            cancelStream()
        } catch {
            await apply(
                streamEvent: .failed(Self.modelFailureSummary(error)),
                conversationID: conversation.id,
                assistantMessageID: messageID
            )
            showBanner(Self.displayFailureMessage(error.localizedDescription))
        }
    }

    private func waitForCouncilStopSignal(batchID: String) async -> CouncilStreamResult {
        while !Task.isCancelled {
            if councilStopRequestedBatchID == batchID {
                return .stopSignal(batchID: batchID)
            }
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                break
            }
        }
        return .stopSignal(batchID: batchID)
    }

    func synthesizeCouncilTurn(
        prompt: String,
        routedPrompt: String,
        conversationID: String,
        previousResponseID: String?,
        batchID: String?,
        modelIDs: [String],
        successfulResults: [CouncilStreamResult]
    ) async {
        let resultByModel = successfulResults.reduce(into: [String: CouncilStreamResult]()) { mapping, result in
            if mapping[result.modelID] == nil {
                mapping[result.modelID] = result
            }
        }
        let responses = modelIDs.compactMap { modelID -> (String, String)? in
            guard let result = resultByModel[modelID],
                  let message = messages.first(where: { $0.id == result.messageID }),
                  !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return (modelDisplayName(for: modelID), message.text)
        }
        let councilSources = Self.uniqueSources(successfulResults.flatMap { result -> [WebSearchSource] in
            messages.first(where: { $0.id == result.messageID })?.sources ?? []
        })
        guard responses.count > 1 else { return }

        removeFailedCouncilSynthesisMessages(batchID: batchID)
        let synthesisID = "local-council-synthesis-\(UUID().uuidString)"
        let synthesisCreatedAt = Date().addingTimeInterval(0.2)
        let synthesisMessage = ChatMessage(
            id: synthesisID,
            role: .assistant,
            text: "",
            model: ModelOption.llmCouncilSynthesisModelID,
            createdAt: synthesisCreatedAt,
            status: "streaming",
            responseID: nil,
            previousResponseID: previousResponseID,
            councilBatchID: batchID,
            isStreaming: true,
            searchQuery: prompt,
            sources: councilSources,
            trustMetadata: assistantTrustMetadata(
                for: ModelOption.llmCouncilSynthesisModelID,
                webSearchUsed: !councilSources.isEmpty,
                capturedAt: synthesisCreatedAt
            )
        )
        currentCouncilAssistantMessageIDs.append(synthesisID)
        messages.append(synthesisMessage)

        let synthesisModelID = successfulResults.first(where: { routeHealth.shouldAttempt(modelID: $0.modelID) })?.modelID
            ?? preferredAvailableModel(excluding: Set<String>()).flatMap { routeHealth.shouldAttempt(modelID: $0) ? $0 : nil }
        guard let synthesisModelID else {
            let notice = routeHealth.restrictionNotice(for: .nearPrivate)
                ?? "No healthy model route is available right now."
            await apply(
                streamEvent: .failed("\(notice) Tap \"Synthesize again\" to retry."),
                conversationID: conversationID,
                assistantMessageID: synthesisID
            )
            return
        }
        let synthesisPrompt = CouncilStreamService.synthesisPrompt(
            originalPrompt: prompt,
            routedPrompt: routedPrompt,
            responses: responses
        )
        var attemptsRemaining = 2
        while attemptsRemaining > 0 {
            attemptsRemaining -= 1
            do {
                try await streamResponse(
                    model: synthesisModelID,
                    text: synthesisPrompt,
                    attachments: [],
                    conversationID: conversationID,
                    previousResponseID: previousResponseID,
                    initiator: "llm_council_synthesis",
                    assistantMessageID: synthesisID
                )
                finishAssistantMessage(synthesisID)
                return
            } catch {
                if attemptsRemaining > 0, Self.isTransientTransportError(error), !Task.isCancelled {
                    updateMessage(synthesisID) { message in
                        message.text = ""
                        message.status = "streaming"
                        message.isStreaming = true
                    }
                    try? await Task.sleep(nanoseconds: Self.synthesisRetryDelayNanoseconds)
                    continue
                }
                await apply(
                    streamEvent: .failed("\(Self.modelFailureSummary(error)) Tap \"Synthesize again\" to retry."),
                    conversationID: conversationID,
                    assistantMessageID: synthesisID
                )
                return
            }
        }
    }

    private func removeFailedCouncilSynthesisMessages(batchID: String?) {
        guard let batchID else { return }
        let removableIDs = Set(messages.compactMap { message -> String? in
            guard message.councilBatchID == batchID,
                  Self.isCouncilSynthesisModelID(message.model),
                  message.status.lowercased() == "failed" else {
                return nil
            }
            return message.id
        })
        guard !removableIDs.isEmpty else { return }
        messages.removeAll { removableIDs.contains($0.id) }
        currentCouncilAssistantMessageIDs.removeAll { removableIDs.contains($0) }
    }

    /// Mutable for tests/harness: the pause before the single synthesis retry.
    nonisolated(unsafe) static var synthesisRetryDelayNanoseconds: UInt64 = 1_500_000_000

    private static func isTransientTransportError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [.networkConnectionLost, .timedOut, .cannotConnectToHost, .networkConnectionLost].contains(urlError.code)
        }
        if case let APIError.status(code, message) = error {
            if [408, 502, 503, 504].contains(code) { return true }
            return message.lowercased().contains("response stream ended early")
        }
        return false
    }
}
