import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var searchText = ""
    @State private var selectedHomeFilter: HomeFilter = .all
    @State private var showingNewProject = false
    @State private var showingProjectFiles = false
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
        guard !searchQuery.isEmpty else { return chatStore.projects }
        return chatStore.projects.filter { projectMatchesSearch($0) }
    }

    private var filteredProjectContextMatches: [HomeProjectContextMatch] {
        HomeSearchIndex.projectContextMatches(query: searchQuery, projects: chatStore.projects)
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
        return SetupLaunchCardState(
            accountID: accountID,
            profile: profile,
            plan: AppSetupPlan(profile: profile, readiness: setupReadinessSnapshot)
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
        List {
            Section {
                WorkspaceCommandHeader(
                    title: "NEAR Private Chat",
                    subtitle: "Ready to answer, research, or take action.",
                    onNewChat: openNewChat
                )
                .workspaceListRow()

                SidebarSearchField(text: $searchText, prompt: "Search chats, projects, and sources")
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 5, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                HomeFilterStrip(
                    selectedFilter: $selectedHomeFilter,
                    counts: filterCounts,
                    onSelect: selectHomeFilter
                )
                .workspaceListRow(top: 4, bottom: 8)
            }
            .listSectionSeparator(.hidden)

            if let pendingSetupLaunchCard {
                Section {
                    SetupLaunchCard(
                        plan: pendingSetupLaunchCard.plan,
                        onPrimaryAction: { openPendingSetupLaunchCard(pendingSetupLaunchCard) },
                        onDismiss: { dismissPendingSetupLaunchCard(pendingSetupLaunchCard) }
                    )
                    .workspaceListRow(top: 12, bottom: 4)
                }
                .listSectionSeparator(.hidden)
            }

            if selectedHomeFilter == .all, !resumeConversations.isEmpty {
                Section {
                    HomeSectionHeader(title: "Resume")
                        .workspaceListRow(top: 16, bottom: 5)

                    HomeRecentsRow(
                        conversations: resumeConversations,
                        projectNameForConversation: projectName(for:),
                        onOpenConversation: openConversation
                    )
                    .workspaceListRow(top: 0, bottom: 3)
                }
                .listSectionSeparator(.hidden)
            }

            if selectedHomeFilter == .all, !filteredProjects.isEmpty {
                Section {
                    HomeSectionHeader(
                        title: "Projects",
                        actionTitle: "New",
                        actionSymbolName: "plus",
                        action: { showingNewProject = true }
                    )
                    .workspaceListRow(top: 16, bottom: 5)

                    ForEach(filteredProjects) { project in
                        Button {
                            chatStore.selectProject(project)
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
                                chatStore.selectProject(project)
                            } label: {
                                Label("Open", systemImage: "folder")
                            }
                            Button {
                                chatStore.selectProject(project)
                                showingProjectFiles = true
                            } label: {
                                Label("Project Context", systemImage: "folder.badge.gearshape")
                            }
                            Button {
                                chatStore.selectProject(project)
                                openNewChat()
                            } label: {
                                Label("New Chat", systemImage: "square.and.pencil")
                            }
                            Divider()
                            Button {
                                editingProject = project
                            } label: {
                                Label("Rename / Style", systemImage: "paintpalette")
                            }
                        }
                        .workspaceListRow()
                    }
                }
                .listSectionSeparator(.hidden)
            }

            if selectedHomeFilter == .all, !filteredProjectContextMatches.isEmpty {
                Section {
                    HomeSectionHeader(title: "Project Context")
                        .workspaceListRow(top: 16, bottom: 5)

                    ForEach(filteredProjectContextMatches) { match in
                        Button {
                            openProjectContext(match.project)
                        } label: {
                            ProjectContextSearchRow(match: match)
                        }
                        .buttonStyle(.plain)
                        .workspaceListRow()
                    }
                }
                .listSectionSeparator(.hidden)
            }

            if selectedHomeFilter == .all,
               filteredConversations.isEmpty,
               filteredProjects.isEmpty,
               filteredProjectContextMatches.isEmpty {
                Section {
                    if let emptyHomeSetupState {
                        SavedSetupHomeCard(
                            plan: emptyHomeSetupState.plan,
                            onPrimaryAction: { reopenSavedSetup(emptyHomeSetupState) },
                            onChangeSetup: onRunSetupAgain
                        )
                        .workspaceListRow(top: 18, bottom: 8)
                    } else {
                        ContentUnavailableView(
                            searchQuery.isEmpty ? (chatStore.selectedProject == nil ? "No chats" : "No project chats") : "No matching chats",
                            systemImage: "bubble.left.and.bubble.right",
                            description: searchQuery.isEmpty ? nil : Text("Try a project name, file, link, note, or chat title.")
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            } else if selectedHomeFilter == .all {
                ForEach(conversationGroups, id: \.title) { group in
                    Section {
                        HomeSectionHeader(title: group.title)
                            .workspaceListRow(top: 18, bottom: 5)

                        ForEach(group.conversations) { conversation in
                            Button {
                                openConversation(conversation)
                            } label: {
                                ConversationRow(
                                    conversation: conversation,
                                    isSelected: conversation.id == chatStore.selectedConversation?.id
                                )
                            }
                            .buttonStyle(.plain)
                            .workspaceListRow()
                            .swipeActions(edge: .leading) {
                                Button {
                                    chatStore.togglePinConversation(conversation)
                                } label: {
                                    Label(conversation.isPinned ? "Unpin" : "Pin", systemImage: conversation.isPinned ? "pin.slash" : "pin")
                                }
                                .tint(.brandBlue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    chatStore.archiveConversation(conversation)
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(.secondary)

                                Button(role: .destructive) {
                                    chatStore.requestDeleteConversation(conversation)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }

            if selectedHomeFilter == .shared {
                Section {
                    HomeSectionHeader(title: "Shared")
                        .workspaceListRow(top: 16, bottom: 5)

                    if chatStore.isLoadingSharedWithMe && chatStore.sharedWithMe.isEmpty {
                        LoadingHomeRow(title: "Loading shared conversations")
                            .workspaceListRow()
                    } else if filteredSharedWithMe.isEmpty {
                        ContentUnavailableView(
                            searchQuery.isEmpty ? "No shared conversations" : "No matching shared conversations",
                            systemImage: "person.2.slash"
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else {
                        if searchQuery.isEmpty {
                            SharedAccessSummaryCard(conversationCount: filteredSharedWithMe.count)
                                .workspaceListRow(top: 0, bottom: 8)
                        }
                        ForEach(filteredSharedWithMe) { item in
                            NavigationLink(value: item) {
                                SharedWithMeRow(item: item)
                            }
                            .workspaceListRow()
                        }
                    }
                }
                .listSectionSeparator(.hidden)
            }

            if selectedHomeFilter == .archived {
                Section {
                    HomeSectionHeader(title: "Archived")
                        .workspaceListRow(top: 16, bottom: 5)

                    if filteredArchivedConversations.isEmpty {
                        ContentUnavailableView(
                            searchQuery.isEmpty ? "No archived conversations" : "No matching archived conversations",
                            systemImage: "archivebox"
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredArchivedConversations) { conversation in
                            Button {
                                openConversation(conversation)
                            } label: {
                                ConversationRow(
                                    conversation: conversation,
                                    isSelected: conversation.id == chatStore.selectedConversation?.id
                                )
                            }
                            .buttonStyle(.plain)
                            .workspaceListRow()
                            .swipeActions(edge: .trailing) {
                                Button {
                                    chatStore.unarchiveConversation(conversation)
                                } label: {
                                    Label("Unarchive", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.brandBlue)

                                Button(role: .destructive) {
                                    chatStore.requestDeleteConversation(conversation)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(HomeSurfaceBackground())
        .platformInlineNavigationTitle()
        .refreshable {
            await chatStore.refreshConversations()
        }
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
        .navigationDestination(for: SharedConversationInfo.self) { item in
            SharedWithMePreviewView(item: item)
                .environmentObject(chatStore)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Chats")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            ToolbarItem(placement: .automatic) {
                AccountToolbarButton(onRunSetupAgain: onRunSetupAgain)
            }
        }
        .task {
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
            .archived: chatStore.archivedConversations.count
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

    private func projectName(for conversation: ConversationSummary) -> String? {
        if let selectedProject = chatStore.selectedProject,
           selectedProject.conversationIDs.contains(conversation.id) {
            return selectedProject.name
        }
        return chatStore.projects.first { $0.conversationIDs.contains(conversation.id) }?.name
    }

    private func projectSubtitle(_ project: ChatProject) -> String {
        var parts: [String] = []
        if let chats = optionalCountLabel(project.conversationIDs.count, singular: "chat") {
            parts.append(chats)
        }
        parts.append(contentsOf: contextSubtitleParts(project))
        return parts.isEmpty ? "Ready for sources" : parts.joined(separator: " · ")
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

    private func reopenSavedSetup(_ state: SetupLaunchCardState) {
        AppHaptics.lightImpact()
        chatStore.applySetupProfile(state.profile)
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

