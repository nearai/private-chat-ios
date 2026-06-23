import SwiftUI

extension HomeScreen {
    func headlineText(for conversation: ConversationSummary) -> String {
        HomeConversationPreviewFormatter.displayTitle(
            chatStore.cachedConversationHeadline(for: conversation.id) ?? conversation.title
        )
    }

    func previewText(for conversation: ConversationSummary) -> String {
        HomeConversationPreviewFormatter.preview(
            cachedPreview: chatStore.cachedConversationPreview(for: conversation.id),
            title: conversation.title
        )
    }

    func hasSourceCue(for conversation: ConversationSummary) -> Bool {
        chatStore.cachedConversationHasSourceCue(for: conversation.id) ||
            HomeConversationPreviewFormatter.hasSourceCue(
            cachedPreview: chatStore.cachedConversationPreview(for: conversation.id),
            title: conversation.title
        )
    }

    func sourceSummary(for conversation: ConversationSummary) -> String? {
        if let summary = chatStore.cachedConversationSourceSummary(for: conversation.id) {
            return summary
        }
        return hasSourceCue(for: conversation) ? "Sources" : nil
    }

    func sourceChips(for conversation: ConversationSummary) -> [ConversationSourceChip] {
        chatStore.cachedConversationSourceChips(for: conversation.id)
    }

    func isRecoveryConversation(_ conversation: ConversationSummary) -> Bool {
        HomeConversationRecoveryPolicy.isRecovery(
            title: conversation.title,
            preview: previewText(for: conversation),
            hasSourceCue: hasSourceCue(for: conversation)
        )
    }

    func projectName(for conversation: ConversationSummary) -> String? {
        if let selectedProject = projectStore.selectedProject,
           selectedProject.conversationIDs.contains(conversation.id) {
            return selectedProject.name
        }
        return projectStore.visibleProjects.first { $0.conversationIDs.contains(conversation.id) }?.name
    }

    func projectSubtitle(_ project: ChatProject) -> String {
        var parts: [String] = []
        if let chats = optionalCountLabel(project.conversationIDs.count, singular: "chat") {
            parts.append(chats)
        }
        parts.append(contentsOf: contextSubtitleParts(project))
        return parts.isEmpty ? "Ready for sources" : parts.joined(separator: " · ")
    }

    func archivedProjectSubtitle(_ project: ChatProject) -> String {
        var parts = ["Archived project"]
        if let archivedAt = project.archivedAt {
            parts.append(archivedAt.formatted(date: .abbreviated, time: .omitted))
        }
        let activeContext = contextSubtitleParts(project)
        if !activeContext.isEmpty {
            parts.append(activeContext.joined(separator: " · "))
        }
        return parts.joined(separator: " · ")
    }

    func openPendingSetupLaunchCard(_ state: SetupLaunchCardState) {
        UserSetupStorage.clearPendingLaunchCard(for: state.accountID)
        AppHaptics.lightImpact()
        chatStore.applySetupProfile(state.profile)
    }

    func openProjectContext(_ project: ChatProject) {
        AppHaptics.selection()
        chatStore.selectProject(project)
        homeStore.showingProjectFiles = true
    }

    func dismissPendingSetupLaunchCard(_ state: SetupLaunchCardState) {
        UserSetupStorage.clearPendingLaunchCard(for: state.accountID)
        chatStore.bannerMessage = "Setup saved. Start from Home anytime."
    }

    var setupRouteBlock: CapabilityRouteBlock? {
        guard let issue = chatStore.routeReadinessIssue else { return nil }
        switch issue.route {
        case .nearCloud:
            return .nearCloudKeyRequired
        case .hostedIronclaw:
            return .hostedIronclawEndpointRequired
        case .council:
            return .councilNeedsModels
        }
    }

    func setupCardNextStep(for plan: AppSetupPlan) -> CapabilityNextStep? {
        let recommendation = CapabilityNextStepPlanner.recommend(
            routeBlock: setupRouteBlock,
            setupPlan: plan,
            currentRoute: chatStore.selectedRouteKind,
            hasFreshPrivateProof: true,
            hostedIronclawAvailable: chatStore.ironclawRemoteWorkstationAvailable,
            autoCouncilReady: chatStore.defaultCouncilModels.count >= 2
        )

        guard let recommendation else { return nil }
        switch recommendation.kind {
        case .openCloud, .openAgent, .useAutoCouncil:
            return recommendation
        case .openSecurity, .rerunSetup:
            return nil
        }
    }

    func setupCardRecommendation(for plan: AppSetupPlan) -> SetupCardRecommendation? {
        guard let recommendation = setupCardNextStep(for: plan) else { return nil }
        return setupCardRecommendation(from: recommendation)
    }

    func setupCardRecommendation(from recommendation: CapabilityNextStep) -> SetupCardRecommendation {
        return SetupCardRecommendation(
            title: recommendation.title,
            detail: recommendation.detail,
            actionTitle: recommendation.actionTitle,
            actionSymbolName: setupCardRecommendationSymbolName(for: recommendation.kind)
        )
    }

    func setupCardRecommendationSymbolName(for kind: CapabilityNextStepKind) -> String {
        switch kind {
        case .openCloud:
            return "key"
        case .openAgent:
            return "point.3.connected.trianglepath.dotted"
        case .useAutoCouncil:
            return "square.grid.2x2"
        case .openSecurity:
            return "checkmark.shield"
        case .rerunSetup:
            return "arrow.counterclockwise"
        }
    }

    func runSetupCardRecommendation(for plan: AppSetupPlan) {
        guard let recommendation = setupCardNextStep(for: plan) else { return }
        runRecommendation(recommendation)
    }

    func runFirstRunRecommendation(_ recommendation: CapabilityNextStep) {
        runRecommendation(recommendation)
    }

    func runRecommendation(_ recommendation: CapabilityNextStep) {
        switch recommendation.kind {
        case .openCloud, .openAgent:
            AppHaptics.lightImpact()
            openAccountSettings(deepLink: AccountSettingsDeepLink(capabilityNextStepKind: recommendation.kind))
        case .useAutoCouncil:
            AppHaptics.selection()
            chatStore.useDefaultCouncilLineup()
        case .openSecurity, .rerunSetup:
            break
        }
    }

    func openAccountSettings(deepLink: AccountSettingsDeepLink? = nil) {
        homeStore.accountSettingsDeepLink = deepLink
        homeStore.showingAccountSettings = true
    }

    func reopenSavedSetup(_ state: SetupLaunchCardState) {
        if !state.restoreState.needsRestore, state.plan.firstRunDraft == nil {
            AppHaptics.selection()
            openNewChat()
            return
        }
        AppHaptics.lightImpact()
        chatStore.applySetupProfile(state.profile)
    }

    func openSetupPromptSuggestion(
        _ suggestion: SetupPromptSuggestion,
        from state: SetupLaunchCardState,
        clearsPendingCard: Bool
    ) {
        if clearsPendingCard {
            UserSetupStorage.clearPendingLaunchCard(for: state.accountID)
        }

        AppHaptics.selection()

        let profileWillOpenDraft = state.restoreState.needsRestore && state.plan.firstRunDraft != nil
        if state.restoreState.needsRestore {
            chatStore.applySetupProfile(state.profile)
        }

        if !profileWillOpenDraft {
            chatStore.startNewConversation()
            onStartNewChat()
        }

        chatStore.draft = suggestion.prompt
        chatStore.bannerMessage = "Starter prompt ready."
    }

    func openSetupAgentMissionSuggestion(
        _ suggestion: SetupAgentMissionSuggestion,
        from state: SetupLaunchCardState,
        clearsPendingCard: Bool
    ) {
        if clearsPendingCard {
            UserSetupStorage.clearPendingLaunchCard(for: state.accountID)
        }

        AppHaptics.selection()

        let profileWillOpenDraft = state.restoreState.needsRestore && state.plan.firstRunDraft != nil
        if state.restoreState.needsRestore {
            chatStore.applySetupProfile(state.profile)
        }

        if !profileWillOpenDraft {
            chatStore.startNewConversation()
            onStartNewChat()
        }

        chatStore.draft = suggestion.prompt
        chatStore.bannerMessage = "Agent mission ready."
    }

    func openSetupSkillSuggestion(
        _ skill: IronclawSkillProfile,
        from state: SetupLaunchCardState,
        clearsPendingCard: Bool
    ) {
        if clearsPendingCard {
            UserSetupStorage.clearPendingLaunchCard(for: state.accountID)
        }

        AppHaptics.selection()

        let profileWillOpenDraft = state.restoreState.needsRestore && state.plan.firstRunDraft != nil
        if state.restoreState.needsRestore {
            chatStore.applySetupProfile(state.profile)
        }

        if !profileWillOpenDraft {
            chatStore.startNewConversation()
            onStartNewChat()
        }

        chatStore.draft = skill.missionPrompt(
            seed: state.plan.goalText,
            projectName: state.plan.starterProjectName ?? chatStore.selectedProject?.name
        )
        chatStore.bannerMessage = "\(skill.title) prompt ready."
    }

    func openHomeTrustFlow() {
        AppHaptics.selection()
        if shouldFetchHomeAttestation {
            Task {
                await chatStore.refreshAttestationReport()
                homeStore.showingSecurity = true
            }
            return
        }
        homeStore.showingSecurity = true
    }

    var currentModelRoute: AppSetupModelRoute {
        if chatStore.selectedModelOption?.isIronclawMobileRuntime == true ||
            chatStore.selectedModelOption?.isIronclawHostedModel == true {
            return .ironclaw
        }
        if chatStore.isCouncilModeEnabled {
            return .council
        }
        return .privateModel
    }

    func projectMatchesSearch(_ project: ChatProject) -> Bool {
        project.name.localizedCaseInsensitiveContains(searchQuery) ||
        project.instructions.localizedCaseInsensitiveContains(searchQuery) ||
        project.memorySummary.localizedCaseInsensitiveContains(searchQuery) ||
        project.attachments.contains { $0.name.localizedCaseInsensitiveContains(searchQuery) } ||
        project.links.contains {
            $0.displayTitle.localizedCaseInsensitiveContains(searchQuery) ||
            $0.urlString.localizedCaseInsensitiveContains(searchQuery)
        } ||
        project.notes.contains {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            $0.text.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    func contextSubtitleParts(_ project: ChatProject) -> [String] {
        var parts: [String] = []
        let sources = project.attachments.count + project.links.count
        if let sources = optionalCountLabel(sources, singular: "source") {
            parts.append(sources)
        }
        if let notes = optionalCountLabel(project.notes.count, singular: "note") {
            parts.append(notes)
        }
        return parts
    }

    func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }

    func optionalCountLabel(_ count: Int, singular: String) -> String? {
        count > 0 ? countLabel(count, singular: singular) : nil
    }
}
