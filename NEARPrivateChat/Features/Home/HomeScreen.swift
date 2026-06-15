import SwiftUI

enum HomeLaunchFollowUp: Equatable {
    case project
    case council
}

struct HomeScreen: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var conversationStore: ConversationStore
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var shareStore: ShareStore
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var briefingStore: BriefingStore
    @StateObject var homeStore = HomeStore()
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

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ClaudeHomeTopBar(
                    displayName: sessionStore.displayName,
                    isSearchVisible: homeStore.isSearchVisible,
                    onAccount: { openAccountSettings() },
                    onSearch: toggleSearch,
                    onNewChat: openNewChat,
                    onDashboard: { homeStore.showingDashboard = true }
                )

                if homeStore.isSearchVisible || !homeStore.searchText.isEmpty {
                    SidebarSearchField(text: $homeStore.searchText, prompt: "Search chats, projects, and sources")
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
                        homeDefaultStarterSurface

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
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.top, pendingSetupLaunchCard == nil ? 12 : 0)
                                }
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
                                    HomeInboxEmptyState(
                                        title: "No results",
                                        subtitle: "No chats, Projects, or sources match \"\(searchQuery)\". Clear search or try fewer words.",
                                        symbolName: "magnifyingglass",
                                        actionTitle: "Clear search",
                                        actionSymbolName: "xmark.circle",
                                        action: clearHomeSearch
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.top, 18)
                                    .frame(maxWidth: .infinity, alignment: .top)
                                    .containerRelativeFrame(.vertical, alignment: .top)
                                }
                            }
                        }
                    } else {
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
                                    action: searchQuery.isEmpty ? { homeStore.showingNewProject = true } : nil
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
                                                isSelected: projectStore.selectedProjectID == project.id,
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
                                                homeStore.editingProject = project
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
                                    HomeInboxEmptyState(
                                        title: "No results",
                                        subtitle: "No chats, Projects, or sources match \"\(searchQuery)\". Clear search or try fewer words.",
                                        symbolName: "magnifyingglass",
                                        actionTitle: "Clear search",
                                        actionSymbolName: "xmark.circle",
                                        action: clearHomeSearch
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.top, 18)
                                    .frame(maxWidth: .infinity, alignment: .top)

                                    // v2: HomeTrustReadinessCard removed — trust state
                                    // lives inside the chat thread, not on Home.
                                }
                                .containerRelativeFrame(.vertical, alignment: .top)
                            }
                        }

                        if homeInboxSectionPlan.showsConversations {
                            fullChatHistorySection
                        }

                        sharedWithMeSection

                        archivedProjectsSection

                        archivedConversationsSection

                        filteredEmptyStateSection
                    }

                    if shouldShowDefaultWorkSurface {
                        Color.clear
                            .frame(height: 132)
                    }
                }
            }
            .refreshable {
                await chatStore.refreshConversations()
            }

                Spacer(minLength: 0)
            }

            if shouldShowDefaultWorkSurface {
                homePromptCaptureCard
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(HomeSurfaceBackground().ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $homeStore.showingNewProject) {
            NewProjectView()
                .environmentObject(projectStore)
        }
        .sheet(isPresented: $homeStore.showingProjectFiles, onDismiss: {
            resumePendingHomeLaunchIfPossible(after: .project)
        }) {
            ProjectFilesView(
                projectContextRoutePreview: { chatStore.projectContextRoutePreview },
                addProjectAttachment: { url in await chatStore.addProjectAttachment(from: url) },
                removeProjectAttachment: { attachment in chatStore.removeProjectAttachment(attachment) },
                onOpenConversation: { conversation in
                    homeStore.showingProjectFiles = false
                    DispatchQueue.main.async {
                        openConversation(conversation)
                    }
                },
                onStagePrompt: { prompt in
                    homeStore.showingProjectFiles = false
                    DispatchQueue.main.async {
                        stageProjectPrompt(prompt)
                    }
                }
            )
            .environmentObject(projectStore)
        }
        .sheet(isPresented: $homeStore.showingHomeCouncilPicker, onDismiss: {
            resumePendingHomeLaunchIfPossible(after: .council)
        }) {
            ModelPickerView(
                openingCouncil: true,
                onOpenNearCloudKeys: {
                    openAccountSettings(deepLink: .nearCloudKeys)
                }
            )
                .environmentObject(chatStore)
        }
        .sheet(item: $homeStore.editingProject) { project in
            EditProjectView(project: project)
                .environmentObject(projectStore)
        }
        .sheet(isPresented: $homeStore.showingAccountSettings, onDismiss: {
            homeStore.accountSettingsDeepLink = nil
        }) {
            AccountSettingsView(
                initialDeepLink: homeStore.accountSettingsDeepLink,
                onRunSetupAgain: onRunSetupAgain,
                isCurrentChatEmpty: { chatStore.selectedConversation == nil && chatStore.transcriptStore.messages.isEmpty }
            )
                .environmentObject(sessionStore)
        }
        .sheet(isPresented: $homeStore.showingSecurity) {
            SecurityView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $homeStore.showingNewBriefing) {
            BriefingEditorSheet(
                briefing: nil,
                onSave: { briefingStore.add($0) },
                onDelete: { briefingStore.remove($0) }
            )
        }
        .fullScreenCover(isPresented: $homeStore.showingDashboard, onDismiss: performDashboardExit) {
            DashboardScreen(
                store: briefingStore,
                onOpenBriefing: { briefing in
                    homeStore.pendingDashboardExit = .openBriefing(briefing)
                    homeStore.showingDashboard = false
                },
                onNewBriefing: {
                    homeStore.pendingDashboardExit = .newBriefing
                    homeStore.showingDashboard = false
                },
                onAsk: { text in
                    homeStore.pendingDashboardExit = .ask(text)
                    homeStore.showingDashboard = false
                },
                onClose: { homeStore.showingDashboard = false }
            )
        }
        .fullScreenCover(item: $homeStore.openedBriefing) { briefing in
            if shouldOpenBriefingManagementDetail(briefing) {
                NavigationStack {
                    BriefingDetailView(
                        store: briefingStore,
                        briefing: briefing,
                        onFollowUp: { question in
                            chatStore.draft = question
                            homeStore.openedBriefing = nil
                        },
                        onDelivered: {
                            // The detail opened because the briefing had no result.
                            // It just delivered one, so re-present to switch the
                            // cover to the result thread. Deferred to avoid
                            // re-presenting while the cover is mid-update.
                            guard let updated = briefingStore.briefings.first(where: { $0.id == briefing.id }) else { return }
                            homeStore.openedBriefing = nil
                            DispatchQueue.main.async { homeStore.openedBriefing = updated }
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                homeStore.openedBriefing = nil
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.title3.weight(.semibold))
                            }
                            .accessibilityLabel("Close")
                        }
                    }
                }
            } else {
                ThreadedBriefingView(
                    briefing: briefing,
                    store: briefingStore,
                    onAskFollowUp: { question, context, proxyModelID in
                        await chatStore.answerBriefingFollowUp(
                            question: question,
                            context: context,
                            briefing: briefing,
                            viaProxyModelID: proxyModelID
                        )
                    }
                ) { homeStore.openedBriefing = nil }
            }
        }
        .navigationDestination(for: SharedConversationInfo.self) { item in
            SharedWithMePreviewView(
                item: item,
                onOpenForWriting: { snapshot in
                    chatStore.openSharedPreviewForWriting(snapshot)
                },
                onCopyAndContinue: { snapshot in
                    chatStore.cloneConversation(snapshot.conversation)
                }
            )
            .environmentObject(shareStore)
        }
        .task {
            homeStore.resetDefaultFilter()
            if shareStore.sharedWithMe.isEmpty {
                await shareStore.refreshSharedWithMe(showErrors: false)
            }
        }
    }

    private func clearHomeSearch() {
        homeStore.searchText = ""
        homeStore.isSearchVisible = false
        homeStore.resetDefaultFilter()
    }

    private func shouldOpenBriefingManagementDetail(_ briefing: Briefing) -> Bool {
        let current = briefingStore.briefings.first(where: { $0.id == briefing.id }) ?? briefing
        return current.status == .failed || current.latestResult == nil
    }

}
