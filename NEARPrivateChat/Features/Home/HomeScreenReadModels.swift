import SwiftUI

extension HomeScreen {
    var searchQuery: String {
        homeStore.searchQuery
    }

    var filteredConversations: [ConversationSummary] {
        let conversations = searchQuery.isEmpty ? visibleConversationReadModels : conversationStore.allVisibleConversations
        return filtered(conversations)
    }

    var filteredArchivedConversations: [ConversationSummary] {
        filtered(conversationStore.archivedConversations)
    }

    var filteredSharedWithMe: [SharedConversationInfo] {
        guard !searchQuery.isEmpty else { return shareStore.sharedWithMe }
        return shareStore.sharedWithMe.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(searchQuery) ||
            $0.conversationID.localizedCaseInsensitiveContains(searchQuery) ||
            $0.permission.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var filteredProjects: [ChatProject] {
        let projects = projectStore.visibleProjects
        guard !searchQuery.isEmpty else { return projects }
        return projects.filter { projectMatchesSearch($0) }
    }

    var filteredArchivedProjects: [ChatProject] {
        let projects = projectStore.archivedProjects
        guard !searchQuery.isEmpty else { return projects }
        return projects.filter { projectMatchesSearch($0) }
    }

    var filteredProjectContextMatches: [HomeProjectContextMatch] {
        HomeSearchIndex.projectContextMatches(query: searchQuery, projects: projectStore.visibleProjects)
    }

    var setupReadinessSnapshot: AppSetupReadinessSnapshot {
        AppSetupReadinessSnapshot(
            modelCatalogLoaded: !chatStore.models.isEmpty,
            privateModelAvailable: chatStore.pickerModels.contains { !$0.isExternalModel },
            defaultCouncilModelCount: chatStore.defaultCouncilModels.count,
            ironclawMobileAvailable: chatStore.agentModels.contains { $0.id == ModelOption.ironclawMobileModelID },
            hostedIronclawAvailable: chatStore.ironclawRemoteWorkstationAvailable,
            nearCloudKeyConfigured: chatStore.nearCloudKeyConfigured
        )
    }

    var currentSetupRuntimeSnapshot: SetupRuntimeSnapshot {
        SetupRuntimeSnapshot(
            modelRoute: currentModelRoute,
            focusMode: chatStore.sourceMode,
            webSearchEnabled: chatStore.webSearchEnabled,
            researchModeEnabled: chatStore.researchModeEnabled,
            selectedProjectName: chatStore.selectedProject?.name,
            selectedModelID: chatStore.selectedModel,
            councilModelIDs: chatStore.councilModelIDs
        )
    }

    var pendingSetupLaunchCard: SetupLaunchCardState? {
        // Setup remains available from Home commands, Account, and saved skills
        // in the workboard, but stale pending setup state must not preempt Home.
        nil
    }

    var savedSetupState: SetupLaunchCardState? {
        guard homeStore.selectedHomeFilter == .all,
              searchQuery.isEmpty,
              let accountID = sessionStore.setupAccountID,
              let profile = UserSetupStorage.load(for: accountID) else {
            return nil
        }
        let plan = AppSetupPlan(
            profile: profile,
            readiness: setupReadinessSnapshot,
            routeDefaults: profile.routeDefaults.isEmpty ? chatStore.setupRouteDefaults : profile.routeDefaults
        )
        return SetupLaunchCardState(
            accountID: accountID,
            profile: profile,
            plan: plan,
            restoreState: SetupRestorePlanner.evaluate(
                profile: profile,
                plan: plan,
                runtime: currentSetupRuntimeSnapshot
            )
        )
    }

    var emptyHomeSetupState: SetupLaunchCardState? {
        nil
    }

    var shouldShowFirstRunSetupCard: Bool {
        // The v2 Home surface is the orchestration workboard. First-run setup is
        // available from Home and Account, but it should never preempt Home or
        // make the app feel like the older setup-led flow.
        false
    }

    var shouldShowHomeTrustCard: Bool {
        homeStore.selectedHomeFilter == .all && searchQuery.isEmpty && filteredConversations.isEmpty
    }

    var shouldPrioritizeSetupOverToday: Bool {
        false
    }

    var homeTrustCardViewModel: ProofCapsuleViewModel {
        if chatStore.selectedRouteUsesNearCloud || (chatStore.isCouncilModeEnabled && chatStore.activeCouncilHasNearCloudRoutes) {
            return ProofCapsuleViewModel(
                state: .proxied,
                title: "Privacy proxy route",
                detail: "NEAR AI Cloud anonymizes your prompt to the provider before forwarding. Anonymized routes do not carry NEAR Private proof.",
                badge: "Privacy proxy",
                symbolName: "eye.slash"
            )
        }

        if chatStore.selectedModelOption?.isIronclawHostedModel == true {
            return ProofCapsuleViewModel(
                state: .unknown,
                title: "Hosted IronClaw route",
                detail: "Hosted IronClaw uses its own trust boundary. Open Proof report when you need the current route summary before handing work off.",
                badge: "Hosted route",
                symbolName: "terminal"
            )
        }

        if chatStore.selectedModelOption?.isIronclawMobileRuntime == true {
            return ProofCapsuleViewModel(
                state: .private_,
                title: "IronClaw Mobile route",
                detail: "IronClaw Mobile runs on the phone. Switch back to a NEAR Private model whenever you need signed private-route proof.",
                badge: "On-device Agent",
                symbolName: "iphone"
            )
        }

        return ProofCapsuleViewModel(
            status: chatStore.currentAttestationStatus,
            isLoading: chatStore.isLoadingAttestation,
            modelID: chatStore.selectedModel
        )
    }

    var canFetchHomeAttestation: Bool {
        if chatStore.isCouncilModeEnabled {
            return !chatStore.activeCouncilHasExternalRoutes && chatStore.selectedRouteKind == .nearPrivate
        }
        return chatStore.selectedRouteKind == .nearPrivate
    }

    var shouldFetchHomeAttestation: Bool {
        guard canFetchHomeAttestation, !chatStore.isLoadingAttestation else { return false }
        switch chatStore.currentAttestationStatus.effectiveState() {
        case .valid:
            return false
        case .stale, .unknown, .unavailable, .mismatch:
            return true
        }
    }

    var homeTrustRouteLabel: String {
        if chatStore.isCouncilModeEnabled {
            return chatStore.activeCouncilRouteSummary
        }
        return chatStore.selectedProviderDisplayName
    }

    var homeTrustActionTitle: String {
        if chatStore.isLoadingAttestation {
            return "Checking proof"
        }
        return shouldFetchHomeAttestation ? "Fetch proof" : "Open Proof report"
    }

    var homeTrustActionSymbolName: String {
        if chatStore.isLoadingAttestation {
            return "arrow.triangle.2.circlepath"
        }
        return shouldFetchHomeAttestation ? "arrow.clockwise" : "checkmark.shield"
    }

    var resumeConversations: [ConversationSummary] {
        guard homeStore.selectedHomeFilter == .all, searchQuery.isEmpty else { return [] }
        return Array(recentConversationReadModels.prefix(3))
    }

    var conversationsForDateGroups: [ConversationSummary] {
        let resumeIDs = Set(resumeConversations.map(\.id))
        guard !resumeIDs.isEmpty else { return filteredConversations }
        return filteredConversations.filter { !resumeIDs.contains($0.id) }
    }

    func filtered(_ conversations: [ConversationSummary]) -> [ConversationSummary] {
        guard !searchQuery.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            $0.id.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var conversationGroups: [HomeConversationGroup] {
        HomeSearchIndex.conversationGroups(
            searchQuery: searchQuery,
            conversations: conversationsForDateGroups
        )
    }

    var homeOrchestrationPlan: HomeOrchestrationPlan {
        HomeOrchestrationPlanner.make(
            briefings: briefingStore.briefings,
            projects: projectStore.visibleProjects,
            conversations: visibleConversationReadModels,
            selectedProjectID: projectStore.selectedProjectID,
            isStreaming: chatStore.isStreaming,
            routeLabel: chatStore.isCouncilModeEnabled ? chatStore.activeCouncilRouteSummary : chatStore.selectedProviderDisplayName,
            isCouncilModeEnabled: chatStore.isCouncilModeEnabled,
            defaultCouncilModelCount: chatStore.defaultCouncilModels.count,
            councilModelNames: chatStore.councilModelNames,
            hostedAgentAvailable: chatStore.ironclawRemoteWorkstationAvailable,
            mobileAgentAvailable: chatStore.agentModels.contains { $0.id == ModelOption.ironclawMobileModelID }
        )
    }

    var homeInboxSectionPlan: HomeInboxSectionPlan {
        HomeInboxSectionPlan(
            selectedFilter: homeStore.selectedHomeFilter,
            searchQuery: searchQuery,
            activeConversationCount: filteredConversations.count,
            activeProjectCount: filteredProjects.count,
            projectContextMatchCount: filteredProjectContextMatches.count,
            sharedWithMeCount: filteredSharedWithMe.count,
            archivedConversationCount: filteredArchivedConversations.count,
            archivedProjectCount: filteredArchivedProjects.count
        )
    }

    var visibleConversationReadModels: [ConversationSummary] {
        projectStore.selectedProject == nil ? conversationStore.visibleConversations : projectStore.visibleConversations
    }

    var recentConversationReadModels: [ConversationSummary] {
        projectStore.selectedProject == nil ? conversationStore.allVisibleConversations : projectStore.allVisibleConversations
    }

    var shouldShowDefaultWorkSurface: Bool {
        homeStore.selectedHomeFilter == .all && searchQuery.isEmpty
    }

    var shouldShowHomeFilterControls: Bool {
        homeStore.selectedHomeFilter != .all || !searchQuery.isEmpty
    }

    var shouldShowDefaultRecentRail: Bool {
        shouldShowDefaultWorkSurface && !resumeConversations.isEmpty
    }

    var visibleHomeFeedBriefings: [Briefing] {
        guard shouldShowDefaultWorkSurface else { return [] }
        return HomeFeedPlanner.visibleBriefings(
            briefingStore.briefings,
            scope: homeStore.selectedFeedScope,
            allLimit: HomeFeedPlanner.defaultAllBriefingLimit(
                totalCardLimit: defaultHomeFeedCardLimit,
                hasRecentConversations: !resumeConversations.isEmpty
            )
        )
    }

    var visibleHomeFeedChats: [ConversationSummary] {
        guard shouldShowDefaultWorkSurface else { return [] }
        switch homeStore.selectedFeedScope {
        case .all:
            let remainingCardCount = max(0, defaultHomeFeedCardLimit - visibleHomeFeedBriefings.count)
            return HomeFeedPlanner.uniqueRecentConversations(
                resumeConversations,
                limit: remainingCardCount,
                excludingBriefings: visibleHomeFeedBriefings,
                isRecoveryCandidate: isRecoveryConversation
            )
        case .chats:
            return Array(filteredConversations.prefix(8))
        case .briefings, .watchers:
            return []
        }
    }

    private var defaultHomeFeedCardLimit: Int {
        3
    }

    var homeFeedScopeCounts: [HomeFeedScope: Int] {
        HomeFeedPlanner.scopeCounts(
            briefings: briefingStore.briefings,
            visibleConversationCount: filteredConversations.count
        )
    }

    var homeLaunchSubtitle: String {
        if let projectName = chatStore.selectedProject?.name.nilIfBlank {
            return "\(projectName) context active."
        }
        return ""
    }

    var homeLaunchSuggestions: [EmptyChatStarterSuggestion] {
        []
    }

    var selectedHomeLaunchSuggestion: EmptyChatStarterSuggestion? {
        homeLaunchSuggestions.first { $0.id == homeStore.selectedHomeLaunchSuggestionID }
    }

    var homeLaunchActionTitle: String {
        guard let suggestion = selectedHomeLaunchSuggestion else {
            return "Start chat"
        }
        switch suggestion.action {
        case .agent:
            return "Prepare agent prompt"
        case .research:
            return "Prepare research"
        case .project:
            return "Prepare file action"
        case .council:
            return "Prepare Council"
        case .trust:
            return "Prepare proof view"
        case .draft:
            return "Prepare \(suggestion.title.lowercased())"
        }
    }

    var homeLaunchActionSymbolName: String {
        selectedHomeLaunchSuggestion?.symbolName ?? "arrow.up.circle.fill"
    }

    var homeLaunchActionEnabled: Bool {
        selectedHomeLaunchSuggestion != nil ||
            !homeStore.homeLaunchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }


}
