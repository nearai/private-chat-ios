import Foundation

extension ChatStore {
    func composeWidgetFollowUp(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = trimmed
        AppHaptics.selection()
    }

    func createTracker(fromWidgetAction action: WidgetActionItem) {
        guard let draft = action.appActionDraft() else {
            showBanner("This action cannot become a tracker yet.")
            return
        }
        guard draft.isReady else {
            let missing = draft.missingFields.prefix(3).joined(separator: ", ")
            showBanner("Add \(missing) before saving this tracker.")
            if let command = draft.command {
                self.draft = command
                AppHaptics.selection()
            }
            return
        }

        let briefing = Briefing(
            title: draft.title,
            prompt: draft.prompt,
            schedule: draft.schedule,
            kind: .customPrompt
        )
        onCreateTracker?(briefing)
        activityLog.record("Created tracker “\(draft.title)” from action card · \(draft.confirmation)")

        let sourceLine = draft.source.map { "\nSource: \($0)" } ?? ""
        let message = ChatLocalIntentTranscriptWriter.assistantMessage(
            text: "Created a tracker — **\(draft.confirmation)**. It runs on schedule and lands in Trackers; open it any time to Run now, change, or delete it.\(sourceLine)"
        )
        messages.append(message)
        if let conversationID = selectedConversation?.id {
            saveLocalMessages(for: conversationID)
        }
        showBanner("Tracker created.")
        AppHaptics.selection()
    }

    /// The agentic Daily Brief: active automations and their latest approved
    /// results, composed into one digest. Shared by the on-demand "brief me"
    /// intent and the scheduled .dailyBrief automation.
    func briefDigestWidget() async -> MessageWidget? {
        let trackers = trackersProvider?() ?? []
        return BriefDigest.compose(trackers: trackers, market: [])
    }

    func runBriefing(_ briefing: Briefing) async -> BriefingRunOutcome {
        // Conditional trackers are gated: evaluate the threshold against live
        // data and only deliver on a met run, so the rest of the pipeline
        // (latestResult + notification) fires exactly when it should.
        if let condition = briefing.condition {
            return await runConditionalBriefing(briefing, condition: condition)
        }

        // The Daily Brief is a client-side digest of existing automation state.
        // Other non-conditional briefings, including legacy live-data kinds,
        // route through the model so facts, sources, and presentation are not
        // hardcoded in the app.
        if briefing.kind == .dailyBrief {
            guard let digest = await briefDigestWidget() else { return .quiet }
            return .delivered(digest)
        }

        // A council briefing runs several models + a synthesis on each scheduled
        // run; a plain one runs a single model.
        if briefing.council {
            return await runCouncilBriefing(briefing)
        }
        return await runSingleModelBriefing(briefing)
    }

    /// Evaluates a conditional tracker against live price data. The threshold
    /// gate is deterministic and local; fired-alert presentation routes through
    /// the model with a value-only metric fallback so notifications are not lost.
    /// Quiet checks are intentionally not logged so the log stays meaningful.
    private func runConditionalBriefing(_ briefing: Briefing, condition: BriefingCondition) async -> BriefingRunOutcome {
        // "stock:" and "commodity:" coinIDs both price via Yahoo (commodities use
        // a futures symbol like GC=F); a bare id prices via CoinGecko.
        let yahooSymbol: String?
        if condition.coinID.hasPrefix("stock:") {
            yahooSymbol = String(condition.coinID.dropFirst("stock:".count))
        } else if condition.coinID.hasPrefix("commodity:") {
            yahooSymbol = String(condition.coinID.dropFirst("commodity:".count))
        } else {
            yahooSymbol = nil
        }
        let price: Double?
        if let yahooSymbol {
            price = await LiveDataService.stockUSDPrice(symbol: yahooSymbol)
        } else {
            price = await LiveDataService.coinUSDPrice(coinID: condition.coinID)
        }
        guard let price else {
            // Couldn't fetch — don't fire on missing data, but say why.
            return .failed("Could not fetch the current \(condition.symbol) price to check this alert. It will retry on the next run.")
        }
        guard condition.isSatisfied(by: price) else { return .quiet }
        let priceLabel = LiveDataService.usdPriceString(price)
        activityLog.record("Alert fired — \(condition.summary) (now \(priceLabel))")

        let prompt = """
        A scheduled alert fired.

        Alert: \(condition.summary)
        Checked value: \(priceLabel)
        Symbol: \(condition.symbol)

        Explain what happened concisely, include the checked value, and say what the next useful action is. If current context or sources are needed, use web search. Do not imply the app hardcoded the answer; present this as a model-routed alert follow-up based on the threshold check.
        """
        let alertBriefing = Briefing(
            title: "\(condition.symbol) alert",
            prompt: prompt,
            schedule: briefing.schedule,
            kind: .customPrompt,
            council: briefing.council
        )
        let modelOutcome = briefing.council
            ? await runCouncilBriefing(alertBriefing)
            : await runSingleModelBriefing(alertBriefing)
        if case let .delivered(modelWidget) = modelOutcome {
            return .delivered(modelWidget)
        }

        // The alert DID fire; even if the model follow-up failed, deliver the
        // deterministic threshold result so the notification is not lost.
        return .delivered(MessageWidget(
            kind: .metric,
            title: "\(condition.symbol) alert",
            time: "just now",
            metric: WidgetMetric(
                label: "\(condition.symbol) / USD",
                value: priceLabel,
                delta: condition.summary,
                trend: condition.comparator == .below ? .down : .up,
                caption: "alert triggered"
            )
        ))
    }

    private struct BriefingTextStreamResult {
        var text: String?
        var failureMessage: String?
    }

    /// One headless model turn → its full text, with private-model fallback when
    /// a selected route is temporarily blocked or unavailable.
    private func streamBriefingTextResult(
        model: String,
        prompt: String,
        conversationID: String,
        webSearchEnabled: Bool,
        attachments: [ChatAttachment] = []
    ) async -> BriefingTextStreamResult {
        var currentModel = model
        var unavailableModels = Set<String>()
        var lastFailureMessage: String?
        var fallbackHops = 0
        var transientPrivateRouteRetries = 0

        if !routeHealth.shouldAttempt(modelID: model) {
            let notice = routeHealth.restrictionNotice(for: Self.routeKind(forModelID: model))
            return BriefingTextStreamResult(text: nil, failureMessage: notice)
        }

        while true {
            final class TextSink: @unchecked Sendable { var text = "" }
            let sink = TextSink()
            let route = Self.routeKind(forModelID: currentModel)
            do {
                if Self.isExternalModel(currentModel) {
                    // Cloud/proxy model IDs are NOT valid on the private streamer.
                    // A proxy follow-up that lands here must hit the Cloud
                    // completion API, or it silently fails on the private route.
                    sink.text = try await cloudBriefingText(
                        modelID: currentModel,
                        prompt: prompt,
                        webSearchEnabled: webSearchEnabled,
                        attachments: attachments
                    )
                } else {
                    try await api.streamResponse(
                        model: currentModel,
                        text: prompt,
                        attachments: [],
                        conversationID: conversationID,
                        previousResponseID: nil,
                        webSearchEnabled: webSearchEnabled,
                        systemPrompt: activeSystemPrompt(memoryForModel: currentModel),
                        onEvent: { event in
                            switch event {
                            case let .textDelta(delta):
                                sink.text += delta
                            case let .itemDone(text):
                                if sink.text.isEmpty, let text { sink.text = text }
                            default:
                                break
                            }
                        }
                    )
                }
                routeHealth.recordSuccess(modelID: currentModel)
                diagnostics.recordSuccess(route: route, modelID: currentModel)
                let trimmed = sink.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return BriefingTextStreamResult(text: nil, failureMessage: "The model returned no visible output.")
                }
                return BriefingTextStreamResult(text: trimmed, failureMessage: nil)
            } catch {
                if route == .nearPrivate,
                   transientPrivateRouteRetries < 1,
                   RouteHealthMonitor.isTransientBusyFailure(error) {
                    transientPrivateRouteRetries += 1
                    try? await Task.sleep(nanoseconds: Self.transientPrivateRouteRetryDelayNanoseconds)
                    continue
                }

                routeHealth.recordFailure(modelID: currentModel, error: error)
                diagnostics.record(route: route, modelID: currentModel, error: error)
                lastFailureMessage = Self.displayFailureMessage(error.localizedDescription)
                unavailableModels.insert(currentModel)
                guard !Self.isExternalModel(currentModel),
                      Self.isRecoverableModelError(error),
                      fallbackHops < 1,
                      !routeHealth.isTripped(Self.routeKind(forModelID: currentModel)),
                      let fallbackModel = preferredAvailableModel(excluding: unavailableModels),
                      fallbackModel != currentModel else {
                    return BriefingTextStreamResult(text: nil, failureMessage: lastFailureMessage)
                }
                fallbackHops += 1
                currentModel = fallbackModel
            }
        }
    }

    /// One headless model turn → its full text (nil on failure / empty output).
    private func streamBriefingText(
        model: String,
        prompt: String,
        conversationID: String,
        webSearchEnabled: Bool,
        attachments: [ChatAttachment] = []
    ) async -> String? {
        let result = await streamBriefingTextResult(
            model: model,
            prompt: prompt,
            conversationID: conversationID,
            webSearchEnabled: webSearchEnabled,
            attachments: attachments
        )
        return result.text
    }

    /// Renders briefing model output into a widget (structured if the model
    /// produced a near-widget block, else a generic text card).
    private func briefingWidget(from text: String, title: String) -> MessageWidget? {
        let extraction = MessageWidget.extract(from: text)
        if let widget = extraction.widget { return widget }
        let summary = extraction.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return nil }
        return MessageWidget(kind: .generic, title: title, time: "just now", note: String(summary.prefix(600)))
    }

    private func runSingleModelBriefing(_ briefing: Briefing) async -> BriefingRunOutcome {
        let runModelID = effectiveDefaultModelID
        // Fail fast (zero network) while the route's breaker is open; the
        // backoff schedules the retry.
        if !routeHealth.shouldAttempt(modelID: runModelID),
           let notice = routeHealth.restrictionNotice(for: Self.routeKind(forModelID: runModelID)) {
            return .failed(notice)
        }
        // A cloud-routed run doesn't need (and must not depend on) a private
        // conversation — creating one fails exactly when the private session is
        // broken, which is when a cloud default model should still work.
        let conversationID: String
        if Self.isExternalModel(runModelID) {
            conversationID = ""
        } else if let conversation = try? await api.createConversation(title: briefing.title) {
            conversationID = conversation.id
        } else {
            return .failed("Could not start a private conversation for this run. Check your connection or sign in again, then run it now.")
        }
        let result = await streamBriefingTextResult(
            model: runModelID,
            prompt: briefing.prompt,
            conversationID: conversationID,
            webSearchEnabled: true,
            attachments: activeProjectContextAttachments
        )
        guard let text = result.text else {
            return .failed(result.failureMessage)
        }
        guard let widget = briefingWidget(from: text, title: briefing.title) else {
            return .failed("The model returned no usable output for this run.")
        }
        return .delivered(widget)
    }

    /// Answers a follow-up in a briefing thread by routing the question through
    /// the model with the delivery's text as context. Private route only,
    /// consistent with the app's privacy posture.
    /// Picks the model a briefing follow-up should use: the briefing's own
    /// route (first healthy council member for council briefings, else the
    /// effective default private model).
    private func briefingFollowUpModelID(for briefing: Briefing) -> String {
        if briefing.council,
           let healthyMember = defaultCouncilModelIDs().first(where: { routeHealth.shouldAttempt(modelID: $0) }) {
            return healthyMember
        }
        return effectiveDefaultModelID
    }

    func answerBriefingFollowUp(
        question: String,
        context: String,
        briefing: Briefing,
        viaProxyModelID: String? = nil
    ) async -> BriefingFollowUpResult {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return .failure(nil) }

        let followUpModelID = viaProxyModelID ?? briefingFollowUpModelID(for: briefing)
        // Tripped private route: don't burn a doomed call — fail with the
        // notice and carry the proxy option so the thread can offer one tap.
        if viaProxyModelID == nil,
           !routeHealth.shouldAttempt(modelID: followUpModelID),
           let notice = routeHealth.restrictionNotice(for: Self.routeKind(forModelID: followUpModelID)) {
            var failure = BriefingFollowUpResult.failure(notice)
            if shouldOfferBriefingProxyRetry(modelID: followUpModelID, failureMessage: notice) {
                failure.proxyModelID = modelCatalogStore.preferredPrivacyProxyModel(nearCloudKeyConfigured: nearCloudKeyConfigured)
            }
            return failure
        }

        // A Cloud/proxy follow-up doesn't need (and shouldn't depend on) a
        // private conversation — creating one would fail on a broken private
        // session, the exact case the proxy exists to work around.
        let conversationID: String
        if Self.isExternalModel(followUpModelID) {
            conversationID = ""
        } else if let conversation = try? await api.createConversation(title: "Briefing follow-up") {
            conversationID = conversation.id
        } else {
            return .failure("Could not create a briefing follow-up thread. Sign in again, then retry.")
        }
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt: String
        if trimmedContext.isEmpty {
            prompt = trimmedQuestion
        } else {
            prompt = """
            Here is a briefing I received:

            \"\"\"
            \(trimmedContext)
            \"\"\"

            My follow-up: \(trimmedQuestion)

            Answer concisely. Use web search for anything time-sensitive and cite sources.
            """
        }
        let result = await streamBriefingTextResult(
            model: followUpModelID,
            prompt: prompt,
            conversationID: conversationID,
            webSearchEnabled: true,
            attachments: activeProjectContextAttachments
        )
        if let text = result.text {
            return .success(text: text)
        }
        var failure = BriefingFollowUpResult.failure(result.failureMessage)
        if viaProxyModelID == nil,
           shouldOfferBriefingProxyRetry(modelID: followUpModelID, failureMessage: result.failureMessage) {
            failure.proxyModelID = modelCatalogStore.preferredPrivacyProxyModel(nearCloudKeyConfigured: nearCloudKeyConfigured)
        }
        return failure
    }

    private func shouldOfferBriefingProxyRetry(modelID: String, failureMessage: String?) -> Bool {
        PrivateRouteRecoveryPolicy.shouldOfferPrivacyProxyRetry(
            modelID: modelID,
            failureMessage: failureMessage,
            routeIsTripped: routeHealth.isTripped(Self.routeKind(forModelID: modelID))
        )
    }

    /// Runs a council (several models in the default lineup) on the briefing
    /// prompt, then synthesizes one answer — the scheduled equivalent of the
    /// live Council. Falls back to a single model if fewer than two are usable.
    private func runCouncilBriefing(_ briefing: Briefing) async -> BriefingRunOutcome {
        // Members on a tripped route are skipped up front; with fewer than two
        // healthy members the run degrades to a single healthy model.
        let modelIDs = defaultCouncilModelIDs().filter { routeHealth.shouldAttempt(modelID: $0) }
        guard modelIDs.count > 1 else {
            return await runSingleModelBriefing(briefing)
        }
        guard let conversation = try? await api.createConversation(title: briefing.title) else {
            return .failed("Could not start a private conversation for this run. Check your connection or sign in again, then run it now.")
        }

        // Best-effort Live Activity for the council run: one step per model plus
        // a final synthesis step. Side-effect only — the returned widget below is
        // identical whether or not the Activity ever appears.
        let totalSteps = modelIDs.count + 1
        agentActivity.start(title: briefing.title, total: totalSteps)

        var responses: [(String, String)] = []
        var firstFailureMessage: String?
        var stepsDone = 0
        for modelID in modelIDs {
            let displayName = modelDisplayName(for: modelID)
            agentActivity.update(stage: "Asking \(displayName)", completed: stepsDone)
            let result = await streamBriefingTextResult(
                model: modelID,
                prompt: briefing.prompt,
                conversationID: conversation.id,
                webSearchEnabled: true,
                attachments: activeProjectContextAttachments
            )
            if let text = result.text {
                responses.append((displayName, text))
            } else if firstFailureMessage == nil {
                firstFailureMessage = result.failureMessage
            }
            stepsDone += 1
            agentActivity.update(stage: "Asking \(displayName)", completed: stepsDone)
        }
        guard let first = responses.first else {
            agentActivity.end()
            return .failed(firstFailureMessage)
        }
        guard responses.count > 1 else {
            agentActivity.end()
            guard let widget = briefingWidget(from: first.1, title: briefing.title) else {
                return .failed("The council returned no usable output for this run.")
            }
            return .delivered(widget)
        }

        agentActivity.update(stage: "Synthesizing", completed: modelIDs.count)
        let synthesisPrompt = CouncilStreamService.synthesisPrompt(
            originalPrompt: briefing.prompt,
            routedPrompt: briefing.prompt,
            responses: responses
        )
        let synthesized = await streamBriefingText(
            model: modelIDs.first ?? Self.defaultModelID,
            prompt: synthesisPrompt,
            conversationID: conversation.id,
            webSearchEnabled: false
        )
        agentActivity.update(stage: "Synthesizing", completed: totalSteps)
        agentActivity.end()
        guard let widget = briefingWidget(from: synthesized ?? first.1, title: briefing.title) else {
            return .failed("The council returned no usable output for this run.")
        }
        return .delivered(widget)
    }
}
