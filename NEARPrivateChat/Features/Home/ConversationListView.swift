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
        guard let savedSetupState,
              UserSetupStorage.hasPendingLaunchCard(for: savedSetupState.accountID) else {
            return nil
        }
        return savedSetupState
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
        guard searchQuery.isEmpty,
              filteredConversations.isEmpty,
              filteredProjects.isEmpty,
              filteredProjectContextMatches.isEmpty,
              pendingSetupLaunchCard == nil else {
            return nil
        }
        return savedSetupState
    }

    private var shouldShowFirstRunSetupCard: Bool {
        guard searchQuery.isEmpty,
              filteredConversations.isEmpty,
              filteredProjects.isEmpty,
              filteredProjectContextMatches.isEmpty,
              pendingSetupLaunchCard == nil,
              savedSetupState == nil,
              let accountID = sessionStore.setupAccountID else {
            return false
        }
        return UserSetupStorage.needsFirstRunSetup(for: accountID)
    }

    private var shouldShowHomeTrustCard: Bool {
        selectedHomeFilter == .all && searchQuery.isEmpty && filteredConversations.isEmpty
    }

    private var shouldPrioritizeSetupOverToday: Bool {
        pendingSetupLaunchCard != nil || emptyHomeSetupState != nil || shouldShowFirstRunSetupCard
    }

    private var homeTrustCardViewModel: ProofCapsuleViewModel {
        if chatStore.selectedRouteUsesNearCloud || (chatStore.isCouncilModeEnabled && chatStore.activeCouncilHasNearCloudRoutes) {
            return ProofCapsuleViewModel(
                state: .proxied,
                title: "Privacy proxy route",
                detail: "NEAR AI Cloud anonymizes your prompt to the provider before forwarding. Anonymized routes do not carry NEAR Private verification.",
                badge: "Privacy proxy",
                symbolName: "eye.slash"
            )
        }

        if chatStore.selectedModelOption?.isIronclawHostedModel == true {
            return ProofCapsuleViewModel(
                state: .unknown,
                title: "Hosted agent route",
                detail: "Hosted IronClaw uses its own trust boundary. Open Security when you need the current route summary before handing work off.",
                badge: "Hosted route",
                symbolName: "terminal"
            )
        }

        if chatStore.selectedModelOption?.isIronclawMobileRuntime == true {
            return ProofCapsuleViewModel(
                state: .private_,
                title: "Phone agent route",
                detail: "IronClaw Mobile runs on the phone. Switch back to a NEAR Private model whenever you need signed private-route proof.",
                badge: "On-device agent",
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
        return shouldFetchHomeAttestation ? "Fetch proof" : "Open Security"
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

    private var hasProjectSearchResults: Bool {
        !filteredProjectContextMatches.isEmpty
    }

    private var hasVisibleProjects: Bool {
        !filteredProjects.isEmpty
    }

    private var allHomeHasVisibleContent: Bool {
        !filteredConversations.isEmpty || hasVisibleProjects || hasProjectSearchResults
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
            setupPlan: savedSetupState?.plan
        )
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
                SidebarSearchField(text: $searchText, prompt: "Search chats")
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                LazyVStack(spacing: 14) {
                    if searchQuery.isEmpty, !shouldPrioritizeSetupOverToday {
                        HomeOrchestrationSurface(
                            plan: homeOrchestrationPlan,
                            onAction: runHomeOrchestrationAction
                        )
                        .padding(.top, 12)
                    }

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

                    if hasProjectSearchResults {
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

                    if hasVisibleProjects {
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

                    if filteredConversations.isEmpty {
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
                        } else if !allHomeHasVisibleContent {
                            VStack(spacing: 14) {
                                ClaudeHomeEmptyState(
                                    title: searchQuery.isEmpty ? "Verifiably Yours." : "No matching chats or projects",
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

                    if !filteredConversations.isEmpty {
                        if hasVisibleProjects || hasProjectSearchResults {
                            HomeSectionHeader(title: searchQuery.isEmpty ? "Chats" : "Chat matches")
                                .padding(.horizontal, 16)
                        }

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
                        .padding(.top, pendingSetupLaunchCard == nil ? 0 : 4)
                        .padding(.horizontal, 16)
                        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.appBorder, lineWidth: 1)
                        }
                        .padding(.bottom, 28)
                    }
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
            ProjectFilesView()
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

    private var filterCounts: [HomeFilter: Int] {
        [
            .all: chatStore.allVisibleConversations.count,
            .shared: chatStore.sharedWithMe.count,
            .archived: chatStore.archivedConversations.count + chatStore.archivedProjects.count
        ]
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
