import SwiftUI

extension HomeScreen {
    var homeTodayFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeFeedScopeStrip(
                selectedScope: $homeStore.selectedFeedScope,
                counts: homeFeedScopeCounts
            )

            if shouldLeadHomeFeedWithChats {
                homeFeedChats
                homeFeedBriefings
            } else {
                homeFeedBriefings
                homeFeedChats
            }

            if visibleHomeFeedBriefings.isEmpty && visibleHomeFeedChats.isEmpty {
                VStack(spacing: 12) {
                    HomeInboxEmptyState(
                        title: emptyHomeFeedTitle,
                        subtitle: emptyHomeFeedSubtitle,
                        symbolName: homeStore.selectedFeedScope.symbolName,
                        actionTitle: emptyHomeFeedActionTitle,
                        actionSymbolName: emptyHomeFeedActionSymbolName,
                        action: { stageEmptyHomeFeedPrompt(scope: homeStore.selectedFeedScope) }
                    )

                    homeFeedEmptyStateActions
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var homeFeedEmptyStateActions: some View {
        let actionScopes = homeFeedStarterScopes
        if actionScopes.count > 1 {
            LazyVGrid(columns: [
                GridItem(.flexible(minimum: 0), spacing: 8),
                GridItem(.flexible(minimum: 0), spacing: 8)
            ], spacing: 8) {
                ForEach(actionScopes, id: \.self) { scope in
                    HomeFeedEmptyActionButton(
                        title: homeFeedStarterTitle(for: scope),
                        symbolName: homeFeedStarterSymbol(for: scope),
                        onTap: { stageEmptyHomeFeedPrompt(scope: scope) }
                    )
                }
            }
        } else if let singleScope = actionScopes.first {
            HomeFeedEmptyActionButton(
                title: homeFeedStarterTitle(for: singleScope),
                symbolName: homeFeedStarterSymbol(for: singleScope),
                onTap: { stageEmptyHomeFeedPrompt(scope: singleScope) }
            )
        }
    }

    private var homeFeedStarterScopes: [HomeFeedScope] {
        switch homeStore.selectedFeedScope {
        case .all:
            return [.briefings, .watchers]
        case .chats, .briefings, .watchers:
            return []
        }
    }

    private func homeFeedStarterTitle(for scope: HomeFeedScope) -> String {
        switch scope {
        case .all, .chats:
            return "Start chat"
        case .briefings:
            return "Draft briefing"
        case .watchers:
            return "Draft watcher"
        }
    }

    private func homeFeedStarterSymbol(for scope: HomeFeedScope) -> String {
        switch scope {
        case .all, .chats:
            return "square.and.pencil"
        case .briefings:
            return "doc.text"
        case .watchers:
            return "bell.badge"
        }
    }

    @ViewBuilder
    private var homeFeedBriefings: some View {
        if !visibleHomeFeedBriefings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HomeSectionHeader(title: "Scheduled")
                HomeBriefingFeedList(
                    briefings: visibleHomeFeedBriefings,
                    onOpen: { briefing in homeStore.openedBriefing = briefing }
                )
            }
        }
    }

    @ViewBuilder
    private var homeFeedChats: some View {
        if !visibleHomeFeedChats.isEmpty {
            HomeRecentsRow(
                conversations: visibleHomeFeedChats,
                previewTextForConversation: previewText(for:),
                hasSourceCueForConversation: hasSourceCue(for:),
                sourceSummaryForConversation: sourceSummary(for:),
                sourceChipsForConversation: sourceChips(for:),
                projectNameForConversation: projectName(for:),
                onOpenConversation: openConversation
            )
        }
    }

    private var shouldLeadHomeFeedWithChats: Bool {
        homeStore.selectedFeedScope == .all &&
            !visibleHomeFeedChats.isEmpty &&
            !visibleHomeFeedBriefings.isEmpty &&
            visibleHomeFeedBriefings.allSatisfy { $0.status == .failed || $0.lastFailureAt != nil }
    }

    var homeRecentChatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHeader(title: "Continue")
            HomeRecentsRow(
                conversations: resumeConversations,
                previewTextForConversation: previewText(for:),
                hasSourceCueForConversation: hasSourceCue(for:),
                sourceSummaryForConversation: sourceSummary(for:),
                sourceChipsForConversation: sourceChips(for:),
                projectNameForConversation: projectName(for:),
                onOpenConversation: openConversation
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    private var emptyHomeFeedTitle: String {
        switch homeStore.selectedFeedScope {
        case .all:
            return "Nothing live yet"
        case .briefings:
            return "No briefings yet"
        case .watchers:
            return "No watchers yet"
        case .chats:
            return "No chats yet"
        }
    }

    private var emptyHomeFeedSubtitle: String {
        switch homeStore.selectedFeedScope {
        case .all:
            return "Ask privately, then turn useful answers into briefings, trackers, or threads."
        case .briefings:
            return "Create a recurring digest from any topic, project, file, or search."
        case .watchers:
            return "Track prices, launches, accounts, releases, or any changing topic on a schedule."
        case .chats:
            return "Start a private thread; useful answers can become reusable work."
        }
    }

    private var emptyHomeFeedActionTitle: String {
        switch homeStore.selectedFeedScope {
        case .all, .chats:
            return "Start chat"
        case .briefings:
            return "Draft briefing"
        case .watchers:
            return "Draft watcher"
        }
    }

    private var emptyHomeFeedActionSymbolName: String {
        switch homeStore.selectedFeedScope {
        case .all, .chats:
            return "square.and.pencil"
        case .briefings:
            return "doc.text"
        case .watchers:
            return "bell.badge"
        }
    }

    var fullChatHistorySection: some View {
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
                            conversationStore.requestDeleteConversation(conversation)
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
    var sharedWithMeSection: some View {
        if homeInboxSectionPlan.showsSharedWithMe {
            VStack(spacing: 8) {
                HomeSectionHeader(
                    title: searchQuery.isEmpty ? "Shared With Me" : "Shared matches",
                    actionTitle: shareStore.isLoadingSharedWithMe ? nil : "Refresh",
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
    var archivedProjectsSection: some View {
        if homeInboxSectionPlan.showsArchivedProjects {
            VStack(spacing: 8) {
                HomeSectionHeader(title: searchQuery.isEmpty ? "Archived Projects" : "Archived project matches")

                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredArchivedProjects.enumerated()), id: \.element.id) { index, project in
                        Button {
                            projectStore.unarchiveProject(project)
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
                                projectStore.unarchiveProject(project)
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
    var archivedConversationsSection: some View {
        if homeInboxSectionPlan.showsArchivedConversations {
            VStack(spacing: 8) {
                HomeSectionHeader(title: searchQuery.isEmpty ? "Archived Chats" : "Archived chat matches")

                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredArchivedConversations.enumerated()), id: \.element.id) { index, conversation in
                        Button {
                            Task { await conversationStore.restoreArchivedConversation(conversation) }
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
                                Task { await conversationStore.restoreArchivedConversation(conversation) }
                            } label: {
                                Label("Restore Chat", systemImage: "arrow.uturn.backward")
                            }
                            Button(role: .destructive) {
                                conversationStore.requestDeleteConversation(conversation)
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
    var filteredEmptyStateSection: some View {
        if homeInboxSectionPlan.showsSharedEmptyState {
            HomeInboxEmptyState(
                title: shareStore.isLoadingSharedWithMe ? "Loading shared chats" : (searchQuery.isEmpty ? "No shared chats" : "No shared matches"),
                subtitle: sharedEmptyStateSubtitle,
                symbolName: "person.2.slash",
                isLoading: shareStore.isLoadingSharedWithMe,
                actionTitle: shareStore.isLoadingSharedWithMe ? nil : "Refresh",
                actionSymbolName: "arrow.clockwise",
                action: sharedRefreshAction
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        } else if homeInboxSectionPlan.showsArchivedEmptyState {
            HomeInboxEmptyState(
                title: searchQuery.isEmpty ? "No archived items" : "No archived matches",
                subtitle: searchQuery.isEmpty ? "Archived chats and Projects will collect here." : "Try another search or switch filters.",
                symbolName: "archivebox"
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    var sharedEmptyStateSubtitle: String {
        if shareStore.isLoadingSharedWithMe {
            return "Checking shared conversations."
        }
        if searchQuery.isEmpty {
            return "Conversations shared with you will collect here."
        }
        return "Try another search or switch filters."
    }

var sharedRefreshAction: (() -> Void)? {
        guard !shareStore.isLoadingSharedWithMe else { return nil }
        return {
            _ = Task { await shareStore.refreshSharedWithMe() }
        }
    }

}

struct HomeFeedEmptyActionButton: View {
    let title: String
    let symbolName: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label(title, systemImage: symbolName)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 10)
                .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.pill))
                .overlay {
                    RoundedRectangle.app(AppRadius.pill)
                        .stroke(Color.appBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .minimumTouchTarget()
    }
}
