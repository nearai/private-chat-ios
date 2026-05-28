import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var searchText = ""
    @State private var selectedHomeFilter: HomeFilter = .all
    @State private var showingNewProject = false
    @State private var showingProjectFiles = false
    @State private var showingAccountSettings = false
    @State private var isSearchVisible = false
    @State private var editingProject: ChatProject?
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
            selectedProjectName: chatStore.selectedProject?.name
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
        let plan = AppSetupPlan(profile: profile, readiness: setupReadinessSnapshot)
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

    var body: some View {
        VStack(spacing: 0) {
            ClaudeHomeTopBar(
                displayName: sessionStore.displayName,
                isSearchVisible: isSearchVisible,
                onAccount: { showingAccountSettings = true },
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
                if filteredConversations.isEmpty {
                    ClaudeHomeEmptyState(
                        title: searchQuery.isEmpty ? "Ask privately." : "No matching chats",
                        showsAction: searchQuery.isEmpty,
                        action: openNewChat
                    )
                    .frame(maxWidth: .infinity)
                    .containerRelativeFrame(.vertical)
                } else {
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
                    .padding(.bottom, 28)
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
        .sheet(isPresented: $showingAccountSettings) {
            AccountSettingsView(onRunSetupAgain: onRunSetupAgain)
                .environmentObject(sessionStore)
                .environmentObject(chatStore)
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

    private func openConversation(_ conversation: ConversationSummary) {
        guard !chatStore.isStreaming else {
            chatStore.bannerMessage = "Finish or cancel the current response before switching chats."
            return
        }
        chatStore.selectConversation(conversation)
        onOpenChat()
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
        switch recommendation.kind {
        case .openCloud, .openAgent:
            AppHaptics.lightImpact()
            showingAccountSettings = true
        case .useAutoCouncil:
            AppHaptics.selection()
            chatStore.useDefaultCouncilLineup()
        case .openSecurity, .rerunSetup:
            break
        }
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
