import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


struct AppShellView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @State private var showingCompactChat = false
    let onRunSetupAgain: () -> Void

    init(onRunSetupAgain: @escaping () -> Void = {}) {
        self.onRunSetupAgain = onRunSetupAgain
    }

    var body: some View {
        NavigationStack {
            ConversationListView(
                onOpenChat: { showingCompactChat = true },
                onStartNewChat: { showingCompactChat = true },
                onRunSetupAgain: onRunSetupAgain
            )
            .navigationDestination(isPresented: $showingCompactChat) {
                ChatView()
                    .navigationTitle(chatStore.selectedConversationTitle)
                    .platformInlineNavigationTitle()
            }
        }
        .tint(.brandBlue)
        .onChange(of: chatStore.openSelectedConversationToken) { _, token in
            if token != nil {
                showingCompactChat = true
            }
        }
        .confirmationDialog(
            "Delete this conversation?",
            isPresented: deleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            if let conversation = chatStore.pendingDeleteConversation {
                Button("Archive Instead") {
                    chatStore.archiveConversation(conversation)
                    chatStore.cancelPendingDelete()
                }
                Button("Delete Permanently", role: .destructive) {
                    chatStore.confirmPendingDelete()
                }
            }
            Button("Cancel", role: .cancel) {
                chatStore.cancelPendingDelete()
            }
        } message: {
            if let conversation = chatStore.pendingDeleteConversation {
                Text("\"\(conversation.title)\" will be permanently deleted. Archive keeps it recoverable.")
            }
        }
        .confirmationDialog(
            "Open external shortcut?",
            isPresented: externalDeepLinkConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Open Shortcut") {
                chatStore.confirmPendingExternalDeepLink()
            }
            Button("Cancel", role: .cancel) {
                chatStore.cancelPendingExternalDeepLink()
            }
        } message: {
            Text(chatStore.pendingExternalDeepLinkDescription)
        }
        .sheet(item: $chatStore.pendingHostedHandoffPreflight) { preflight in
            HostedHandoffPreflightSheet(preflight: preflight)
                .environmentObject(chatStore)
                .platformMediumDetent()
        }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { chatStore.pendingDeleteConversation != nil },
            set: { isPresented in
                if !isPresented {
                    chatStore.cancelPendingDelete()
                }
            }
        )
    }

    private var externalDeepLinkConfirmationPresented: Binding<Bool> {
        Binding(
            get: { chatStore.pendingExternalDeepLink != nil },
            set: { isPresented in
                if !isPresented {
                    chatStore.cancelPendingExternalDeepLink()
                }
            }
        )
    }
}

private struct ConversationListView: View {
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
        guard selectedHomeFilter == .all,
              searchQuery.isEmpty,
              let accountID = sessionStore.setupAccountID,
              UserSetupStorage.hasPendingLaunchCard(for: accountID),
              let profile = UserSetupStorage.load(for: accountID) else {
            return nil
        }
        return SetupLaunchCardState(
            accountID: accountID,
            profile: profile,
            plan: AppSetupPlan(profile: profile, readiness: setupReadinessSnapshot)
        )
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
                    ContentUnavailableView(
                        searchQuery.isEmpty ? (chatStore.selectedProject == nil ? "No chats" : "No project chats") : "No matching chats",
                        systemImage: "bubble.left.and.bubble.right",
                        description: searchQuery.isEmpty ? nil : Text("Try a project name, file, link, note, or chat title.")
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
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

struct SharedConversationSheet: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("private.near.ai/c/conv_...", text: $linkText)
                        .textFieldStyle(.plain)
                        .tokenInputTraits()
                        .padding(12)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 10) {
                        Button {
                            Task { await chatStore.openSharedConversation(from: linkText) }
                        } label: {
                            Label("Open", systemImage: "arrow.down.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.brandBlue)
                        .disabled(linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatStore.isLoadingSharedPreview)

                        Button {
                            linkText = ""
                            chatStore.closeSharedPreview()
                        } label: {
                            Image(systemName: "xmark")
                                .frame(width: 40, height: 34)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Clear")
                    }

                    if chatStore.isLoadingSharedPreview {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading conversation")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()

                Divider()

                if let snapshot = chatStore.sharedPreview {
                    SharedConversationPreview(snapshot: snapshot)
                } else {
                    ContentUnavailableView(
                        "Open a shared conversation",
                        systemImage: "link",
                        description: Text("Paste a public or shared NEAR AI Private Chat link.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Shared Link")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct SharedConversationPreview: View {
    @EnvironmentObject private var chatStore: ChatStore
    let snapshot: SharedConversationSnapshot

    private var transcript: String {
        snapshot.messages
            .map { "\($0.role == .user ? "You" : $0.modelDisplayName): \($0.text)" }
            .joined(separator: "\n\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.brandBlue)
                        .frame(width: 34, height: 34)
                        .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.conversation.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text("\(snapshot.messages.count) messages")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                ChipFlowLayout(spacing: 7, lineSpacing: 7) {
                    SharedAccessPill(
                        title: snapshot.accessBadgeTitle,
                        symbolName: snapshot.canWrite ? "square.and.pencil" : "eye",
                        tint: snapshot.canWrite ? Color.primaryAction : Color.orange
                    )
                    SharedAccessPill(
                        title: snapshot.sourceBadgeTitle,
                        symbolName: "link",
                        tint: Color.textSecondary
                    )
                }

                Text(snapshot.accessDescription)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.textSecondary)

                Text(snapshot.sourceDescription)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        previewActions
                    }
                    VStack(spacing: 10) {
                        previewActions
                    }
                }
            }
            .padding(16)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Divider()
                .padding(.top, 16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if snapshot.messages.isEmpty {
                        ContentUnavailableView("No messages", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else {
                        ForEach(snapshot.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
            }
        }
        .background(Color.appBackground)
    }

    @ViewBuilder
    private var previewActions: some View {
        if snapshot.canWrite {
            SharedPreviewActionButton(title: "Open chat", systemImage: "square.and.pencil", isPrimary: true) {
                chatStore.openSharedPreviewForWriting()
            }
            .accessibilityLabel("Open shared conversation for writing")
        }

        SharedPreviewActionButton(title: "Copy & Continue", systemImage: "doc.on.doc", isPrimary: false) {
            chatStore.cloneSharedPreviewToChat()
        }
        .accessibilityLabel("Copy and Continue")

        SharedPreviewActionButton(title: "Copy text", systemImage: "doc.text", isPrimary: false) {
            Clipboard.copy(transcript)
        }
        .accessibilityLabel("Copy Transcript")
    }
}

private struct SharedWithMeView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SharedAccessSummaryCard(conversationCount: chatStore.sharedWithMe.count)
                        .padding(.vertical, 4)
                }

                Section("Conversations") {
                    if chatStore.isLoadingSharedWithMe && chatStore.sharedWithMe.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading shared conversations")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if chatStore.sharedWithMe.isEmpty {
                        ContentUnavailableView("No shared conversations", systemImage: "person.2.slash")
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(chatStore.sharedWithMe) { item in
                            NavigationLink(value: item) {
                                SharedWithMeRow(item: item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shared")
            .platformInlineNavigationTitle()
            .refreshable {
                await chatStore.refreshSharedWithMe()
            }
            .navigationDestination(for: SharedConversationInfo.self) { item in
                SharedWithMePreviewView(item: item)
                    .environmentObject(chatStore)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await chatStore.refreshSharedWithMe() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(chatStore.isLoadingSharedWithMe)
                    .accessibilityLabel("Refresh shared conversations")
                }
            }
            .task {
                await chatStore.refreshSharedWithMe(showErrors: false)
            }
            .onChange(of: chatStore.openSelectedConversationToken) { _, token in
                if token != nil {
                    dismiss()
                }
            }
        }
        .platformLargeDetent()
    }
}

private struct SharedWithMeRow: View {
    let item: SharedConversationInfo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.canWrite ? "square.and.pencil" : "eye")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.canWrite ? Color.primaryAction : Color.orange)
                .frame(width: 32, height: 32)
                .background(
                    (item.canWrite ? Color.primaryAction : Color.orange).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(item.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    SharedAccessPill(
                        title: item.accessBadgeTitle,
                        symbolName: item.canWrite ? "square.and.pencil" : "eye",
                        tint: item.canWrite ? Color.primaryAction : Color.orange
                    )
                }

                Text(item.sourceLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let createdAt = item.createdAt {
            parts.append(Date(timeIntervalSince1970: createdAt).formatted(date: .abbreviated, time: .omitted))
        }
        if let error = item.error, !error.isEmpty {
            parts.append(error)
        }
        if parts.isEmpty {
            return item.canWrite ? "Open in place or fork a private copy." : "Copy and Continue makes a private draft."
        }
        return parts.joined(separator: " · ")
    }
}

private struct SharedWithMePreviewView: View {
    @EnvironmentObject private var chatStore: ChatStore
    let item: SharedConversationInfo

    var body: some View {
        Group {
            if chatStore.isLoadingSharedPreview {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Opening shared conversation")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            } else if let snapshot = chatStore.sharedPreview,
                      snapshot.conversation.id == item.conversationID {
                SharedConversationPreview(snapshot: snapshot)
            } else {
                ContentUnavailableView(
                    "Could not open conversation",
                    systemImage: "exclamationmark.triangle",
                    description: Text(item.error ?? "Pull to refresh or try again.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            }
        }
        .navigationTitle(item.displayTitle)
        .platformInlineNavigationTitle()
        .task(id: item.conversationID) {
            await chatStore.openSharedConversation(
                from: item.conversationID,
                knownCanWrite: item.canWrite,
                sourceLabel: item.sourceLabel
            )
        }
    }
}

private struct SharedAccessSummaryCard: View {
    let conversationCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.2")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 34, height: 34)
                    .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Shared with you")
                        .font(.headline)
                    Text("Read-only chats stay locked. Editable shares open in place when the owner granted write access.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ChipFlowLayout(spacing: 7, lineSpacing: 7) {
                SharedAccessPill(title: "Read-only", symbolName: "eye", tint: Color.orange)
                SharedAccessPill(title: "Can edit", symbolName: "square.and.pencil", tint: Color.primaryAction)
                SharedAccessPill(title: conversationCountLabel, symbolName: "bubble.left.and.bubble.right", tint: Color.textSecondary)
            }
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var conversationCountLabel: String {
        conversationCount == 1 ? "1 conversation" : "\(conversationCount) conversations"
    }
}

private struct SharedAccessPill: View {
    let title: String
    let symbolName: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct SharedPreviewActionButton: View {
    let title: String
    let systemImage: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isPrimary ? Color.brandBlack : Color.primaryAction)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    isPrimary ? Color.brandSky : Color.appSecondaryBackground,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

struct EmptyChatView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var sessionStore: SessionStore

    private struct EmptyPromptSuggestion: Identifiable {
        var id: String { title }
        let title: String
        let symbolName: String
        let prompt: String
    }

    private var emptyHeroSubtitle: String {
        if let project = chatStore.selectedProject {
            let contextCount = chatStore.activeProjectContextAttachments.count + chatStore.activeProjectContextLinks.count
            return contextCount > 0 ? "\(project.name) context is ready." : "\(project.name) is selected."
        }
        if chatStore.selectedModelOption?.isIronclawHostedModel == true {
            return chatStore.ironclawRemoteWorkstationAvailable ? "Hosted agent ready." : "Connect hosted IronClaw to run workstation tasks."
        }
        if chatStore.selectedModelOption?.isIronclawMobileRuntime == true {
            return chatStore.ironclawRemoteWorkstationAvailable ? "Hosted agent ready." : "Mobile agent ready."
        }
        if let setupProfileWithGoal {
            return setupProfileWithGoal.emptyStateSubtitle
        }
        if chatStore.isCouncilModeEnabled {
            return "Council is ready to compare answers."
        }
        if chatStore.researchModeEnabled && !chatStore.selectedRouteUsesNearCloud {
            return "Search current sources."
        }
        if let setupProfile {
            return setupProfile.emptyStateSubtitle
        }
        return "Ask normally. NEAR picks web, project context, or an agent when needed."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                PrivacySeal(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What do you want to ask?")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(emptyHeroSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(emptyPromptSuggestions) { suggestion in
                        suggestionButton(suggestion)
                    }
                }
                .padding(.vertical, 1)

                Menu {
                    ForEach(emptyPromptSuggestions) { suggestion in
                        Button {
                            AppHaptics.selection()
                            chatStore.draft = suggestion.prompt
                        } label: {
                            Label(suggestion.title, systemImage: suggestion.symbolName)
                        }
                    }
                } label: {
                    Label("Prompt examples", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(height: 34)
                        .padding(.horizontal, 10)
                        .background(Color.secondarySurface, in: Capsule())
                }
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func suggestionButton(_ suggestion: EmptyPromptSuggestion) -> some View {
        Button {
            AppHaptics.selection()
            chatStore.draft = suggestion.prompt
        } label: {
            Label(suggestion.title, systemImage: suggestion.symbolName)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.secondarySurface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use suggestion, \(suggestion.title)")
        .accessibilityHint("Fills the composer without sending.")
    }

    private var emptyPromptSuggestions: [EmptyPromptSuggestion] {
        if chatStore.selectedProviderDisplayName == "IronClaw" {
            return [
                EmptyPromptSuggestion(title: "Review repo", symbolName: "chevron.left.forwardslash.chevron.right", prompt: "Agent mission: Review this repo and identify the highest-impact fixes: "),
                EmptyPromptSuggestion(title: "Patch safely", symbolName: "wrench.and.screwdriver", prompt: "Agent mission: Implement this change, run focused tests, and report changed files: "),
                EmptyPromptSuggestion(title: "Research issue", symbolName: "globe", prompt: "Agent mission: Research the latest context and turn it into next actions: ")
            ]
        }

        if let project = chatStore.selectedProject {
            let projectName = project.name
            return [
                EmptyPromptSuggestion(title: "Brief project", symbolName: "folder.badge.gearshape", prompt: "Use \(projectName)'s files, links, and notes to brief me on the next best move."),
                EmptyPromptSuggestion(title: "Find blockers", symbolName: "exclamationmark.triangle", prompt: "Review \(projectName)'s context and identify the highest-risk blockers, missing facts, and next checks."),
                EmptyPromptSuggestion(title: "Draft next step", symbolName: "arrow.forward.circle", prompt: "Turn \(projectName)'s current context into a concise next-step plan I can act on.")
            ]
        }

        if let setupProfileWithGoal {
            return setupProfileWithGoal.emptyStatePromptSuggestions.map {
                EmptyPromptSuggestion(title: $0.title, symbolName: $0.symbolName, prompt: $0.prompt)
            }
        }

        if chatStore.isCouncilModeEnabled {
            return [
                EmptyPromptSuggestion(title: "Compare models", symbolName: "square.grid.2x2", prompt: "Compare Anthropic and OpenAI for this task: "),
                EmptyPromptSuggestion(title: "Disagree", symbolName: "arrow.triangle.branch", prompt: "Ask the council to identify strongest agreements and disagreements on: "),
                EmptyPromptSuggestion(title: "Decision brief", symbolName: "doc.text.magnifyingglass", prompt: "Give me a decision-ready brief with tradeoffs and next steps: ")
            ]
        }

        if chatStore.researchModeEnabled {
            return [
                EmptyPromptSuggestion(title: "Latest AI", symbolName: "globe", prompt: "What is the latest important news in AI? Include sources and dates."),
                EmptyPromptSuggestion(title: "Compare views", symbolName: "square.grid.2x2", prompt: "Compare Anthropic and OpenAI for this task using current sources: "),
                EmptyPromptSuggestion(title: "Brief me", symbolName: "doc.text.magnifyingglass", prompt: "Research this and give me a decision-ready brief with citations: ")
            ]
        }

        if let setupProfile {
            return setupProfile.emptyStatePromptSuggestions.map {
                EmptyPromptSuggestion(title: $0.title, symbolName: $0.symbolName, prompt: $0.prompt)
            }
        }

        return [
            EmptyPromptSuggestion(title: "Plan next move", symbolName: "arrow.forward.circle", prompt: "Help me turn this into the next concrete action: "),
            EmptyPromptSuggestion(title: "Research latest", symbolName: "globe", prompt: "Research the latest context and give me the decision-ready version: "),
            EmptyPromptSuggestion(title: "Compare options", symbolName: "square.grid.2x2", prompt: "Compare the strongest options, tradeoffs, and recommendation for: ")
        ]
    }

    private var setupProfile: UserSetupProfile? {
        guard let accountID = sessionStore.setupAccountID else { return nil }
        return UserSetupStorage.load(for: accountID)
    }

    private var setupProfileWithGoal: UserSetupProfile? {
        guard let setupProfile, !setupProfile.normalizedGoalText.isEmpty else { return nil }
        return setupProfile
    }
}
