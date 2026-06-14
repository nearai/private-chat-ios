import Foundation

extension ChatStore {
    static func promptBenefitsFromAppSearch(_ prompt: String) -> Bool {
        let lowercased = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if promptNeedsLiveWeb(lowercased) {
            return true
        }
        let questionPrefixes = [
            "what did ",
            "what happened",
            "what has ",
            "what is ",
            "who is ",
            "who are ",
            "when did ",
            "where did ",
            "why did ",
            "how did ",
            "tell me about "
        ]
        return questionPrefixes.contains { lowercased.hasPrefix($0) }
    }

    func preferredAvailableModel(excluding unavailableModel: String? = nil) -> String? {
        preferredAvailableModel(excluding: unavailableModel.map { Set([$0]) } ?? Set<String>())
    }

    func routeCurrentPromptIfNeeded(_ text: String, attachments: [ChatAttachment]) {
        let sourceOverride = Self.promptSourcePrivacyOverride(for: text, hasAttachments: !attachments.isEmpty)
        applyPromptSourcePrivacyOverride(sourceOverride)
        if !sourceOverride.requiresPrivateRoute {
            if modelCatalogStore.routeToHostedIronclawIfNeeded(
                text: text,
                hostedIronclawAvailable: ironclawRemoteWorkstationAvailable
            ) {
                return
            }
        }

        if !sourceOverride.requiresPrivateRoute, modelCatalogStore.routeCouncilIfNeeded(for: text) {
            return
        }

        guard !sourceOverride.blocksWeb else { return }
        _ = modelCatalogStore.routeToPrivateForNativeWebIfNeeded(
            text: text,
            shouldUseAppWebGrounding: shouldUseAppWebGrounding(model: selectedModel, prompt: text)
        )
    }

    func ensureSelectedModelIsAvailable(shouldShowBanner: Bool) {
        modelCatalogStore.ensureSelectedModelIsAvailable(shouldShowBanner: shouldShowBanner)
    }

    func isCouncilEligible(_ model: ModelOption) -> Bool {
        modelCatalogStore.isCouncilEligible(model)
    }

    func normalizedCouncilModels(from ids: [String]) -> [ModelOption] {
        modelCatalogStore.normalizedCouncilModels(from: ids)
    }

    func normalizedCouncilModelIDs(_ ids: [String]) -> [String] {
        modelCatalogStore.normalizedCouncilModelIDs(ids)
    }

    func canPreserveCouncilModelID(_ modelID: String) -> Bool {
        modelCatalogStore.canPreserveCouncilModelID(modelID)
    }

    func normalizeCouncilSelection() {
        modelCatalogStore.normalizeCouncilSelection()
    }

    func defaultCouncilModelIDs() -> [String] {
        modelCatalogStore.defaultCouncilModelIDs()
    }

    static func model(_ model: ModelOption, matchesCandidateID candidateID: String) -> Bool {
        ModelCatalogStore.model(model, matchesCandidateID: candidateID)
    }

    func requestCouncilModelIDs(for requestModel: String) -> [String] {
        modelCatalogStore.requestCouncilModelIDs(for: requestModel)
    }

    func preferredAvailableModel(excluding unavailableModels: Set<String>) -> String? {
        modelCatalogStore.preferredAvailableModel(excluding: unavailableModels)
    }

    func preferredIronclawBaseModel(excluding unavailableModels: Set<String>) -> String? {
        let availableModels = chatModels.filter {
            $0.isOpenWeightCandidate && !deniedOpenWeightModelIDs.contains($0.id)
        }
        let availableIDs = Set(availableModels.map(\.id))
        let prioritizedIDs = ironclawOpenWeightPreferredModelIDs + rankedModels(from: availableModels).map(\.id)

        return prioritizedIDs.first { modelID in
            availableIDs.contains(modelID) &&
                !unavailableModels.contains(modelID)
        } ?? rankedModels(from: availableModels).first(where: { !unavailableModels.contains($0.id) })?.id
    }

    func visibleOutputTimeout(for model: String) -> TimeInterval? {
        MessageStreamService.visibleOutputTimeout(for: model)
    }

    func modelDisplayName(for modelID: String) -> String {
        chatModels.first(where: { $0.id == modelID })?.displayName ??
            modelID.split(separator: "/").last.map(String.init) ??
            modelID
    }

    func nearCloudUnderlyingModelID(for modelID: String) -> String? {
        if let model = chatModels.first(where: { $0.id == modelID }),
           let cloudModelID = model.nearCloudUnderlyingModelID {
            return cloudModelID
        }
        guard modelID.hasPrefix(ModelOption.nearCloudModelPrefix) else { return nil }
        let cloudID = String(modelID.dropFirst(ModelOption.nearCloudModelPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cloudID.isEmpty ? nil : cloudID
    }

    static func shouldMigrateStoredModel(_ modelID: String?) -> Bool {
        guard let modelID else { return false }
        let lowercased = modelID.lowercased()
        return lowercased == "openai/gpt-oss-120b" ||
            lowercased == "openai/gpt-5" ||
            lowercased == "openai/gpt-5.1" ||
            lowercased == "openai/gpt-5.2" ||
            lowercased == "openai/gpt-4.1" ||
            lowercased == "google/gemini-2.5-pro" ||
            lowercased == "anthropic/claude-opus-4-5" ||
            lowercased == "anthropic/claude-sonnet-4-5" ||
            lowercased.contains("/o3") ||
            lowercased.contains("/o4-mini") ||
            lowercased.contains("mini") ||
            lowercased.contains("nano") ||
            lowercased.contains("lite") ||
            lowercased.contains("flash")
    }

    static func shouldUpgradeStoredFrontierModel(_ modelID: String?) -> Bool {
        guard let modelID else { return false }
        return [
            "openai/gpt-5",
            "openai/gpt-5.1",
            "openai/gpt-5.2",
            "openai/gpt-5.4"
        ].contains(modelID.lowercased())
    }

    static func shouldMigrateClosedProviderModel(_ modelID: String?) -> Bool {
        guard let modelID else { return false }
        let lowercased = modelID.lowercased()
        guard !lowercased.hasPrefix("ironclaw/"),
              !lowercased.hasPrefix("openai/gpt-oss") else {
            return false
        }
        return lowercased.hasPrefix("openai/") ||
            lowercased.hasPrefix("anthropic/") ||
            lowercased.hasPrefix("google/") ||
            lowercased.hasPrefix("x-ai/") ||
            lowercased.hasPrefix("mistral/")
    }

    func rankedModels(from source: [ModelOption]) -> [ModelOption] {
        modelCatalogStore.rankedModels(from: source)
    }

    nonisolated static func isExternalModel(_ modelID: String) -> Bool {
        MessageRepository.isExternalModel(modelID)
    }

    nonisolated static func promptNeedsLiveWeb(_ prompt: String) -> Bool {
        RoutePlanner.promptNeedsLiveWeb(prompt)
    }

    nonisolated static func shouldDiscloseAutoLiveWeb(
        sourceMode: ChatSourceMode,
        researchModeEnabled: Bool,
        prompt: String
    ) -> Bool {
        RoutePlanner.shouldDiscloseAutoLiveWeb(
            sourceMode: sourceMode,
            researchModeEnabled: researchModeEnabled,
            prompt: prompt
        )
    }

    static func promptRequestsCouncil(_ prompt: String) -> Bool {
        RoutePlanner.promptRequestsCouncil(prompt)
    }

    nonisolated static func promptNeedsRemoteWorkstation(_ prompt: String) -> Bool {
        RoutePlanner.promptNeedsRemoteWorkstation(prompt)
    }

    nonisolated static func modelAfterHostedAutoRoute(
        selectedModelID: String,
        text: String,
        hostedIronclawAvailable: Bool
    ) -> String {
        RoutePlanner.modelAfterHostedAutoRoute(
            selectedModelID: selectedModelID,
            text: text,
            hostedIronclawAvailable: hostedIronclawAvailable
        )
    }

    func phoneAgentMissionPromptIfNeeded(for text: String) -> String? {
        guard selectedModel == ModelOption.ironclawModelID || selectedModel == ModelOption.ironclawMobileModelID else {
            return nil
        }
        guard Self.promptNeedsRemoteWorkstation(text) else {
            return nil
        }
        return AgentStore.phoneAgentMissionPrompt(for: text)
    }

    func organizePhoneAgentConversationIfNeeded(
        conversation: ConversationSummary,
        originalText: String,
        routedText: String
    ) {
        guard selectedModel == ModelOption.ironclawModelID || selectedModel == ModelOption.ironclawMobileModelID else {
            return
        }
        guard Self.promptNeedsRemoteWorkstation(originalText) || Self.promptNeedsRemoteWorkstation(routedText) else {
            return
        }
        guard let detectedRepoURL = AgentStore.firstRepoURL(in: "\(originalText)\n\(routedText)"),
              let projectName = AgentStore.repoProjectName(from: detectedRepoURL) else {
            return
        }
        let repoRootURL = AgentStore.repoRootURL(from: detectedRepoURL) ?? detectedRepoURL

        let project: ChatProject
        if let selectedProject {
            project = selectedProject
            projectStore.assign(conversationID: conversation.id, to: selectedProject.id)
        } else {
            project = projectStore.ensureProject(named: projectName, includeConversationID: conversation.id)
        }

        projectStore.addLinkIfNeeded(
            projectID: project.id,
            title: projectName,
            urlString: repoRootURL.absoluteString
        )
        if detectedRepoURL.absoluteString != repoRootURL.absoluteString {
            projectStore.addLinkIfNeeded(
                projectID: project.id,
                title: AgentStore.repoTaskLinkTitle(from: detectedRepoURL, projectName: projectName),
                urlString: detectedRepoURL.absoluteString
            )
        }

        projectStore.updateInstructionsIfEmpty(
            projectID: project.id,
            instructions: "Repo-backed Agent Project. Use saved repo, issue, PR, and source links for follow-up research, code edits, tests, and triage for \(projectName)."
        )
    }

    func updateCurrentExchange(to model: String, shouldClearText: Bool = true) {
        guard let currentAssistantMessageID,
              let assistantIndex = messages.firstIndex(where: { $0.id == currentAssistantMessageID }) else {
            return
        }

        messages[assistantIndex].model = model
        messages[assistantIndex].trustMetadata = assistantTrustMetadata(
            for: model,
            capturedAt: messages[assistantIndex].createdAt
        )
        if shouldClearText {
            messages[assistantIndex].text = ""
        }
        messages[assistantIndex].status = "streaming"
        messages[assistantIndex].isStreaming = true

        if assistantIndex > messages.startIndex {
            let userIndex = messages.index(before: assistantIndex)
            if messages[userIndex].role == .user {
                messages[userIndex].model = model
            }
        }
    }

    func resetCurrentAssistantForRetry(preserving preservedText: String = "") {
        guard let currentAssistantMessageID,
              let index = messages.firstIndex(where: { $0.id == currentAssistantMessageID }) else {
            return
        }

        flushPendingTextDelta(for: currentAssistantMessageID)
        messages[index].text = preservedText
        messages[index].status = "streaming"
        messages[index].responseID = nil
        messages[index].isStreaming = true
        messages[index].searchQuery = nil
        messages[index].sources = []
        messages[index].pendingApproval = nil
    }

    static func isRecoverableModelError(_ error: Error) -> Bool {
        isModelPlanError(error) || isModelAccessError(error) || isModelTimeoutError(error)
    }

    static func modelFailureSummary(_ error: Error) -> String {
        if let urlError = error as? URLError,
           let mapped = MessageRepository.transportFailureMessage(urlError) {
            return mapped
        }
        let rawMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        let message = displayFailureMessage(rawMessage)
        let normalized = message.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return "request failed"
        }
        return String(normalized.prefix(180))
    }

    static func openWeightFailureMessage(
        modelFailures: [String: String],
        modelName: (String) -> String
    ) -> String {
        let base = "No open-weight NEAR Private model returned a response for this turn."
        guard !modelFailures.isEmpty else {
            return "\(base) Refresh models or sign in again, then retry."
        }

        let details = modelFailures
            .sorted { lhs, rhs in lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending }
            .prefix(5)
            .map { "\(modelName($0.key)): \($0.value)" }
            .joined(separator: "; ")
        return "\(base) Tried \(details)."
    }

    static func isModelPlanError(_ error: Error) -> Bool {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        let lowercased = message.lowercased()
        return lowercased.contains("not available in your plan") ||
            lowercased.contains("model") && lowercased.contains("not available")
    }

    private static func isModelAccessError(_ error: Error) -> Bool {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        let lowercased = message.lowercased()
        return lowercased.contains("access denied") ||
            lowercased.contains("temporarily restricted") ||
            lowercased.contains("forbidden") ||
            lowercased.contains("not authorized") ||
            lowercased.contains("permission") && lowercased.contains("model")
    }

    private static func isModelTimeoutError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .timedOut || urlError.code == .networkConnectionLost
        }
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        let lowercased = message.lowercased()
        return lowercased.contains("timed out") ||
            lowercased.contains("timeout") ||
            lowercased.contains("still reasoning without visible output") ||
            lowercased.contains("network connection was lost")
    }

    static func localFailureMessage(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawMessage: String?
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            rawMessage = (object["error"] as? String) ?? (object["message"] as? String) ?? (object["detail"] as? String)
        } else if isRawToolFailureText(trimmed) {
            rawMessage = trimmed
        } else {
            rawMessage = nil
        }

        return rawMessage.map(displayFailureMessage)
    }

    static var gatewayStatusFailureMessage: String {
        "IronClaw accepted the request, but Hosted IronClaw only returned gateway status instead of a final answer. Start or repair the Agent connection, then retry."
    }

    static func isTransportOnlyGatewayText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return normalized == "accepted" ||
            normalized == "running" ||
            normalized == "queued" ||
            (normalized.contains("accepted") && normalized.contains("gateway")) ||
            (normalized.contains("running") && normalized.contains("configured gateway"))
    }

    // Single source of failure copy: MessageRepository owns the raw-error ->
    // user-facing mapping; this forwards so banner and timeline copy cannot drift.
    static func displayFailureMessage(_ rawValue: String) -> String {
        MessageRepository.displayFailureMessage(rawValue)
    }

    private static func isRawToolFailureText(_ text: String) -> Bool {
        let lowercased = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.isEmpty else { return false }
        return lowercased.contains("tool error") ||
            lowercased.contains("tool '") ||
            lowercased.contains("tool \"")
    }

    static func cleanedNearCloudResponse(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let lowercased = trimmed.lowercased()
        let looksLikeToolCall = lowercased.contains("default_api:web_search") ||
            lowercased.contains("<tool_call") ||
            lowercased.contains("</tool_call>") ||
            (lowercased.hasPrefix("call {") && lowercased.contains("web_search")) ||
            (lowercased.contains("\"call\"") && lowercased.contains("web_search"))

        guard looksLikeToolCall else { return trimmed }
        return "The NEAR AI Cloud model emitted tool-call markup instead of a normal answer. The iOS app handles web and project context before the model call; ask again and the route will use supplied context directly."
    }

    static func uniqueSources(_ sources: [WebSearchSource]) -> [WebSearchSource] {
        MessageRepository.uniqueSources(sources)
    }
}
