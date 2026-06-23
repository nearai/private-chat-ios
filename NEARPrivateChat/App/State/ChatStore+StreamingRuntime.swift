import Foundation

extension ChatStore {
    /// Lightweight, no-token probe of the private session: hits `/v1/users/me`
    /// with the stored session token. Succeeds only when the private route truly
    /// accepts the session, so a wallet login that returns a non-session token
    /// surfaces here (401/403) instead of being discovered on the first chat.
    /// Records the real outcome into `diagnostics`.
    @discardableResult
    func probePrivateSession() async -> ConnectionDiagnostics.Outcome? {
        guard !isProbingSession else { return diagnostics.lastPrivateOutcome }
        isProbingSession = true
        defer { isProbingSession = false }
        do {
            _ = try await api.fetchProfile()
            diagnostics.recordSuccess(route: .nearPrivate, modelID: "session-probe")
        } catch {
            diagnostics.record(route: .nearPrivate, modelID: "session-probe", error: error)
        }
        return diagnostics.lastPrivateOutcome
    }

    func streamResponseWithFallback(
        initialModel: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        initiator: String
    ) async throws -> String {
        var currentModel = initialModel
        var unavailableModels = Set<String>()
        var fallbackHops = 0
        var transientPrivateRouteRetries = 0

        if !routeHealth.shouldAttempt(modelID: initialModel),
           let notice = routeHealth.restrictionNotice(for: Self.routeKind(forModelID: initialModel)) {
            throw RouteHealthError.routeRestricted(notice)
        }

        while true {
            do {
                try await streamResponse(
                    model: currentModel,
                    text: text,
                    attachments: attachments,
                    conversationID: conversationID,
                    previousResponseID: previousResponseID,
                    initiator: initiator,
                    assistantMessageID: currentAssistantMessageID
                )
                routeHealth.recordSuccess(modelID: currentModel)
                diagnostics.recordSuccess(route: Self.routeKind(forModelID: currentModel), modelID: currentModel)
                return currentModel
            } catch {
                let currentRoute = Self.routeKind(forModelID: currentModel)
                if currentRoute == .nearPrivate,
                   transientPrivateRouteRetries < 1,
                   Self.shouldRetryPrivateRouteOnce(error) {
                    transientPrivateRouteRetries += 1
                    resetCurrentAssistantForRetry()
                    showBanner(Self.privateRouteRetryMessage(for: error))
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: Self.transientPrivateRouteRetryDelayNanoseconds)
                    continue
                }

                routeHealth.recordFailure(modelID: currentModel, error: error)
                diagnostics.record(route: currentRoute, modelID: currentModel, error: error)
                unavailableModels.insert(currentModel)
                // One fallback hop max: walking the whole catalog against a
                // restricted route amplified the very rate limit it hit.
                guard !Self.isExternalModel(currentModel),
                      Self.isRecoverableModelError(error),
                      fallbackHops < 1,
                      !routeHealth.isTripped(currentRoute),
                      let fallbackModel = preferredAvailableModel(excluding: unavailableModels),
                      fallbackModel != currentModel else {
                    throw error
                }

                fallbackHops += 1
                selectedModel = fallbackModel
                updateCurrentExchange(to: fallbackModel)
                showBanner("\(modelDisplayName(for: currentModel)) stalled. Retrying with \(modelDisplayName(for: fallbackModel)).")
                currentModel = fallbackModel
            }
        }
    }

    nonisolated static let transientPrivateRouteRetryDelayNanoseconds: UInt64 = 750_000_000

    nonisolated static func shouldRetryPrivateRouteOnce(_ error: Error) -> Bool {
        RouteHealthMonitor.isTransientBusyFailure(error) ||
            RouteHealthMonitor.isTransientPrivateTransportFailure(error)
    }

    nonisolated static func privateRouteRetryMessage(for error: Error) -> String {
        RouteHealthMonitor.isTransientPrivateTransportFailure(error)
            ? "Private backend did not answer. Retrying once privately."
            : "Private route is busy. Retrying once privately."
    }

    func streamResponse(
        model: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        initiator: String = "new_message",
        assistantMessageID: String? = nil
    ) async throws {
        if model == ModelOption.ironclawMobileModelID {
            try await streamIronclawMobileRuntime(
                text: text,
                attachments: attachments,
                conversationID: conversationID,
                previousResponseID: previousResponseID,
                assistantMessageID: assistantMessageID
            )
            return
        }

        if Self.routeKind(forModelID: model) == .nearCloud {
            let webContext = try await appWebGroundingContextIfNeeded(
                model: model,
                text: text,
                conversationID: conversationID,
                assistantMessageID: assistantMessageID
            )
            try await streamNearCloudModel(
                modelID: model,
                text: text,
                attachments: attachments,
                conversationID: conversationID,
                webContext: webContext,
                assistantMessageID: assistantMessageID
            )
            return
        }

        if model == ModelOption.ironclawModelID {
            let settings = ironclawSettingsForConversation(conversationID)
            guard settings.isEnabled, settings.hasUsableHostedEndpoint else {
                let message = settings.hasUsableHostedEndpoint
                    ? "Turn on Hosted IronClaw in Account before sending."
                    : settings.endpointValidationMessage ?? "Add a Hosted IronClaw URL first."
                throw APIError.status(0, message)
            }
            let webContext = try await appWebGroundingContextIfNeeded(
                model: model,
                text: text,
                conversationID: conversationID,
                assistantMessageID: assistantMessageID
            )
            let documentAttachments = attachments.filter { !$0.isLocalOnly }
            await attachmentStagingStore.ensureDocumentTextsAvailable(for: documentAttachments, using: fileService)
            let hostedAttachmentPayloads = await hostedIronclawAttachmentPayloads(for: documentAttachments)
            var resolvedHostedThreadID: String?
            try await ironclawAPI.streamPrompt(
                prompt: ironclawPrompt(for: text, attachments: attachments, webContext: webContext),
                attachments: attachments,
                attachmentPayloads: hostedAttachmentPayloads,
                settings: settings,
                authToken: loadIronclawAuthToken(),
                onResolvedThreadID: { [weak self] threadID in
                    resolvedHostedThreadID = threadID
                    self?.agentStore.rememberIronclawThreadID(threadID, for: conversationID)
                }
            ) { [weak self] event in
                await self?.apply(streamEvent: event, conversationID: conversationID, assistantMessageID: assistantMessageID)
            }
            if let threadID = resolvedHostedThreadID, let msgID = assistantMessageID {
                let files = await ironclawAPI.fetchProjectFiles(
                    threadID: threadID,
                    settings: settings,
                    authToken: loadIronclawAuthToken()
                )
                if !files.isEmpty {
                    _ = updateMessage(msgID) { $0.projectFiles = files }
                }
            }
            return
        }

        let webContext = try await appWebGroundingContextIfNeeded(
            model: model,
            text: text,
            conversationID: conversationID,
            assistantMessageID: assistantMessageID
        )

        try await api.streamResponse(
            model: model,
            text: privateRoutePrompt(for: text, webContext: webContext),
            attachments: attachments,
            conversationID: conversationID,
            previousResponseID: previousResponseID,
            webSearchEnabled: shouldEnableModelNativeWebTool(model: model, prompt: text, appWebContext: webContext),
            systemPrompt: activeSystemPrompt(memoryForModel: model),
            advancedParams: advancedModelParams,
            initiator: initiator,
            visibleOutputTimeout: visibleOutputTimeout(for: model)
        ) { [weak self] event in
            await self?.apply(streamEvent: event, conversationID: conversationID, assistantMessageID: assistantMessageID)
        }
    }

    /// Non-streaming Cloud completion for headless briefing runs and proxy
    /// follow-ups. Mirrors `streamNearCloudModel`'s routing but returns the text
    /// instead of applying stream events, so `streamBriefingTextResult` can use
    /// it for cloud/proxy model IDs that the private streamer can't serve.
    func cloudBriefingText(
        modelID: String,
        prompt: String,
        webSearchEnabled: Bool,
        attachments: [ChatAttachment] = []
    ) async throws -> String {
        guard let apiKey = loadNearCloudAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw APIError.status(401, "Connect NEAR AI Cloud in Account to use \(modelDisplayName(for: modelID)).")
        }
        guard let cloudModelID = nearCloudUnderlyingModelID(for: modelID) else {
            throw APIError.status(400, "That NEAR AI Cloud model route is not valid.")
        }
        // Headless app web grounding mirrors the live NEAR Cloud path. It is
        // best-effort: a failed search degrades to the no-web prompt instead of
        // failing the run.
        var webContext: WebGroundingContext?
        if webSearchEnabled,
           let groundingPrompt = WebGroundingService.searchPrompt(for: prompt, priorUserTexts: []) {
            let searchMode = WebGroundingService.searchMode(for: groundingPrompt)
            webContext = try? await webGroundingService.search(
                for: groundingPrompt,
                preferNews: searchMode.prefersNews(
                    researchModeEnabled: false,
                    needsLiveWeb: Self.promptNeedsLiveWeb(groundingPrompt)
                )
            )
        }
        let documentAttachments = attachments.filter { !$0.isLocalOnly }
        await attachmentStagingStore.ensureDocumentTextsAvailable(for: documentAttachments, using: fileService)
        let finalPrompt = attachmentStagingStore.documentAugmentedPrompt(
            ChatPromptContextBuilder.cloudBriefingPrompt(prompt: prompt, webContext: webContext),
            question: prompt,
            attachments: documentAttachments
        )
        let response = try await api.fetchNearCloudChatCompletion(
            apiKey: apiKey,
            model: cloudModelID,
            prompt: finalPrompt,
            systemPrompt: nearCloudSystemPrompt(
                modelID: modelID,
                modelDisplayName: modelDisplayName(for: modelID),
                hasWebContext: webContext != nil
            ),
            advancedParams: advancedModelParams
        )
        return Self.cleanedNearCloudResponse(response)
    }

    private func streamNearCloudModel(
        modelID: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        webContext: WebGroundingContext?,
        assistantMessageID: String? = nil
    ) async throws {
        guard let apiKey = loadNearCloudAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw APIError.status(401, "Connect NEAR AI Cloud in Account to use \(modelDisplayName(for: modelID)).")
        }
        guard let cloudModelID = nearCloudUnderlyingModelID(for: modelID) else {
            throw APIError.status(400, "That NEAR AI Cloud model route is not valid.")
        }

        await apply(streamEvent: .reasoningStarted, conversationID: conversationID, assistantMessageID: assistantMessageID)
        let documentAttachments = attachments.filter { !$0.isLocalOnly }
        await attachmentStagingStore.ensureDocumentTextsAvailable(for: documentAttachments, using: fileService)
        let prompt = attachmentStagingStore.documentAugmentedPrompt(
            nearCloudPrompt(for: text, attachments: attachments, webContext: webContext),
            question: text,
            attachments: documentAttachments
        )
        let response = try await api.fetchNearCloudChatCompletion(
            apiKey: apiKey,
            model: cloudModelID,
            prompt: prompt,
            systemPrompt: nearCloudSystemPrompt(modelID: modelID, modelDisplayName: modelDisplayName(for: modelID), hasWebContext: webContext != nil),
            advancedParams: advancedModelParams
        )
        await apply(streamEvent: .textDelta(Self.cleanedNearCloudResponse(response)), conversationID: conversationID, assistantMessageID: assistantMessageID)
        await apply(streamEvent: .completed(responseID: nil), conversationID: conversationID, assistantMessageID: assistantMessageID)
    }

    private func streamIronclawMobileRuntime(
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        assistantMessageID: String? = nil
    ) async throws {
        let promptAttachments = promptOnlyAttachments(from: attachments)
        let initialSnapshot = mobileWorkspaceSnapshot(
            conversationID: conversationID,
            promptAttachments: promptAttachments
        )
        let actionPlan = IronclawMobilePlanner.plan(prompt: text, snapshot: initialSnapshot)
        let toolResults = await executeIronclawMobileToolCalls(
            actionPlan.calls,
            conversationID: conversationID,
            promptAttachments: promptAttachments
        )
        if !toolResults.isEmpty {
            await apply(
                streamEvent: .textDelta(AgentStore.ironclawToolResultMarkdown(toolResults)),
                conversationID: conversationID,
                assistantMessageID: assistantMessageID
            )
        }

        if Self.promptNeedsRemoteWorkstation(text), ironclawRemoteWorkstationAvailable {
            updateCurrentExchange(to: ModelOption.ironclawModelID, shouldClearText: false)
            selectedModel = ModelOption.ironclawModelID
            let handoffMessage = """
            **Hosted IronClaw handoff**
            This needs hosted git/code/shell/research tools, so I am running it through Hosted IronClaw. Local iOS project actions above stay attached to this run.

            """
            await apply(streamEvent: .textDelta(handoffMessage), conversationID: conversationID, assistantMessageID: assistantMessageID)
            showBanner("IronClaw Mobile handed this to Hosted IronClaw.")
            do {
                try await streamResponse(
                    model: ModelOption.ironclawModelID,
                    text: text,
                    attachments: attachments,
                    conversationID: conversationID,
                    previousResponseID: nil,
                    assistantMessageID: assistantMessageID
                )
                return
            } catch {
                await apply(
                    streamEvent: .textDelta("\n\nHosted IronClaw failed: \(Self.displayFailureMessage(error.localizedDescription))"),
                    conversationID: conversationID,
                    assistantMessageID: assistantMessageID
                )
                throw error
            }
        }

        let webContext = try await appWebGroundingContextIfNeeded(
            model: ModelOption.ironclawMobileModelID,
            text: text,
            conversationID: conversationID,
            assistantMessageID: assistantMessageID
        )
        let documentAttachments = attachments.filter { !$0.isLocalOnly }
        await attachmentStagingStore.ensureDocumentTextsAvailable(for: documentAttachments, using: fileService)
        let mobileModelPrompt = attachmentStagingStore.documentAugmentedPrompt(
            AgentStore.normalizedIronclawPrompt(text),
            question: text,
            attachments: documentAttachments
        )
        var unavailableModels = Set<String>()
        var modelFailures: [String: String] = [:]

        while let baseModel = preferredIronclawBaseModel(excluding: unavailableModels) {
            // The agent's base models ride the private route; a tripped breaker
            // fails fast instead of walking every open-weight model.
            guard routeHealth.shouldAttempt(modelID: baseModel) else {
                let notice = routeHealth.restrictionNotice(for: Self.routeKind(forModelID: baseModel))
                    ?? "Private route is rate-limited for this session. Wait for the cooldown, or use the privacy proxy only for this turn. If it keeps failing after cooldown, sign out and back in."
                throw APIError.status(403, notice)
            }
            do {
                try await ironclawMobileRuntime.streamTurn(
                    prompt: mobileModelPrompt,
                    attachments: attachments,
                    context: mobileProjectContext(promptAttachments: attachments),
                    baseModel: baseModel,
                    conversationID: conversationID,
                    previousResponseID: previousResponseID,
                    webSearchEnabled: shouldEnableModelNativeWebTool(
                        model: ModelOption.ironclawMobileModelID,
                        prompt: text,
                        appWebContext: webContext
                    ),
                    systemPrompt: activeSystemPrompt(memoryForModel: ModelOption.ironclawMobileModelID),
                    toolResults: toolResults,
                    webContext: webContext
                ) { [weak self] event in
                    await self?.apply(streamEvent: event, conversationID: conversationID, assistantMessageID: assistantMessageID)
                }
                return
            } catch {
                routeHealth.recordFailure(modelID: baseModel, error: error)
                unavailableModels.insert(baseModel)
                modelFailures[baseModel] = Self.modelFailureSummary(error)
                if Self.isModelPlanError(error) {
                    deniedOpenWeightModelIDs.insert(baseModel)
                }
                guard Self.isRecoverableModelError(error), !routeHealth.isTripped(Self.routeKind(forModelID: baseModel)) else {
                    throw error
                }
                guard preferredIronclawBaseModel(excluding: unavailableModels) != nil else {
                    let failureMessage = Self.openWeightFailureMessage(
                        modelFailures: modelFailures,
                        modelName: { [weak self] in self?.modelDisplayName(for: $0) ?? $0 }
                    )
                    if !toolResults.isEmpty {
                        await apply(
                            streamEvent: .textDelta("\n\nThe local iPhone actions completed, but \(failureMessage)"),
                            conversationID: conversationID,
                            assistantMessageID: assistantMessageID
                        )
                        return
                    }
                    throw APIError.status(403, failureMessage)
                }

                resetCurrentAssistantForRetry(preserving: AgentStore.ironclawToolResultMarkdown(toolResults))
                showBanner("IronClaw skipped \(modelDisplayName(for: baseModel)): \(Self.modelFailureSummary(error))")
            }
        }

        throw APIError.status(503, "IronClaw Mobile could not find an available open-weight NEAR Private model.")
    }

    private func appWebGroundingContextIfNeeded(
        model: String,
        text: String,
        conversationID: String,
        assistantMessageID: String? = nil
    ) async throws -> WebGroundingContext? {
        let currentGroundingPrompt = Self.webGroundingPrompt(from: text)
        guard let groundingPrompt = WebGroundingService.searchPrompt(
            for: currentGroundingPrompt,
            priorUserTexts: priorUserGroundingPrompts(excludingCurrentText: text)
        ) else {
            return nil
        }
        guard shouldUseAppWebGrounding(model: model, prompt: groundingPrompt) else {
            return nil
        }

        let query = WebGroundingService.query(from: groundingPrompt)
        await apply(streamEvent: .webSearchStarted(query: query), conversationID: conversationID, assistantMessageID: assistantMessageID)
        do {
            let searchMode = WebGroundingService.searchMode(for: groundingPrompt)
            let context = try await webGroundingService.search(
                for: groundingPrompt,
                preferNews: searchMode.prefersNews(
                    researchModeEnabled: researchModeEnabled,
                    needsLiveWeb: Self.promptNeedsLiveWeb(groundingPrompt)
                )
            )
            await apply(
                streamEvent: .webSearchCompleted(query: context.query, sources: context.sources),
                conversationID: conversationID,
                assistantMessageID: assistantMessageID
            )
            return context
        } catch {
            await apply(streamEvent: .webSearchCompleted(query: query, sources: []), conversationID: conversationID, assistantMessageID: assistantMessageID)
            throw APIError.status(0, "Web search failed before the model call: \(error.localizedDescription)")
        }
    }

    /// Prior prompts eligible to substitute for a low-signal follow-up's web
    /// query. Restricted to turns the user sent on non-private routes: a prompt
    /// deliberately asked on the private route must never be shipped to
    /// device-side search engines because a later "try again" needed a query.
    /// Messages without a recorded model are excluded for the same reason.
    private func priorUserGroundingPrompts(excludingCurrentText text: String) -> [String] {
        var userTexts = messages.compactMap { message -> String? in
            guard message.role == .user,
                  let model = message.model,
                  Self.routeKind(forModelID: model) != .nearPrivate else { return nil }
            return message.text
        }
        if userTexts.last == text {
            userTexts.removeLast()
        }
        return userTexts.map(Self.webGroundingPrompt(from:))
    }

    private static func webGroundingPrompt(from text: String) -> String {
        if let brief = AgentStore.agentMissionBrief(from: text) {
            return brief
        }
        return AgentStore.strippedAgentLaunchPrefix(from: text)
    }

    func shouldEnableModelNativeWebTool(
        model: String,
        prompt: String,
        appWebContext: WebGroundingContext? = nil
    ) -> Bool {
        let privacyBlocksWeb = Self.promptSourcePrivacyOverride(for: prompt).blocksWeb
        let semantics = routingSemantics(for: Self.routeKind(forModelID: model))
        return ChatWebGroundingDecision.shouldEnableNativeWebTool(
            semantics: semantics,
            benefitsFromSearch: Self.promptBenefitsFromAppSearch(prompt),
            needsFreshFacts: Self.promptNeedsLiveWeb(prompt),
            privacyBlocksWeb: privacyBlocksWeb,
            appWebContextPresent: appWebContext != nil
        )
    }

    func shouldUseAppWebGrounding(model: String, prompt: String) -> Bool {
        let route = Self.routeKind(forModelID: model)
        let semantics = routingSemantics(for: route)
        return ChatWebGroundingDecision.shouldUseAppGrounding(
            route: route,
            semantics: semantics,
            benefitsFromSearch: Self.promptBenefitsFromAppSearch(prompt),
            needsFreshFacts: Self.promptNeedsLiveWeb(prompt),
            privacyBlocksWeb: Self.promptSourcePrivacyOverride(for: prompt).blocksWeb,
            promptNeedsRemoteWorkstation: model == ModelOption.ironclawModelID && Self.promptNeedsRemoteWorkstation(prompt)
        )
    }

    private func ironclawPrompt(
        for text: String,
        attachments: [ChatAttachment],
        webContext: WebGroundingContext?
    ) -> String {
        let prompt = AgentStore.normalizedIronclawPrompt(text)
        let workstationInstructions = Self.ironclawWorkstationInstructions(for: prompt)
        let appContext = hostedIronclawContextSection(promptAttachments: promptOnlyAttachments(from: attachments))
        guard let webContext else {
            guard !workstationInstructions.isEmpty || !appContext.isEmpty else {
                return prompt
            }
            return """
            \(workstationInstructions)
            \(appContext)

            User request:
            \(prompt)
            """
        }
        let scopedWorkstationInstructions = workstationInstructions.isEmpty ? "" : """

        \(workstationInstructions)
        """
        let scopedAppContext = appContext.isEmpty ? "" : """

        \(appContext)
        """
        let date = Date.now.formatted(date: .complete, time: .omitted)
        return """
        Current date: \(date).
        \(scopedWorkstationInstructions)
        \(scopedAppContext)

        User request:
        \(prompt)

        \(webContext.promptSection)

        Instructions:
        - Use the app-side web results above as the live search context.
        - Do not say you cannot perform web searches; the search has already been performed by the app.
        - Cite concrete sources by title or domain when making current factual claims.
        - If the search context is insufficient, say exactly what is missing, then answer from available context.
        """
    }

    private func privateRoutePrompt(for text: String, webContext: WebGroundingContext?) -> String {
        guard let webContext else { return text }
        let date = Date.now.formatted(date: .complete, time: .omitted)
        return """
        Current date: \(date).

        User request:
        \(text)

        \(webContext.promptSection)

        Instructions:
        - Use the app-side web results above as the live search context.
        - Do not say you cannot perform web searches; the search has already been performed by the app.
        - Cite concrete sources by title or domain when making current factual claims.
        """
    }

    private func hostedIronclawContextSection(promptAttachments: [ChatAttachment]) -> String {
        ChatPromptContextBuilder.hostedIronclawContextSection(
            selectedProject: selectedProject,
            promptAttachments: promptAttachments,
            sourceModeDetail: sourceModeDetail,
            documentText: { [attachmentStagingStore] attachmentID in
                attachmentStagingStore.documentText(for: attachmentID)
            }
        )
    }

    private func hostedIronclawAttachmentPayloads(for attachments: [ChatAttachment]) async -> [IronclawMessageAttachmentPayload] {
        var payloads: [IronclawMessageAttachmentPayload] = []
        for attachment in attachments where !attachment.isLocalOnly {
            guard let payload = await hostedIronclawAttachmentPayload(for: attachment) else {
                continue
            }
            payloads.append(payload)
        }
        return payloads
    }

    private func hostedIronclawAttachmentPayload(for attachment: ChatAttachment) async -> IronclawMessageAttachmentPayload? {
        do {
            let data = try await fileService.fetchFileContent(attachment.id)
            guard !data.isEmpty, data.count <= APIClient.maxUploadBytes else {
                return nil
            }
            return IronclawMessageAttachmentPayload(
                sourceAttachmentID: attachment.id,
                filename: attachment.name,
                mimeType: hostedIronclawMimeType(for: attachment),
                data: data
            )
        } catch {
            return nil
        }
    }

    private func hostedIronclawMimeType(for attachment: ChatAttachment) -> String {
        let kind = attachment.kind.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind.contains("/") {
            return kind
        }
        if kind == "pdf_text" || kind == "table_text" {
            return "text/plain"
        }
        return PrivateChatFileAPI.mimeType(for: URL(fileURLWithPath: attachment.name))
    }

    private static func ironclawWorkstationInstructions(for prompt: String) -> String {
        guard promptNeedsRemoteWorkstation(prompt) else {
            return ""
        }
        return """
        IronClaw iOS coding-agent task.
        Please run the requested Hosted IronClaw task now.
        You MUST use hosted tools before answering. For git, code, shell, tests, files, repo setup, or filesystem requests, call shell, file, grep, or apply_patch first.
        When calling shell, pass the JSON parameter named command, singular, containing one shell script string.
        If a tool call fails because of parameter shape, retry the same turn with the corrected parameter before giving a final answer.
        Do not answer "I am not sure" when a local tool can be run. If a tool is unavailable, say exactly which local tool failed.
        Use shell for repo setup, file creation, git status, tests, and capability checks. Use grep/read_file/apply_patch for targeted inspection and edits when those tools are available.
        Keep hosted runs phone-safe and bounded: use shallow clones when cloning public repos, inspect before installing, prefer focused tests over full suites, wrap long commands with timeout when available, and stop to report if setup or tests look likely to exceed a few minutes.
        If the request asks for current research, news, citations, or web evidence, call nearai_web_search first. Do not use the http tool for web search; use it only when the user supplied a specific URL that must be fetched.
        Before editing a repo, inspect the tree and git status. After editing, run the smallest useful test/check and show git diff/status.
        Format the final answer for a phone screen: lead with Result, then concise sections for Evidence when research was used, Commands, Changed Files, Tests, Risk, and Next Actions. Wrap raw command output in fenced text blocks only when it helps.
        Do not commit or emphasize generated artifacts such as __pycache__, build folders, node_modules, DerivedData, or caches unless the user explicitly asks.
        Do not use http, GitHub, tool_install, package installers, external network, or IP probes unless the user explicitly asks for that class of work.
        If a credential is truly required, request the exact credential and continue after the credential gate resolves.
        """
    }
}
