import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var briefingStore: BriefingStore
    @State private var searchText = ""
    @State private var selectedHomeFilter: HomeFilter = .all
    @State private var showingNewProject = false
    @State private var showingProjectFiles = false
    @State private var showingAccountSettings = false
    @State private var accountSettingsDeepLink: AccountSettingsDeepLink?
    @State private var showingSecurity = false
    @State private var isSearchVisible = false
    @State private var editingProject: ChatProject?
    @State private var showingNewBriefing = false
    @State private var openedBriefing: Briefing?
    @State private var homeLaunchDraft = ""
    @State private var selectedHomeLaunchSuggestionID: String?
    let onOpenChat: () -> Void
    let onStartNewChat: () -> Void
    let onRunSetupAgain: () -> Void

    init(
        onOpenChat: @escaping () -> Void = {},
        onStartNewChat: @escaping () -> Void = {},
        onRunSetupAgain: @escaping () -> Void = {}
    ) {
        self.onOpenChat = onOpenChat
        self.onStartNewChat = onStartNewChat
        self.onRunSetupAgain = onRunSetupAgain
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredConversations: [ConversationSummary] {
        let conversations = searchQuery.isEmpty ? chatStore.visibleConversations : chatStore.allVisibleConversations
        return filtered(conversations)
    }

    private var filteredArchivedConversations: [ConversationSummary] {
        filtered(chatStore.archivedConversations)
    }

    private var filteredSharedWithMe: [SharedConversationInfo] {
        guard !searchQuery.isEmpty else { return chatStore.sharedWithMe }
        return chatStore.sharedWithMe.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(searchQuery) ||
            $0.conversationID.localizedCaseInsensitiveContains(searchQuery) ||
            $0.permission.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var filteredProjects: [ChatProject] {
        let projects = chatStore.visibleProjects
        guard !searchQuery.isEmpty else { return projects }
        return projects.filter { projectMatchesSearch($0) }
    }

    private var filteredArchivedProjects: [ChatProject] {
        let projects = chatStore.archivedProjects
        guard !searchQuery.isEmpty else { return projects }
        return projects.filter { projectMatchesSearch($0) }
    }

    private var filteredProjectContextMatches: [HomeProjectContextMatch] {
        HomeSearchIndex.projectContextMatches(query: searchQuery, projects: chatStore.visibleProjects)
    }

    private var setupReadinessSnapshot: AppSetupReadinessSnapshot {
        AppSetupReadinessSnapshot(
            modelCatalogLoaded: !chatStore.models.isEmpty,
            privateModelAvailable: chatStore.pickerModels.contains { !$0.isExternalModel },
            defaultCouncilModelCount: chatStore.defaultCouncilModels.count,
            ironclawMobileAvailable: chatStore.agentModels.contains { $0.id == ModelOption.ironclawMobileModelID },
            hostedIronclawAvailable: chatStore.ironclawRemoteWorkstationAvailable,
            nearCloudKeyConfigured: chatStore.nearCloudKeyConfigured
        )
    }

    private var currentSetupRuntimeSnapshot: SetupRuntimeSnapshot {
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

    private var pendingSetupLaunchCard: SetupLaunchCardState? {
        // Setup remains available from Home commands, Account, and saved skills
        // in the workboard, but stale pending setup state must not preempt Home.
        nil
    }

    private var savedSetupState: SetupLaunchCardState? {
        guard selectedHomeFilter == .all,
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

    private var emptyHomeSetupState: SetupLaunchCardState? {
        nil
    }

    private var shouldShowFirstRunSetupCard: Bool {
        // The v2 Home surface is the orchestration workboard. First-run setup is
        // available from Home and Account, but it should never preempt Home or
        // make the app feel like the older setup-led flow.
        false
    }

    private var shouldShowHomeTrustCard: Bool {
        selectedHomeFilter == .all && searchQuery.isEmpty && filteredConversations.isEmpty
    }

    private var shouldPrioritizeSetupOverToday: Bool {
        false
    }

    private var homeTrustCardViewModel: ProofCapsuleViewModel {
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
                title: "Hosted agent route",
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

    private var canFetchHomeAttestation: Bool {
        if chatStore.isCouncilModeEnabled {
            return !chatStore.activeCouncilHasExternalRoutes && chatStore.selectedRouteKind == .nearPrivate
        }
        return chatStore.selectedRouteKind == .nearPrivate
    }

    private var shouldFetchHomeAttestation: Bool {
        guard canFetchHomeAttestation, !chatStore.isLoadingAttestation else { return false }
        switch chatStore.currentAttestationStatus.effectiveState() {
        case .valid:
            return false
        case .stale, .unknown, .unavailable, .mismatch:
            return true
        }
    }

    private var homeTrustRouteLabel: String {
        if chatStore.isCouncilModeEnabled {
            return chatStore.activeCouncilRouteSummary
        }
        return chatStore.selectedProviderDisplayName
    }

    private var homeTrustActionTitle: String {
        if chatStore.isLoadingAttestation {
            return "Checking proof"
        }
        return shouldFetchHomeAttestation ? "Fetch proof" : "Open Proof report"
    }

    private var homeTrustActionSymbolName: String {
        if chatStore.isLoadingAttestation {
            return "arrow.triangle.2.circlepath"
        }
        return shouldFetchHomeAttestation ? "arrow.clockwise" : "checkmark.shield"
    }

    private var resumeConversations: [ConversationSummary] {
        guard selectedHomeFilter == .all, searchQuery.isEmpty else { return [] }
        return Array(filteredConversations.prefix(3))
    }

    private var conversationsForDateGroups: [ConversationSummary] {
        let resumeIDs = Set(resumeConversations.map(\.id))
        guard !resumeIDs.isEmpty else { return filteredConversations }
        return filteredConversations.filter { !resumeIDs.contains($0.id) }
    }

    private func filtered(_ conversations: [ConversationSummary]) -> [ConversationSummary] {
        guard !searchQuery.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            $0.id.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var conversationGroups: [HomeConversationGroup] {
        HomeSearchIndex.conversationGroups(
            searchQuery: searchQuery,
            conversations: conversationsForDateGroups
        )
    }

    private var homeOrchestrationPlan: HomeOrchestrationPlan {
        HomeOrchestrationPlanner.make(
            briefings: briefingStore.briefings,
            projects: chatStore.visibleProjects,
            conversations: chatStore.visibleConversations,
            selectedProjectID: chatStore.selectedProjectID,
            isStreaming: chatStore.isStreaming,
            routeLabel: chatStore.isCouncilModeEnabled ? chatStore.activeCouncilRouteSummary : chatStore.selectedProviderDisplayName,
            isCouncilModeEnabled: chatStore.isCouncilModeEnabled,
            defaultCouncilModelCount: chatStore.defaultCouncilModels.count,
            councilModelNames: chatStore.councilModelNames,
            hostedAgentAvailable: chatStore.ironclawRemoteWorkstationAvailable,
            mobileAgentAvailable: chatStore.agentModels.contains { $0.id == ModelOption.ironclawMobileModelID },
            setupPlan: savedSetupState?.plan,
            includesSetupDefaultsCommand: true
        )
    }

    private var homeInboxSectionPlan: HomeInboxSectionPlan {
        HomeInboxSectionPlan(
            selectedFilter: selectedHomeFilter,
            searchQuery: searchQuery,
            activeConversationCount: filteredConversations.count,
            activeProjectCount: filteredProjects.count,
            projectContextMatchCount: filteredProjectContextMatches.count,
            sharedWithMeCount: filteredSharedWithMe.count,
            archivedConversationCount: filteredArchivedConversations.count,
            archivedProjectCount: filteredArchivedProjects.count
        )
    }

    private var shouldShowDefaultWorkSurface: Bool {
        selectedHomeFilter == .all && searchQuery.isEmpty
    }

    private var shouldShowHomeFilterControls: Bool {
        selectedHomeFilter != .all || !searchQuery.isEmpty
    }

    private var shouldShowDefaultRecentRail: Bool {
        shouldShowDefaultWorkSurface && !resumeConversations.isEmpty
    }

    private var homeLaunchSubtitle: String {
        if let projectName = chatStore.selectedProject?.name.nilIfBlank {
            return "\(projectName) context is active. Chat, research, files, trackers, proof, and agent handoff all start from one prompt."
        }
        return "Chat, research, files, trackers, proof, and agent handoff all start from one prompt."
    }

    private var homeLaunchSuggestions: [EmptyChatStarterSuggestion] {
        Array(EmptyChatStarterCoordinator.suggestions(for: chatStore).prefix(5))
    }

    private var selectedHomeLaunchSuggestion: EmptyChatStarterSuggestion? {
        homeLaunchSuggestions.first { $0.id == selectedHomeLaunchSuggestionID }
    }

    private var homeLaunchActionTitle: String {
        guard let suggestion = selectedHomeLaunchSuggestion else {
            return "Prepare chat"
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

    private var homeLaunchActionSymbolName: String {
        selectedHomeLaunchSuggestion?.symbolName ?? "arrow.up.right.circle.fill"
    }

    private var homeLaunchActionEnabled: Bool {
        selectedHomeLaunchSuggestion != nil ||
        !homeLaunchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ClaudeHomeTopBar(
                displayName: sessionStore.displayName,
                isSearchVisible: isSearchVisible,
                onAccount: { openAccountSettings() },
                onSearch: toggleSearch,
                onNewChat: openNewChat
            )

            if isSearchVisible || !searchText.isEmpty {
                SidebarSearchField(text: $searchText, prompt: "Search chats, projects, and sources")
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                LazyVStack(spacing: 14) {
                    if let pendingSetupLaunchCard, searchQuery.isEmpty {
                        SetupLaunchCard(
                            plan: pendingSetupLaunchCard.plan,
                            recommendation: setupCardRecommendation(for: pendingSetupLaunchCard.plan),
                            onSkillSuggestion: { skill in
                                openSetupSkillSuggestion(skill, from: pendingSetupLaunchCard, clearsPendingCard: true)
                            },
                            onPrimaryAction: {
                                openPendingSetupLaunchCard(pendingSetupLaunchCard)
                            },
                            onAgentMission: { suggestion in
                                openSetupAgentMissionSuggestion(suggestion, from: pendingSetupLaunchCard, clearsPendingCard: true)
                            },
                            onPromptSuggestion: { suggestion in
                                openSetupPromptSuggestion(suggestion, from: pendingSetupLaunchCard, clearsPendingCard: true)
                            },
                            onRecommendationAction: {
                                runSetupCardRecommendation(for: pendingSetupLaunchCard.plan)
                            },
                            onDismiss: {
                                dismissPendingSetupLaunchCard(pendingSetupLaunchCard)
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }

                    if shouldShowHomeFilterControls {
                        homeFilterControls
                    }

                    if shouldShowDefaultWorkSurface {
                        homePromptCaptureCard
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    homeWorkboardSurface

                    if shouldShowDefaultWorkSurface {
                        homeLibraryShortcuts
                    }

                    if homeInboxSectionPlan.showsProjectContext {
                        VStack(spacing: 8) {
                            HomeSectionHeader(title: "Project context")

                            LazyVStack(spacing: 0) {
                                ForEach(filteredProjectContextMatches) { match in
                                    Button {
                                        openProjectContext(match.project)
                                    } label: {
                                        ProjectContextSearchRow(match: match)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, pendingSetupLaunchCard == nil ? 12 : 0)
                    }

                    if homeInboxSectionPlan.showsProjects {
                        VStack(spacing: 8) {
                            HomeSectionHeader(
                                title: searchQuery.isEmpty ? "Projects" : "Project matches",
                                actionTitle: searchQuery.isEmpty ? "New" : nil,
                                actionSymbolName: searchQuery.isEmpty ? "plus" : nil,
                                action: searchQuery.isEmpty ? { showingNewProject = true } : nil
                            )

                            LazyVStack(spacing: 0) {
                                ForEach(Array(filteredProjects.enumerated()), id: \.element.id) { index, project in
                                    Button {
                                        openProjectContext(project)
                                    } label: {
                                        ProjectRow(
                                            title: project.name,
                                            subtitle: projectSubtitle(project),
                                            symbolName: project.projectIconName,
                                            isSelected: chatStore.selectedProjectID == project.id,
                                            tintColor: project.tintColor,
                                            tintBackground: project.tintBackgroundColor
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            openProjectContext(project)
                                        } label: {
                                            Label("Open Context", systemImage: "folder")
                                        }
                                        Button {
                                            editingProject = project
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        Button {
                                            chatStore.archiveProject(project)
                                        } label: {
                                            Label("Archive", systemImage: "archivebox")
                                        }
                                    }

                                    if index != filteredProjects.count - 1 {
                                        Divider()
                                            .padding(.leading, 54)
                                    }
                                }
                            }
                            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                    }

                    if homeInboxSectionPlan.showsActiveSetupEmptyState {
                        if let emptyHomeSetupState {
                            VStack(spacing: 14) {
                                SavedSetupHomeCard(
                                    plan: emptyHomeSetupState.plan,
                                    restoreState: emptyHomeSetupState.restoreState,
                                    recommendation: setupCardRecommendation(for: emptyHomeSetupState.plan),
                                    onSkillSuggestion: { skill in
                                        openSetupSkillSuggestion(skill, from: emptyHomeSetupState, clearsPendingCard: false)
                                    },
                                    onPrimaryAction: {
                                        reopenSavedSetup(emptyHomeSetupState)
                                    },
                                    onAgentMission: { suggestion in
                                        openSetupAgentMissionSuggestion(suggestion, from: emptyHomeSetupState, clearsPendingCard: false)
                                    },
                                    onPromptSuggestion: { suggestion in
                                        openSetupPromptSuggestion(suggestion, from: emptyHomeSetupState, clearsPendingCard: false)
                                    },
                                    onRecommendationAction: {
                                        runSetupCardRecommendation(for: emptyHomeSetupState.plan)
                                    },
                                    onChangeSetup: onRunSetupAgain
                                )

                                // v2: HomeTrustReadinessCard removed — trust state
                                // is surfaced inside the chat thread, not on Home.
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, pendingSetupLaunchCard == nil ? 12 : 0)
                        } else if shouldShowFirstRunSetupCard {
                            FirstRunSetupHomeCard(
                                readiness: setupReadinessSnapshot,
                                routeDefaults: chatStore.setupRouteDefaults,
                                onStartSetup: onRunSetupAgain,
                                onStartPrivateChat: startPrivateChatFromFirstRun,
                                onQuickStart: startQuickStartFromFirstRun,
                                onRecommendationAction: runFirstRunRecommendation
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        } else if homeInboxSectionPlan.showsActiveSearchEmptyState {
                            VStack(spacing: 14) {
                                ClaudeHomeEmptyState(
                                    title: searchQuery.isEmpty ? "Start a private chat" : "No matching chats or projects",
                                    showsAction: searchQuery.isEmpty,
                                    action: openNewChat
                                )
                                .frame(maxWidth: .infinity)
                                .containerRelativeFrame(.vertical)

                                // v2: HomeTrustReadinessCard removed — trust state
                                // lives inside the chat thread, not on Home.
                            }
                        }
                    }

                    if homeInboxSectionPlan.showsConversations {
                        if shouldShowDefaultRecentRail {
                            homeRecentChatsSection
                        } else {
                            fullChatHistorySection
                        }
                    }

                    sharedWithMeSection

                    archivedProjectsSection

                    archivedConversationsSection

                    filteredEmptyStateSection
                }
            }
            .refreshable {
                await chatStore.refreshConversations()
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingNewProject) {
            NewProjectView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingProjectFiles) {
            ProjectFilesView(
                onOpenConversation: { conversation in
                    showingProjectFiles = false
                    DispatchQueue.main.async {
                        openConversation(conversation)
                    }
                },
                onStagePrompt: { prompt in
                    showingProjectFiles = false
                    DispatchQueue.main.async {
                        stageProjectPrompt(prompt)
                    }
                }
            )
            .environmentObject(chatStore)
        }
        .sheet(item: $editingProject) { project in
            EditProjectView(project: project)
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingAccountSettings, onDismiss: {
            accountSettingsDeepLink = nil
        }) {
            AccountSettingsView(initialDeepLink: accountSettingsDeepLink, onRunSetupAgain: onRunSetupAgain)
                .environmentObject(sessionStore)
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingSecurity) {
            SecurityView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingNewBriefing) {
            BriefingEditorSheet(
                briefing: nil,
                onSave: { briefingStore.add($0) },
                onDelete: { briefingStore.remove($0) }
            )
        }
        .fullScreenCover(item: $openedBriefing) { briefing in
            ThreadedBriefingView(
                briefing: briefing,
                store: briefingStore,
                onAskFollowUp: { question, context in
                    await chatStore.answerBriefingFollowUp(question: question, context: context, briefing: briefing)
                }
            ) { openedBriefing = nil }
        }
        .navigationDestination(for: SharedConversationInfo.self) { item in
            SharedWithMePreviewView(item: item)
                .environmentObject(chatStore)
        }
        .task {
            selectedHomeFilter = .all
            if chatStore.sharedWithMe.isEmpty {
                await chatStore.refreshSharedWithMe(showErrors: false)
            }
        }
    }

    private var homeFilterControls: some View {
        HomeFilterStrip(
            selectedFilter: $selectedHomeFilter,
            counts: filterCounts,
            onSelect: selectHomeFilter
        )
        .padding(.horizontal, 16)
        .padding(.top, searchQuery.isEmpty ? 0 : 12)
    }

    @ViewBuilder
    private var homeWorkboardSurface: some View {
        if homeInboxSectionPlan.showsWorkboard, !shouldPrioritizeSetupOverToday {
            HomeOrchestrationSurface(
                plan: homeOrchestrationPlan,
                onAction: runHomeOrchestrationAction
            )
        }
    }

    private var homeLibraryShortcuts: some View {
        HStack(spacing: 8) {
            homeLibraryShortcut(
                title: "Shared",
                count: filteredSharedWithMe.count,
                symbolName: "person.2",
                filter: .shared
            )

            homeLibraryShortcut(
                title: "Archive",
                count: filteredArchivedConversations.count + filteredArchivedProjects.count,
                symbolName: "archivebox",
                filter: .archived
            )
        }
        .padding(.horizontal, 16)
    }

    private func homeLibraryShortcut(title: String, count: Int, symbolName: String, filter: HomeFilter) -> some View {
        Button {
            AppHaptics.selection()
            selectHomeFilter(filter)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) items")
    }

    private var homeRecentChatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeSectionHeader(title: "Recent chats")
            HomeRecentsRow(
                conversations: resumeConversations,
                projectNameForConversation: projectName(for:),
                onOpenConversation: openConversation
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    private var fullChatHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeSectionHeader(title: searchQuery.isEmpty ? "Chat history" : "Chat matches")

            LazyVStack(spacing: 0) {
                ForEach(Array(filteredConversations.enumerated()), id: \.element.id) { index, conversation in
                    Button {
                        openConversation(conversation)
                    } label: {
                        ClaudeThreadRow(
                            conversation: conversation,
                            preview: previewText(for: conversation),
                            isLast: index == filteredConversations.count - 1
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            chatStore.togglePinConversation(conversation)
                        } label: {
                            Label(conversation.isPinned ? "Unpin" : "Pin", systemImage: conversation.isPinned ? "pin.slash" : "pin")
                        }
                        Button {
                            chatStore.archiveConversation(conversation)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        Button(role: .destructive) {
                            chatStore.requestDeleteConversation(conversation)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .padding(.top, pendingSetupLaunchCard == nil ? 0 : 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private var sharedWithMeSection: some View {
        if homeInboxSectionPlan.showsSharedWithMe {
            VStack(spacing: 8) {
                HomeSectionHeader(
                    title: searchQuery.isEmpty ? "Shared With Me" : "Shared matches",
                    actionTitle: chatStore.isLoadingSharedWithMe ? nil : "Refresh",
                    actionSymbolName: "arrow.clockwise",
                    action: sharedRefreshAction
                )

                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredSharedWithMe.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item) {
                            SharedWithMeRow(item: item)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)

                        if index != filteredSharedWithMe.count - 1 {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                }
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    @ViewBuilder
    private var archivedProjectsSection: some View {
        if homeInboxSectionPlan.showsArchivedProjects {
            VStack(spacing: 8) {
                HomeSectionHeader(title: searchQuery.isEmpty ? "Archived Projects" : "Archived project matches")

                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredArchivedProjects.enumerated()), id: \.element.id) { index, project in
                        Button {
                            chatStore.unarchiveProject(project)
                        } label: {
                            ProjectRow(
                                title: project.name,
                                subtitle: archivedProjectSubtitle(project),
                                symbolName: project.projectIconName,
                                isSelected: false,
                                tintColor: project.tintColor,
                                tintBackground: project.tintBackgroundColor
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                chatStore.unarchiveProject(project)
                            } label: {
                                Label("Restore Project", systemImage: "arrow.uturn.backward")
                            }
                        }

                        if index != filteredArchivedProjects.count - 1 {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                }
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var archivedConversationsSection: some View {
        if homeInboxSectionPlan.showsArchivedConversations {
            VStack(spacing: 8) {
                HomeSectionHeader(title: searchQuery.isEmpty ? "Archived Chats" : "Archived chat matches")

                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredArchivedConversations.enumerated()), id: \.element.id) { index, conversation in
                        Button {
                            chatStore.unarchiveConversation(conversation)
                        } label: {
                            ClaudeThreadRow(
                                conversation: conversation,
                                preview: "Tap to restore this archived chat.",
                                isLast: index == filteredArchivedConversations.count - 1
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                chatStore.unarchiveConversation(conversation)
                            } label: {
                                Label("Restore Chat", systemImage: "arrow.uturn.backward")
                            }
                            Button(role: .destructive) {
                                chatStore.requestDeleteConversation(conversation)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    @ViewBuilder
    private var filteredEmptyStateSection: some View {
        if homeInboxSectionPlan.showsSharedEmptyState {
            HomeInboxEmptyState(
                title: chatStore.isLoadingSharedWithMe ? "Loading shared chats" : (searchQuery.isEmpty ? "No shared chats" : "No shared matches"),
                subtitle: sharedEmptyStateSubtitle,
                symbolName: "person.2.slash",
                isLoading: chatStore.isLoadingSharedWithMe,
                actionTitle: chatStore.isLoadingSharedWithMe ? nil : "Refresh",
                actionSymbolName: "arrow.clockwise",
                action: sharedRefreshAction
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        } else if homeInboxSectionPlan.showsArchivedEmptyState {
            HomeInboxEmptyState(
                title: searchQuery.isEmpty ? "No archived items" : "No archived matches",
                subtitle: searchQuery.isEmpty ? "Archived chats and projects will collect here." : "Try another search or switch filters.",
                symbolName: "archivebox"
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    private var sharedEmptyStateSubtitle: String {
        if chatStore.isLoadingSharedWithMe {
            return "Checking shared conversations."
        }
        if searchQuery.isEmpty {
            return "Conversations shared with you will collect here."
        }
        return "Try another search or switch filters."
    }

    private var sharedRefreshAction: (() -> Void)? {
        guard !chatStore.isLoadingSharedWithMe else { return nil }
        return {
            _ = Task { await chatStore.refreshSharedWithMe() }
        }
    }

    private var homePromptCaptureCard: some View {
        HomePromptCaptureCard(
            subtitle: homeLaunchSubtitle,
            draft: $homeLaunchDraft,
            suggestions: homeLaunchSuggestions,
            selectedSuggestionID: selectedHomeLaunchSuggestionID,
            selectedProjectName: chatStore.selectedProject?.name,
            actionTitle: homeLaunchActionTitle,
            actionSymbolName: homeLaunchActionSymbolName,
            actionEnabled: homeLaunchActionEnabled,
            onSelectSuggestion: toggleHomeLaunchSuggestion,
            onSubmit: runHomeLaunchPrompt
        )
    }

    private func openNewChat() {
        guard !chatStore.isStreaming else {
            chatStore.bannerMessage = "Finish or cancel the current response before starting a new chat."
            return
        }
        chatStore.startNewConversation()
        onStartNewChat()
    }

    private func startPrivateChatFromFirstRun() {
        guard !chatStore.isStreaming else {
            chatStore.bannerMessage = "Finish or cancel the current response before starting a new chat."
            return
        }

        if let accountID = sessionStore.setupAccountID,
           UserSetupStorage.needsFirstRunSetup(for: accountID) {
            let profile = chatStore.setupProfileSnapshot(
                UserSetupStorage.completeFirstRunPrivateChat(for: accountID)
            )
            UserSetupStorage.saveWithoutPendingLaunchCard(profile, for: accountID)
            chatStore.applySetupProfile(profile)
        }

        AppHaptics.selection()
        chatStore.startNewConversation()
        onStartNewChat()
    }

    private func startQuickStartFromFirstRun(_ preset: UserSetupStarterPreset) {
        guard !chatStore.isStreaming else {
            chatStore.bannerMessage = "Finish or cancel the current response before starting a new chat."
            return
        }

        let profile: UserSetupProfile
        if let accountID = sessionStore.setupAccountID,
           UserSetupStorage.needsFirstRunSetup(for: accountID) {
            profile = chatStore.setupProfileSnapshot(
                UserSetupStorage.completeFirstRunQuickStart(for: accountID, preset: preset)
            )
            UserSetupStorage.saveWithoutPendingLaunchCard(profile, for: accountID)
        } else {
            profile = chatStore.setupProfileSnapshot(preset.quickStartProfile)
        }

        chatStore.applySetupProfile(profile)

        if profile.firstRunDraft == nil {
            AppHaptics.selection()
            chatStore.startNewConversation()
            chatStore.draft = preset.prompt
            chatStore.bannerMessage = "Starter prompt ready."
            onStartNewChat()
        }
    }

    private func openConversation(_ conversation: ConversationSummary) {
        guard !chatStore.isStreaming else {
            chatStore.bannerMessage = "Finish or cancel the current response before switching chats."
            return
        }
        chatStore.selectConversation(conversation)
        onOpenChat()
    }

    private func runHomeOrchestrationAction(_ action: HomeOrchestrationAction) {
        switch action {
        case .openBriefing(let briefingID):
            openedBriefing = briefingStore.briefings.first { $0.id == briefingID }
        case .openProject(let projectID):
            guard let project = chatStore.visibleProjects.first(where: { $0.id == projectID }) else { return }
            openProjectContext(project)
        case .openConversation(let conversationID):
            guard let conversation = chatStore.allVisibleConversations.first(where: { $0.id == conversationID }) else { return }
            openConversation(conversation)
        case .openAgentSettings:
            AppHaptics.lightImpact()
            openAccountSettings(deepLink: .ironclawAgent)
        case .useAutoCouncil:
            AppHaptics.selection()
            chatStore.useDefaultCouncilLineup()
        case .newBriefing:
            AppHaptics.selection()
            showingNewBriefing = true
        case .runSetupDefaults:
            AppHaptics.lightImpact()
            onRunSetupAgain()
        case .stagePrompt(let stagedPrompt):
            stageHomeOrchestrationPrompt(stagedPrompt)
        }
    }

    private func stageHomeOrchestrationPrompt(_ stagedPrompt: HomeStagedPrompt) {
        guard !chatStore.isStreaming else {
            chatStore.bannerMessage = "Finish or cancel the current response before staging a new prompt."
            return
        }

        if let projectID = stagedPrompt.projectID,
           let project = chatStore.visibleProjects.first(where: { $0.id == projectID }) {
            chatStore.selectProject(project)
        }

        chatStore.startNewConversation()
        chatStore.draft = stagedPrompt.prompt
        chatStore.bannerMessage = stagedPrompt.banner
        AppHaptics.selection()
        onStartNewChat()
    }

    private func stageProjectPrompt(_ prompt: String) {
        guard !chatStore.isStreaming else {
            chatStore.bannerMessage = "Finish or cancel the current response before staging a project prompt."
            return
        }

        chatStore.startNewConversation()
        chatStore.draft = prompt
        chatStore.bannerMessage = "Project prompt ready."
        AppHaptics.selection()
        onStartNewChat()
    }

    private func toggleHomeLaunchSuggestion(_ suggestion: EmptyChatStarterSuggestion) {
        AppHaptics.selection()
        if selectedHomeLaunchSuggestionID == suggestion.id {
            selectedHomeLaunchSuggestionID = nil
        } else {
            selectedHomeLaunchSuggestionID = suggestion.id
        }
    }

    private func runHomeLaunchPrompt() {
        guard !chatStore.isStreaming else {
            chatStore.bannerMessage = "Finish or cancel the current response before staging a new prompt."
            return
        }

        let trimmedDraft = homeLaunchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestion = selectedHomeLaunchSuggestion
        guard suggestion != nil || !trimmedDraft.isEmpty else { return }

        if let suggestion, !prepareHomeLaunchIntent(suggestion) {
            return
        }

        chatStore.startNewConversation()
        chatStore.draft = stagedHomeLaunchPrompt(prefix: suggestion?.prompt, draft: trimmedDraft)
        chatStore.bannerMessage = suggestion.map { "\($0.title) prompt ready." } ?? "Prompt ready."
        homeLaunchDraft = ""
        selectedHomeLaunchSuggestionID = nil
        AppHaptics.selection()
        onStartNewChat()
    }

    private func prepareHomeLaunchIntent(_ suggestion: EmptyChatStarterSuggestion) -> Bool {
        switch suggestion.action {
        case .draft:
            return true
        case .research:
            chatStore.selectSourceMode(.web)
            if !chatStore.selectedRouteUsesNearCloud, !chatStore.researchModeEnabled {
                chatStore.toggleResearchMode()
            }
            return true
        case .project:
            chatStore.selectSourceMode(chatStore.selectedProject == nil ? .files : .all)
            guard chatStore.selectedProject != nil else {
                showingProjectFiles = true
                chatStore.bannerMessage = "Choose files or a Project, then prepare the prompt."
                return false
            }
            return true
        case .council:
            chatStore.useDefaultCouncilLineup()
            return true
        case .agent:
            if chatStore.agentModels.contains(where: { $0.id == ModelOption.ironclawMobileModelID }) {
                chatStore.selectModel(ModelOption.ironclawMobileModelID)
            } else if chatStore.ironclawRemoteWorkstationAvailable {
                chatStore.selectModel(ModelOption.ironclawModelID)
            }
            return true
        case .trust:
            if chatStore.selectedProject != nil {
                chatStore.selectSourceMode(.all)
            } else {
                chatStore.selectSourceMode(.web)
                if !chatStore.selectedRouteUsesNearCloud, !chatStore.researchModeEnabled {
                    chatStore.toggleResearchMode()
                }
            }
            return true
        }
    }

    private func stagedHomeLaunchPrompt(prefix: String?, draft: String) -> String {
        let trimmedPrefix = prefix?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedPrefix.isEmpty else { return draft }
        guard !draft.isEmpty else { return trimmedPrefix }
        guard !draft.hasPrefix(trimmedPrefix) else { return draft }
        return "\(trimmedPrefix) \(draft)"
    }

    private var filterCounts: [HomeFilter: Int] {
        homeInboxSectionPlan.filterCounts
    }

    private func selectHomeFilter(_ filter: HomeFilter) {
        selectedHomeFilter = filter
        if filter == .all {
            chatStore.selectAllChats()
        } else if filter == .shared, chatStore.sharedWithMe.isEmpty {
            Task {
                await chatStore.refreshSharedWithMe(showErrors: false)
            }
        }
    }

    private func toggleSearch() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            isSearchVisible.toggle()
            if !isSearchVisible {
                searchText = ""
            }
        }
    }

    private func previewText(for conversation: ConversationSummary) -> String {
        chatStore.cachedConversationPreview(for: conversation.id) ?? "Tap to continue this conversation."
    }

    private func projectName(for conversation: ConversationSummary) -> String? {
        if let selectedProject = chatStore.selectedProject,
           selectedProject.conversationIDs.contains(conversation.id) {
            return selectedProject.name
        }
        return chatStore.visibleProjects.first { $0.conversationIDs.contains(conversation.id) }?.name
    }

    private func projectSubtitle(_ project: ChatProject) -> String {
        var parts: [String] = []
        if let chats = optionalCountLabel(project.conversationIDs.count, singular: "chat") {
            parts.append(chats)
        }
        parts.append(contentsOf: contextSubtitleParts(project))
        return parts.isEmpty ? "Ready for sources" : parts.joined(separator: " · ")
    }

    private func archivedProjectSubtitle(_ project: ChatProject) -> String {
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

    private func openPendingSetupLaunchCard(_ state: SetupLaunchCardState) {
        UserSetupStorage.clearPendingLaunchCard(for: state.accountID)
        AppHaptics.lightImpact()
        chatStore.applySetupProfile(state.profile)
    }

    private func openProjectContext(_ project: ChatProject) {
        AppHaptics.selection()
        chatStore.selectProject(project)
        showingProjectFiles = true
    }

    private func dismissPendingSetupLaunchCard(_ state: SetupLaunchCardState) {
        UserSetupStorage.clearPendingLaunchCard(for: state.accountID)
        chatStore.bannerMessage = "Setup saved. Start from Home whenever you're ready."
    }

    private var setupRouteBlock: CapabilityRouteBlock? {
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

    private func setupCardNextStep(for plan: AppSetupPlan) -> CapabilityNextStep? {
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

    private func setupCardRecommendation(for plan: AppSetupPlan) -> SetupCardRecommendation? {
        guard let recommendation = setupCardNextStep(for: plan) else { return nil }
        return setupCardRecommendation(from: recommendation)
    }

    private func setupCardRecommendation(from recommendation: CapabilityNextStep) -> SetupCardRecommendation {
        return SetupCardRecommendation(
            title: recommendation.title,
            detail: recommendation.detail,
            actionTitle: recommendation.actionTitle,
            actionSymbolName: setupCardRecommendationSymbolName(for: recommendation.kind)
        )
    }

    private func setupCardRecommendationSymbolName(for kind: CapabilityNextStepKind) -> String {
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

    private func runSetupCardRecommendation(for plan: AppSetupPlan) {
        guard let recommendation = setupCardNextStep(for: plan) else { return }
        runRecommendation(recommendation)
    }

    private func runFirstRunRecommendation(_ recommendation: CapabilityNextStep) {
        runRecommendation(recommendation)
    }

    private func runRecommendation(_ recommendation: CapabilityNextStep) {
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

    private func openAccountSettings(deepLink: AccountSettingsDeepLink? = nil) {
        accountSettingsDeepLink = deepLink
        showingAccountSettings = true
    }

    private func reopenSavedSetup(_ state: SetupLaunchCardState) {
        if !state.restoreState.needsRestore, state.plan.firstRunDraft == nil {
            AppHaptics.selection()
            openNewChat()
            return
        }
        AppHaptics.lightImpact()
        chatStore.applySetupProfile(state.profile)
    }

    private func openSetupPromptSuggestion(
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

    private func openSetupAgentMissionSuggestion(
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

    private func openSetupSkillSuggestion(
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

    private func openHomeTrustFlow() {
        AppHaptics.selection()
        if shouldFetchHomeAttestation {
            Task {
                await chatStore.refreshAttestationReport()
                showingSecurity = true
            }
            return
        }
        showingSecurity = true
    }

    private var currentModelRoute: AppSetupModelRoute {
        if chatStore.selectedModelOption?.isIronclawMobileRuntime == true ||
            chatStore.selectedModelOption?.isIronclawHostedModel == true {
            return .ironclaw
        }
        if chatStore.isCouncilModeEnabled {
            return .council
        }
        return .privateModel
    }

    private func projectMatchesSearch(_ project: ChatProject) -> Bool {
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

    private func contextSubtitleParts(_ project: ChatProject) -> [String] {
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

    private func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }

    private func optionalCountLabel(_ count: Int, singular: String) -> String? {
        count > 0 ? countLabel(count, singular: singular) : nil
    }
}
