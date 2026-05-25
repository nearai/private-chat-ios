import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private enum AppHaptics {
    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func lightImpact() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func mediumImpact() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

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

private enum HomeFilter: String, CaseIterable, Identifiable {
    case all
    case shared
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .shared: "Shared"
        case .archived: "Archived"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "bubble.left.and.bubble.right"
        case .shared: "person.2"
        case .archived: "archivebox"
        }
    }
}

private struct ConversationListView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var searchText = ""
    @State private var selectedHomeFilter: HomeFilter = .all
    @State private var showingNewProject = false
    @State private var showingProjectFiles = false
    @State private var showingAgentWorkspace = false
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

    private var conversationGroups: [(title: String, conversations: [ConversationSummary])] {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now).timeIntervalSince1970
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))?.timeIntervalSince1970 ?? todayStart

        let pinned = conversationsForDateGroups.filter(\.isPinned)
        let normal = conversationsForDateGroups.filter { !$0.isPinned }
        let today = normal.filter { ($0.createdAt ?? 0) >= todayStart }
        let yesterday = normal.filter {
            let createdAt = $0.createdAt ?? 0
            return createdAt < todayStart && createdAt >= yesterdayStart
        }
        let older = normal.filter { ($0.createdAt ?? 0) < yesterdayStart }

        return [
            ("Pinned", pinned),
            ("Today", today),
            ("Yesterday", yesterday),
            ("Earlier", older)
        ].filter { !$0.conversations.isEmpty }
    }

    var body: some View {
        List {
            Section {
                WorkspaceCommandHeader(
                    title: "NEAR Private Chat",
                    subtitle: workspaceHeroSubtitle,
                    providerName: chatStore.selectedProviderDisplayName,
                    sourceModeIsPrimary: chatStore.effectiveWebSearchEnabled,
                    fileCount: chatStore.selectedProjectAttachments.count,
                    linkCount: chatStore.selectedProjectLinks.count,
                    showsAgent: heroAgentAvailable,
                    projectTitle: chatStore.selectedProject == nil ? "Context" : "Project",
                    onNewChat: openNewChat,
                    onAgent: { showingAgentWorkspace = true },
                    onProject: openProjectAction
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

            if selectedHomeFilter == .all, filteredConversations.isEmpty, filteredProjects.isEmpty {
                Section {
                    ContentUnavailableView(
                        searchQuery.isEmpty ? (chatStore.selectedProject == nil ? "No chats" : "No project chats") : "No matching chats",
                        systemImage: "bubble.left.and.bubble.right",
                        description: searchQuery.isEmpty ? nil : Text("Try a project name, source title, or chat title.")
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
        .sheet(isPresented: $showingAgentWorkspace) {
            AgentWorkspaceView()
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

    private var heroAgentAvailable: Bool {
        setupProfile.experienceMode == .power ||
            setupProfile.wantsIronclaw ||
            setupProfile.useCases.contains(.buildAgents) ||
            chatStore.selectedProviderDisplayName == "IronClaw" ||
            chatStore.ironclawRemoteWorkstationAvailable
    }

    private var setupProfile: UserSetupProfile {
        guard let accountID = sessionStore.setupAccountID else { return .defaults }
        return UserSetupStorage.load(for: accountID) ?? .defaults
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

    private func openProjectAction() {
        if chatStore.selectedProject == nil {
            showingNewProject = true
        } else {
            showingProjectFiles = true
        }
    }

    private func projectName(for conversation: ConversationSummary) -> String? {
        if let selectedProject = chatStore.selectedProject,
           selectedProject.conversationIDs.contains(conversation.id) {
            return selectedProject.name
        }
        return chatStore.projects.first { $0.conversationIDs.contains(conversation.id) }?.name
    }

    private var workspaceHeroSubtitle: String {
        if let project = chatStore.selectedProject {
            return "Using \(project.name)"
        }
        return "Private AI with proof on iPhone"
    }

    private func projectSubtitle(_ project: ChatProject) -> String {
        var parts: [String] = []
        if let chats = optionalCountLabel(project.conversationIDs.count, singular: "chat") {
            parts.append(chats)
        }
        parts.append(contentsOf: contextSubtitleParts(project))
        return parts.isEmpty ? "Ready for sources" : parts.joined(separator: " / ")
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
        if !project.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Instructions")
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

struct HomeSurfaceBackground: View {
    var body: some View {
        ZStack {
            Color.appBackground
            LinearGradient(
                colors: [
                    Color.brandBlue.opacity(0.10),
                    Color.brandSky.opacity(0.05),
                    Color.clear,
                    Color.clear
                ],
                startPoint: .topTrailing,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }
}

private struct ConversationRow: View {
    let conversation: ConversationSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            SidebarSymbol(
                symbolName: conversation.isPinned ? "pin.fill" : "bubble.left",
                isSelected: isSelected || conversation.isPinned,
                isAction: false
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.body.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let createdAt = conversation.createdAt {
                    Text(Self.timestampText(for: Date(timeIntervalSince1970: createdAt)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            Spacer(minLength: 0)

            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.brandBlue)
                    .frame(width: 4, height: 28)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(isSelected ? Color.brandBlue.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.brandBlue.opacity(0.10), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }

    private static func timestampText(for date: Date) -> String {
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 {
            return "Just now"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60))m ago"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3600))h ago"
        }
        if elapsed < 604_800 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct SidebarSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .tokenInputTraits()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.brandBlue.opacity(0.05), radius: 12, y: 6)
    }
}

private struct HomeSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var actionSymbolName: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        if let actionSymbolName {
                            Image(systemName: actionSymbolName)
                                .font(.caption.weight(.bold))
                        }
                        Text(actionTitle)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.primaryAction)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 6)
        .padding(.trailing, 6)
    }
}

private struct HomeHeroActions: View {
    let showsAgent: Bool
    let projectTitle: String
    let onAgent: () -> Void
    let onProject: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if showsAgent {
                HomeTextActionButton(title: "Open Agent", symbolName: "terminal", action: onAgent)
            }

            HomeTextActionButton(title: projectTitle, symbolName: "folder", action: onProject)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

private struct HomeTextActionButton: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbolName)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }
}

private struct HomeFilterStrip: View {
    @Binding var selectedFilter: HomeFilter
    let counts: [HomeFilter: Int]
    let onSelect: (HomeFilter) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            filterButtons

            Menu {
                ForEach(HomeFilter.allCases) { filter in
                    Button {
                        onSelect(filter)
                    } label: {
                        Label(filter.title, systemImage: filter.symbolName)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: selectedFilter.symbolName)
                    Text("\(selectedFilter.title) chats")
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
            }
        }
        .padding(4)
        .background(Color.appPanelBackground.opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var filterButtons: some View {
        HStack(spacing: 6) {
            ForEach(HomeFilter.allCases) { filter in
                Button {
                    onSelect(filter)
                } label: {
                    filterLabel(for: filter)
                }
                .buttonStyle(.plain)
                .accessibilityValue(selectedFilter == filter ? "Selected" : "")
            }
        }
    }

    private func filterLabel(for filter: HomeFilter) -> some View {
        let isSelected = selectedFilter == filter
        return HStack(spacing: 5) {
            Image(systemName: filter.symbolName)
                .font(.caption.weight(.bold))
            Text(filter.title)
                .font(.caption.weight(isSelected ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            if let count = counts[filter], count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? Color.primaryAction : Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background(
                        isSelected ? Color.primaryAction.opacity(0.12) : Color.appSecondaryBackground,
                        in: Capsule()
                    )
            }
        }
        .foregroundStyle(isSelected ? Color.primaryAction : Color.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(
            isSelected ? Color.primaryAction.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primaryAction.opacity(0.14), lineWidth: 1)
            }
        }
    }
}

private struct HomeRecentsRow: View {
    let conversations: [ConversationSummary]
    let projectNameForConversation: (ConversationSummary) -> String?
    let onOpenConversation: (ConversationSummary) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(conversations) { conversation in
                    HomeRecentCard(
                        conversation: conversation,
                        projectName: projectNameForConversation(conversation),
                        onOpen: { onOpenConversation(conversation) }
                    )
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

private struct HomeRecentCard: View {
    let conversation: ConversationSummary
    let projectName: String?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(conversation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.primaryAction)
                }

                Text(projectName ?? "Private chat")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text(timestampText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("Resume")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.primaryAction)
                }
            }
            .padding(12)
            .frame(minWidth: 222, idealWidth: 222, maxWidth: 222, minHeight: 104, alignment: .topLeading)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var timestampText: String {
        guard let createdAt = conversation.createdAt else { return "Recent" }
        let date = Date(timeIntervalSince1970: createdAt)
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 {
            return "Just now"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60))m ago"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3600))h ago"
        }
        if elapsed < 604_800 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct LoadingHomeRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
    }
}

private struct WorkspaceCommandHeader: View {
    let title: String
    let subtitle: String
    let providerName: String
    let sourceModeIsPrimary: Bool
    let fileCount: Int
    let linkCount: Int
    let showsAgent: Bool
    let projectTitle: String
    let onNewChat: () -> Void
    let onAgent: () -> Void
    let onProject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 11) {
                PrivacySeal(size: 46)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                    Text(subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 0)
            }

            Button(action: onNewChat) {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .font(.headline.weight(.bold))
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask")
                            .font(.headline.weight(.bold))
                            .lineLimit(1)
                        Text("Start a private chat")
                            .font(.caption.weight(.semibold))
                            .opacity(0.72)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(Color.brandBlack)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color.brandSky, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                if showsAgent {
                    WorkspaceCommandButton(title: "Agent", symbolName: "terminal", isPrimary: false, height: 42, action: onAgent)
                }
                WorkspaceCommandButton(title: projectTitle, symbolName: "folder.badge.gearshape", isPrimary: false, height: 42, action: onProject)
            }

            if let usefulStatusLine {
                Text(usefulStatusLine.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .accessibilityLabel(usefulStatusLine.replacingOccurrences(of: " / ", with: ", "))
            }
        }
        .padding(16)
        .background {
            CommandCardBackground(cornerRadius: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
        .shadow(color: Color.brandBlue.opacity(0.14), radius: 18, y: 8)
    }

    private var contextTitle: String? {
        if fileCount > 0 && linkCount > 0 {
            return "\(fileCount + linkCount) sources"
        }
        if fileCount > 0 {
            return fileCount == 1 ? "1 file" : "\(fileCount) files"
        }
        if linkCount > 0 {
            return linkCount == 1 ? "1 link" : "\(linkCount) links"
        }
        return nil
    }

    private var usefulStatusLine: String? {
        var parts: [String] = []
        if providerName == "NEAR Cloud" {
            parts.append("Cloud route")
        } else if providerName != "NEAR Private" {
            parts.append(providerName)
        } else if sourceModeIsPrimary || contextTitle != nil {
            parts.append("Proof ready")
        }
        if sourceModeIsPrimary {
            parts.append("Web on")
        }
        if let contextTitle {
            parts.append(contextTitle)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }
}

struct CommandCardBackground: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.brandBlack,
                        Color(red: 0.006, green: 0.16, blue: 0.28),
                        Color(red: 0.0, green: 0.38, blue: 0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topTrailing) {
                LinearGradient(
                    colors: [
                        Color.brandBlue.opacity(0.78),
                        Color.brandSky.opacity(0.28),
                        Color.clear
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
    }
}

private struct WorkspaceCommandButton: View {
    let title: String
    let symbolName: String
    let isPrimary: Bool
    var height: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .font(.subheadline.weight(.bold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isPrimary ? Color.brandBlack : .white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(isPrimary ? Color.brandSky : .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(isPrimary ? 0 : 0.14), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct WorkspaceModeButton: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: symbolName)
                    .font(.headline.weight(.bold))
                    .frame(width: 26, height: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                    Text(subtitle)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .opacity(isPrimary ? 0.74 : 0.68)
                }
            }
            .foregroundStyle(isPrimary ? Color.brandBlack : .white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 72)
            .padding(.horizontal, 12)
            .background(isPrimary ? Color.brandSky : .white.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(isPrimary ? 0 : 0.15), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct StatusChip: View {
    let title: String
    let symbolName: String
    let isPrimary: Bool

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isPrimary ? Color.primaryAction : Color.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isPrimary ? Color.primaryAction.opacity(0.08) : Color.secondarySurface, in: Capsule())
    }
}

private struct ProjectRow: View {
    let title: String
    let subtitle: String?
    let symbolName: String
    let isSelected: Bool
    var isAction = false
    var tintColor: Color = .primaryAction
    var tintBackground: Color? = nil

    var body: some View {
        HStack(spacing: 12) {
            SidebarSymbol(
                symbolName: symbolName,
                isSelected: isSelected,
                isAction: isAction,
                tintColor: tintColor,
                backgroundColor: tintBackground,
                size: 32
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            isSelected ? (tintBackground ?? Color.brandBlue.opacity(0.07)) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tintColor.opacity(0.12), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct SidebarSymbol: View {
    let symbolName: String
    let isSelected: Bool
    let isAction: Bool
    var tintColor: Color = .primaryAction
    var backgroundColor: Color? = nil
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbolName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(isSelected || isAction ? tintColor : .secondary)
            .frame(width: size, height: size)
            .background(
                (isSelected || isAction ? (backgroundColor ?? tintColor.opacity(0.11)) : Color.appSecondaryBackground.opacity(0.82)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

private struct AccountToolbarButton: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var chatStore: ChatStore
    @State private var showingAccount = false
    let onRunSetupAgain: () -> Void

    var body: some View {
        Button {
            showingAccount = true
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 36, height: 36)
                .background(Color.panel.opacity(0.82), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account")
        .sheet(isPresented: $showingAccount) {
            AccountSettingsView(onRunSetupAgain: onRunSetupAgain)
                .environmentObject(sessionStore)
                .environmentObject(chatStore)
        }
        .task {
            await sessionStore.refreshProfile()
        }
    }
}

struct ChatView: View {
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        VStack(spacing: 0) {
            ChatToolbar()
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(Color.appPanelBackground)
            Divider()
                .opacity(0.55)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if chatStore.messages.isEmpty {
                            EmptyChatView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 54)
                                .padding(.bottom, 22)
                        } else {
                            ForEach(ChatDisplayItem.items(from: chatStore.messages)) { item in
                                switch item {
                                case let .message(message):
                                    MessageBubble(message: message)
                                        .id(item.id)
                                case let .council(batchID: _, messages: messages):
                                    CouncilResponseGroup(messages: messages)
                                        .id(item.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }
                .background(Color.appBackground)
                .onChange(of: chatStore.messages) { _, messages in
                    guard let last = messages.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()
                .opacity(0.55)
            InputBar()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.appPanelBackground)
        }
        .background(Color.appBackground)
    }
}

private enum ChatDisplayItem: Identifiable {
    case message(ChatMessage)
    case council(batchID: String, messages: [ChatMessage])

    var id: String {
        switch self {
        case let .message(message):
            return message.id
        case let .council(batchID, _):
            return batchID
        }
    }

    static func items(from messages: [ChatMessage]) -> [ChatDisplayItem] {
        let grouped = Dictionary(
            grouping: messages.filter { $0.role == .assistant && $0.councilBatchID?.isEmpty == false },
            by: { $0.councilBatchID ?? "" }
        )
        let groupCounts = grouped.mapValues(\.count)
        var renderedCouncilIDs = Set<String>()
        var items: [ChatDisplayItem] = []

        for message in messages {
            guard message.role == .assistant,
                  let batchID = message.councilBatchID,
                  (groupCounts[batchID] ?? 0) > 1 else {
                items.append(.message(message))
                continue
            }

            guard !renderedCouncilIDs.contains(batchID) else {
                continue
            }
            let councilMessages = (grouped[batchID] ?? [])
                .sorted { $0.createdAt < $1.createdAt }
            items.append(.council(batchID: batchID, messages: councilMessages))
            renderedCouncilIDs.insert(batchID)
        }
        return items
    }
}

private struct CouncilResponseGroup: View {
    @EnvironmentObject private var chatStore: ChatStore
    let messages: [ChatMessage]
    @State private var selectedMessageID: String?

    private var selectedMessage: ChatMessage? {
        let currentID = selectedMessageID ?? preferredMessage?.id
        return messages.first(where: { $0.id == currentID }) ?? messages.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.brandSky.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("LLM Council")
                        .font(.caption.weight(.semibold))
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if hasRunningModels {
                    Button {
                        if canStopWaiting {
                            chatStore.stopWaitingForCouncil(batchID: batchID)
                        } else {
                            chatStore.cancelStream()
                        }
                    } label: {
                        Label(canStopWaiting ? "Stop waiting" : "Cancel", systemImage: canStopWaiting ? "forward.end.fill" : "xmark")
                            .font(.caption2.weight(.bold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canStopWaiting ? Color.brandBlue : .secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background((canStopWaiting ? Color.brandBlue : Color.secondary).opacity(0.09), in: Capsule())
                    .accessibilityHint(canStopWaiting ? "Synthesize from completed Council answers now" : "Cancel the Council run")
                }
            }

            TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                VStack(spacing: 6) {
                    ForEach(messages) { message in
                        CouncilModelProgressRow(
                            message: message,
                            now: timeline.date,
                            isSelected: message.id == selectedMessage?.id
                        ) {
                            selectedMessageID = message.id
                        }
                    }
                }
            }

            if let selectedMessage {
                MessageBubble(message: selectedMessage)
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.13), lineWidth: 1)
        }
        .onAppear {
            selectedMessageID = selectedMessageID ?? messages.first?.id
        }
        .onChange(of: messages) { _, updatedMessages in
            guard let selectedMessageID,
                  updatedMessages.contains(where: { $0.id == selectedMessageID }) else {
                self.selectedMessageID = updatedMessages.first?.id
                return
            }
        }
    }

    private var batchID: String? {
        messages.first?.councilBatchID
    }

    private var preferredMessage: ChatMessage? {
        messages.first(where: \.hasUsableCouncilAnswer) ?? messages.first
    }

    private var statusText: String {
        let ready = messages.filter(\.hasUsableCouncilAnswer).count
        let running = messages.filter(\.isStreaming).count
        let failed = messages.filter { $0.status == "failed" }.count
        if running > 0 {
            return ready > 0 ? "\(ready) ready · \(running) still running" : "\(running) models thinking"
        }
        if failed > 0, ready > 0 {
            return "\(ready) ready · \(failed) failed"
        }
        if failed > 0 {
            return "\(failed) failed"
        }
        return ready == messages.count ? "\(messages.count) answers ready" : "\(ready) usable answers"
    }

    private var hasRunningModels: Bool {
        messages.contains(where: \.isStreaming)
    }

    private var canStopWaiting: Bool {
        hasRunningModels && messages.contains(where: \.hasUsableCouncilAnswer)
    }
}

private struct CouncilModelProgressRow: View {
    let message: ChatMessage
    let now: Date
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: symbolName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tintColor)
                    .frame(width: 24, height: 24)
                    .background(tintColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(message.modelDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(progressText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.brandBlue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isSelected ? Color.brandBlue.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(message.modelDisplayName), \(progressText)")
    }

    private var symbolName: String {
        if message.status == "failed" {
            return "exclamationmark.triangle.fill"
        }
        if message.isStreaming, message.firstTokenAt != nil {
            return "waveform"
        }
        if message.isStreaming {
            return "hourglass"
        }
        if message.hasUsableCouncilAnswer {
            return "checkmark.circle.fill"
        }
        return "circle"
    }

    private var tintColor: Color {
        if message.status == "failed" {
            return .red
        }
        if message.isStreaming {
            return Color.brandBlue
        }
        if message.hasUsableCouncilAnswer {
            return Color.verifiedGreen
        }
        return .secondary
    }

    private var progressText: String {
        if message.status == "failed" {
            return "Failed"
        }
        if message.isStreaming {
            if let latency = message.firstTokenLatency {
                return "Writing · first token \(formatSeconds(latency))"
            }
            return "Waiting · \(formatSeconds(now.timeIntervalSince(message.createdAt)))"
        }
        if message.hasUsableCouncilAnswer {
            if let latency = message.firstTokenLatency {
                return "Done · first token \(formatSeconds(latency))"
            }
            return "Done"
        }
        return "No answer"
    }

    private func formatSeconds(_ value: TimeInterval) -> String {
        let clamped = max(0, value)
        if clamped < 10 {
            return String(format: "%.1fs", clamped)
        }
        return "\(Int(clamped.rounded()))s"
    }
}

private struct ChatToolbar: View {
    @EnvironmentObject private var chatStore: ChatStore
    @State private var showingShare = false
    @State private var showingModels = false
    @State private var showingSecurity = false
    @State private var showingSharedLink = false
    @State private var showingRename = false
    @State private var showingProjectFiles = false
    @State private var showingAgentWorkspace = false
    @State private var showingExporter = false
    @State private var showingSignedExportNotice = false
    @State private var exportDocument = ConversationExportDocument()
    @State private var exportContentType: UTType = .plainText
    @State private var exportFilename = "near-private-chat.txt"

    var body: some View {
        compactToolbar
        .buttonStyle(.borderless)
        .sheet(isPresented: $showingShare) {
            if let conversation = chatStore.selectedConversation {
                ShareConversationView(conversation: conversation)
                    .environmentObject(chatStore)
            }
        }
        .sheet(isPresented: $showingModels) {
            ModelPickerView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingSecurity) {
            SecurityView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingSharedLink) {
            SharedConversationSheet()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingRename) {
            RenameConversationView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingProjectFiles) {
            ProjectFilesView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingAgentWorkspace) {
            AgentWorkspaceView()
                .environmentObject(chatStore)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                chatStore.bannerMessage = "Conversation exported."
            case let .failure(error):
                chatStore.bannerMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Signed export identity",
            isPresented: $showingSignedExportNotice,
            titleVisibility: .visible
        ) {
            Button("Export Signed JSON") {
                prepareExport(.signedJSON)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signed JSON is sealed with a stable on-device Keychain identity. That helps recipients verify tampering, but repeated exports from this device can be linked by the signing key id.")
        }
    }

    private var regularToolbar: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(chatStore.selectedConversationTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                metadataRow
            }

            Spacer()

            toolbarButtons
        }
    }

    private var compactToolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                modelSelectorButton(maxWidth: 190)
                compactAttestationButton

                Spacer(minLength: 0)

                if shouldShowAgentWorkspaceButton && !chatStore.messages.isEmpty {
                    agentWorkspaceButton
                }

                moreMenuButton
            }

            if shouldShowCompactStatusText {
                Text(compactStatusText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
    }

    private var shouldShowCompactStatusText: Bool {
        !chatStore.messages.isEmpty
    }

    private var compactStatusText: String {
        var parts: [String] = []
        if chatStore.selectedRouteUsesNearCloud {
            parts.append("NEAR Cloud")
        } else if chatStore.selectedProviderDisplayName == "IronClaw" {
            parts.append("Agent route")
        } else if chatStore.researchModeEnabled {
            parts.append("Private research")
        } else {
            parts.append("Private chat")
        }
        if chatStore.selectedProviderDisplayName != "NEAR Private",
           chatStore.selectedProviderDisplayName != "IronClaw" {
            parts.append(chatStore.selectedProviderDisplayName)
        }
        if let project = chatStore.selectedProject {
            parts.append(project.name)
        }
        return parts.joined(separator: " · ")
    }

    private var compactAttestationButton: some View {
        Button {
            showingSecurity = true
        } label: {
            let status = chatStore.currentAttestationStatus
            let copy = status.userFacingCopy()
            let isCloudTrust = chatStore.selectedRouteUsesNearCloud || (chatStore.isCouncilModeEnabled && chatStore.activeCouncilHasNearCloudRoutes)
            let tint = isCloudTrust ? Color.brandBlue : status.tintColor
            HStack(spacing: 5) {
                Image(systemName: isCloudTrust ? "eye.slash" : status.symbolName)
                    .font(.caption.weight(.bold))
                Text(isCloudTrust ? "Anonymized" : compactAttestationLabel(copy.badge))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 1)
            }
        }
        .accessibilityLabel(chatStore.currentAttestationStatus.accessibilityLabel())
        .accessibilityHint(chatStore.currentAttestationStatus.accessibilityHint())
    }

    private func compactAttestationLabel(_ value: String) -> String {
        guard value.localizedCaseInsensitiveCompare("No proof") != .orderedSame else {
            return value
        }
        return value
            .replacingOccurrences(of: "Verified ", with: "")
            .replacingOccurrences(of: " proof", with: "")
    }

    private var metadataRow: some View {
        HStack(spacing: 8) {
            if chatStore.isCouncilModeEnabled {
                MetadataPill(
                    title: chatStore.activeCouncilRouteSummary,
                    symbolName: "square.grid.2x2",
                    isPrimary: true
                )
            } else {
                MetadataPill(
                    title: chatStore.selectedRouteUsesNearCloud ? "NEAR Cloud" : "Private",
                    symbolName: chatStore.selectedRouteUsesNearCloud ? "cloud" : "lock.shield",
                    isPrimary: true
                )
            }
            if chatStore.selectedRouteUsesNearCloud || (chatStore.isCouncilModeEnabled && chatStore.activeCouncilHasNearCloudRoutes) {
                MetadataPill(title: "Anonymized", symbolName: "eye.slash", isPrimary: true)
                MetadataPill(
                    title: chatStore.effectiveAppWebGroundingEnabled ? "App web on" : "App web off",
                    symbolName: chatStore.effectiveAppWebGroundingEnabled ? "globe" : "globe.slash",
                    isPrimary: chatStore.effectiveAppWebGroundingEnabled
                )
            } else {
                MetadataPill(title: chatStore.sourceModeDetail, symbolName: chatStore.sourceModeSymbolName, isPrimary: chatStore.effectiveWebSearchEnabled)
            }
            if chatStore.selectedProviderDisplayName == "NEAR Private" || (chatStore.isCouncilModeEnabled && !chatStore.activeCouncilHasExternalRoutes) {
                MetadataPill(
                    title: chatStore.currentAttestationStatus.userFacingCopy().badge,
                    symbolName: chatStore.currentAttestationStatus.symbolName,
                    isPrimary: false
                )
            }
            if chatStore.selectedProviderDisplayName != "NEAR Private", !chatStore.selectedRouteUsesNearCloud, !chatStore.isCouncilModeEnabled {
                MetadataPill(title: chatStore.selectedProviderDisplayName, symbolName: "point.3.connected.trianglepath.dotted", isPrimary: true)
            }
            if chatStore.selectedModelOption?.isIronclawMobileRuntime == true {
                MetadataPill(title: "Phone tools", symbolName: "iphone", isPrimary: false)
                if chatStore.ironclawRemoteWorkstationAvailable {
                    MetadataPill(title: "Shell handoff", symbolName: "terminal", isPrimary: true)
                }
                MetadataPill(
                    title: chatStore.ironclawRemoteWorkstationAvailable ? "Workstation on" : "Workstation off",
                    symbolName: "terminal",
                    isPrimary: chatStore.ironclawRemoteWorkstationAvailable
                )
            } else if chatStore.selectedModelOption?.isIronclawHostedModel == true {
                MetadataPill(title: "Hosted workstation", symbolName: "terminal", isPrimary: true)
                MetadataPill(title: ironclawToolPillTitle, symbolName: "chevron.left.forwardslash.chevron.right", isPrimary: chatStore.ironclawRemoteWorkstationAvailable)
                if chatStore.ironclawTokenConfigured {
                    MetadataPill(title: "Token saved", symbolName: "key", isPrimary: false)
                }
            }
            if let project = chatStore.selectedProject {
                MetadataPill(title: project.name, symbolName: "folder", isPrimary: false)
                if !chatStore.activeProjectContextAttachments.isEmpty {
                    MetadataPill(title: countLabel(chatStore.activeProjectContextAttachments.count, singular: "file"), symbolName: "paperclip", isPrimary: false)
                }
                if !chatStore.activeProjectContextLinks.isEmpty {
                    MetadataPill(title: countLabel(chatStore.activeProjectContextLinks.count, singular: "link"), symbolName: "link", isPrimary: false)
                }
            }
        }
    }

    private var ironclawToolPillTitle: String {
        guard chatStore.ironclawRemoteWorkstationAvailable else { return "Tools off" }
        return chatStore.ironclawToolNames.isEmpty ? "Shell + git" : "\(chatStore.ironclawToolNames.count) tools"
    }

    private var toolbarButtons: some View {
        HStack(spacing: 8) {
            modelSelectorButton(maxWidth: 150)

            if chatStore.selectedProject != nil {
                projectContextButton
            }

            if shouldShowAgentWorkspaceButton {
                agentWorkspaceButton
            }

            securityButton

            if chatStore.selectedConversation != nil {
                reloadButton

                shareButton
            }

            moreMenuButton
        }
    }

    private func modelSelectorButton(maxWidth: CGFloat) -> some View {
        Button {
            AppHaptics.selection()
            showingModels = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: chatStore.isCouncilModeEnabled ? "square.grid.2x2" : (chatStore.selectedRouteUsesNearCloud ? "cloud" : "cpu"))
                    .font(.caption.weight(.bold))
                Text(chatStore.activeModelDisplayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .opacity(0.68)
            }
            .foregroundStyle(Color.brandBlue)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(maxWidth: maxWidth)
            .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.brandBlue.opacity(0.10), lineWidth: 1)
            }
        }
        .accessibilityLabel(modelSelectorAccessibilityLabel)
        .accessibilityHint("Opens model selection for the next message.")
    }

    private var modelSelectorAccessibilityLabel: String {
        if chatStore.isCouncilModeEnabled {
            return "Select model, LLM Council active, \(chatStore.activeCouncilRouteSummary)"
        }
        return "Select model, currently \(chatStore.activeModelDisplayName)"
    }

    private var projectContextButton: some View {
        Button {
            showingProjectFiles = true
        } label: {
            ToolbarIcon(symbolName: "folder.badge.plus")
        }
        .accessibilityLabel("Project Context")
        .disabled(chatStore.selectedProject == nil)
    }

    private var agentWorkspaceButton: some View {
        Button {
            showingAgentWorkspace = true
        } label: {
            ToolbarIcon(symbolName: "terminal", isPrimary: chatStore.selectedProviderDisplayName == "IronClaw")
        }
        .accessibilityLabel("Agent")
    }

    private var securityButton: some View {
        Button {
            showingSecurity = true
        } label: {
            ToolbarIcon(
                symbolName: chatStore.currentAttestationStatus.symbolName,
                isPrimary: chatStore.currentAttestationStatus.effectiveState() == .valid
            )
        }
        .accessibilityLabel(chatStore.currentAttestationStatus.accessibilityLabel())
        .accessibilityHint(chatStore.currentAttestationStatus.accessibilityHint())
    }

    private var reloadButton: some View {
        Button {
            Task {
                if let conversation = chatStore.selectedConversation {
                    await chatStore.loadMessages(for: conversation)
                }
            }
        } label: {
            ToolbarIcon(symbolName: "arrow.clockwise")
        }
        .accessibilityLabel("Reload Messages")
        .disabled(chatStore.selectedConversation == nil)
    }

    private var shareButton: some View {
        Button {
            showingShare = true
        } label: {
            ToolbarIcon(symbolName: "square.and.arrow.up", isPrimary: true)
        }
        .accessibilityLabel("Share")
        .disabled(chatStore.selectedConversation == nil)
    }

    private var moreMenuButton: some View {
        Menu {
            moreMenuContent
        } label: {
            ToolbarIcon(symbolName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    @ViewBuilder
    private var moreMenuContent: some View {
        Section("Navigate") {
            if shouldShowAgentWorkspaceButton {
                Button {
                    showingAgentWorkspace = true
                } label: {
                    Label("Open Agent", systemImage: "terminal")
                }
            }
            Button {
                showingSecurity = true
            } label: {
                Label("Security & Attestation", systemImage: "checkmark.shield")
            }
            Button {
                showingProjectFiles = true
            } label: {
                Label("Project Context", systemImage: "folder.badge.gearshape")
            }
            .disabled(chatStore.selectedProject == nil)
            Button {
                showingSharedLink = true
            } label: {
                Label("Open Shared Link", systemImage: "link.badge.plus")
            }
        }

        Section("Edit") {
            Button {
                showingRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .disabled(chatStore.selectedConversation == nil)
            Button {
                chatStore.cloneSelectedConversation()
            } label: {
                Label("Branch from here", systemImage: "doc.on.doc")
            }
            .disabled(chatStore.selectedConversation == nil)
        }

        Section("Export") {
            Button {
                showingShare = true
            } label: {
                Label("Share Link", systemImage: "link")
            }
            .disabled(chatStore.selectedConversation == nil)
            Button {
                chatStore.copyCurrentTranscript()
            } label: {
                Label("Copy Transcript", systemImage: "doc.text")
            }
            .disabled(chatStore.messages.isEmpty)
            Button {
                prepareExport(.text)
            } label: {
                Label("Export TXT", systemImage: "doc.plaintext")
            }
            .disabled(chatStore.messages.isEmpty)
            Button {
                prepareExport(.json)
            } label: {
                Label("Export JSON", systemImage: "curlybraces")
            }
            .disabled(chatStore.messages.isEmpty)
            Button {
                showingSignedExportNotice = true
            } label: {
                Label("Export Signed JSON", systemImage: "checkmark.shield")
            }
            .disabled(chatStore.messages.isEmpty)
            Button {
                prepareExport(.pdf)
            } label: {
                Label("Export PDF", systemImage: "doc.richtext")
            }
            .disabled(chatStore.messages.isEmpty)
        }

        Section("Organize") {
            Button {
                chatStore.createProjectFromSelectedConversation()
            } label: {
                Label("New Project from Chat", systemImage: "folder.badge.plus")
            }
            .disabled(chatStore.selectedConversation == nil)
            Menu {
                Button {
                    chatStore.assignSelectedConversation(to: nil)
                } label: {
                    Label("No Project", systemImage: "tray")
                }
                ForEach(chatStore.projects) { project in
                    Button {
                        chatStore.assignSelectedConversation(to: project.id)
                    } label: {
                        Label(project.name, systemImage: "folder")
                    }
                }
            } label: {
                Label("Move to Project", systemImage: "folder")
            }
            .disabled(chatStore.selectedConversation == nil)
            Button {
                chatStore.togglePinSelectedConversation()
            } label: {
                Label(
                    chatStore.selectedConversation?.isPinned == true ? "Unpin" : "Pin",
                    systemImage: chatStore.selectedConversation?.isPinned == true ? "pin.slash" : "pin"
                )
            }
            .disabled(chatStore.selectedConversation == nil)
            Button {
                chatStore.archiveSelectedConversation()
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .disabled(chatStore.selectedConversation == nil)
        }

        Section("Destructive") {
            Button(role: .destructive) {
                chatStore.deleteSelectedConversation()
            } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
            .disabled(chatStore.selectedConversation == nil)
        }
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }

    private func prepareExport(_ format: ConversationExportFormat) {
        do {
            exportDocument = try ConversationExportBuilder.document(
                for: chatStore.selectedConversation,
                messages: chatStore.messages,
                format: format,
                signedContext: signedTranscriptContext
            )
            exportContentType = format.contentType
            exportFilename = ConversationExportBuilder.filename(
                for: chatStore.selectedConversation,
                format: format
            )
            showingExporter = true
        } catch {
            chatStore.bannerMessage = error.localizedDescription
        }
    }

    private var signedTranscriptContext: SignedTranscriptExportContext {
        chatStore.signedTranscriptExportContext
    }

    private var shouldShowAgentWorkspaceButton: Bool {
        chatStore.selectedProviderDisplayName == "IronClaw" || chatStore.ironclawRemoteWorkstationAvailable
    }
}

private struct MetadataPill: View {
    let title: String
    let symbolName: String
    let isPrimary: Bool

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isPrimary ? Color.brandBlue : .secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isPrimary ? Color.brandBlue.opacity(0.08) : Color.appSecondaryBackground, in: Capsule())
    }
}

private struct ToolbarIcon: View {
    let symbolName: String
    var isPrimary = false

    var body: some View {
        Image(systemName: symbolName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isPrimary ? Color.brandBlue : .secondary)
            .frame(width: 34, height: 34)
            .background(isPrimary ? Color.brandBlue.opacity(0.08) : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum ModelCapabilityFilter: String, CaseIterable, Identifiable {
    case privateRoute
    case openWeights
    case reasoning
    case code
    case vision
    case longContext

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateRoute: "Private"
        case .openWeights: "Open weights"
        case .reasoning: "Reasoning"
        case .code: "Code"
        case .vision: "Vision"
        case .longContext: "Long context"
        }
    }

    var symbolName: String {
        switch self {
        case .privateRoute: "lock.shield"
        case .openWeights: "shippingbox"
        case .reasoning: "brain.head.profile"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .vision: "eye"
        case .longContext: "text.rectangle"
        }
    }

    func matches(_ model: ModelOption) -> Bool {
        switch self {
        case .privateRoute:
            return !model.isExternalModel && model.isVerifiable
        case .openWeights:
            return model.isOpenWeightCandidate
        case .reasoning:
            return model.isRecommendedReasoningModel
        case .code:
            return model.isCodeModel
        case .vision:
            return model.isVisionModel
        case .longContext:
            return model.isLongContextModel
        }
    }
}

private struct ModelPickerView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedTab: ModelPickerTab = .models
    @State private var showingCouncilCustomizer = false
    @State private var activeFilters: Set<ModelCapabilityFilter> = []

    private enum ModelPickerTab: String, CaseIterable, Identifiable {
        case models = "Models"
        case council = "Council"

        var id: String { rawValue }
    }

    private var eliteModels: [ModelOption] {
        filtered(chatStore.eliteModels)
    }

    private var openWeightModels: [ModelOption] {
        filtered(chatStore.openWeightModels)
    }

    private var privateModels: [ModelOption] {
        filtered(chatStore.privateModels)
    }

    private var standardModels: [ModelOption] {
        filtered(chatStore.standardModels)
    }

    private var cloudModels: [ModelOption] {
        filtered(chatStore.cloudModels)
    }

    private var agentModels: [ModelOption] {
        filtered(chatStore.agentModels)
    }

    private var featuredModels: [ModelOption] {
        filtered(chatStore.featuredPickerModels)
    }

    private var pinnedModels: [ModelOption] {
        filtered(chatStore.pinnedPickerModels)
    }

    private var recommendedModelIDs: Set<String> {
        Set(unpinned(featuredModels).map(\.id))
    }

    private var isSearchingModels: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var councilCandidateModels: [ModelOption] {
        let candidates = filtered(chatStore.pickerModels.filter { chatStore.canUseInCouncil($0.id) })
        let activeIDs = chatStore.activeCouncilModels.map(\.id)
        let activeIDSet = Set(activeIDs)
        let activeModels = activeIDs.compactMap { id in candidates.first { $0.id == id } }
        return activeModels + candidates.filter { !activeIDSet.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Model picker mode", selection: $selectedTab) {
                        ForEach(ModelPickerTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 8, trailing: 14))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                if selectedTab == .models {
                    if !isSearchingModels {
                        Section {
                            ModelPickerSummary(
                                selectedModelName: chatStore.activeModelDisplayName,
                                selectedModelID: chatStore.selectedModel,
                                providerName: chatStore.selectedProviderDisplayName,
                                modelCount: chatStore.pickerModels.count,
                                councilModelNames: chatStore.councilModelNames,
                                webSearchEnabled: chatStore.effectiveWebSearchEnabled,
                                appWebGroundingEnabled: chatStore.effectiveAppWebGroundingEnabled,
                                planName: chatStore.currentBillingPlanName,
                                hiddenPlanLockedModelCount: chatStore.hiddenPlanLockedModelCount,
                                ironclawRemoteWorkstationAvailable: chatStore.ironclawRemoteWorkstationAvailable,
                                ironclawTokenConfigured: chatStore.ironclawTokenConfigured
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 8, trailing: 14))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        Section {
                            ReasoningEffortPickerCard(
                                selectedEffort: chatStore.advancedModelParams.reasoningEffort,
                                appliesToCurrentRoute: chatStore.selectedRouteUsesNearCloud || chatStore.activeCouncilHasNearCloudRoutes,
                                onSelect: { effort in
                                    chatStore.setReasoningEffort(effort)
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 8, trailing: 14))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        Section {
                            ModelCapabilityFilterBar(activeFilters: $activeFilters)
                                .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 8, trailing: 14))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    modelSection("Pinned", models: pinnedModels, showsCouncilButton: false)
                    modelSection("Recommended", models: unpinned(featuredModels), showsCouncilButton: false)
                    modelSection("Open / Reasoning", models: secondaryModels(openWeightModels), showsCouncilButton: false)
                    modelSection("Private / Verifiable", models: secondaryModels(privateModels), showsCouncilButton: false)
                    modelSection("Frontier", models: secondaryModels(eliteModels), showsCouncilButton: false)
                    modelSection("NEAR Cloud", models: secondaryModels(cloudModels), showsCouncilButton: false)
                    modelSection("General", models: secondaryModels(standardModels), showsCouncilButton: false)
                    modelSection("Agents", models: secondaryModels(agentModels), showsCouncilButton: false)
                } else {
                    if !isSearchingModels {
                        Section {
                            CouncilPickerCard(
                                models: chatStore.activeCouncilModels,
                                defaultModels: chatStore.defaultCouncilModels,
                                presets: chatStore.councilPresets,
                                maxModels: 4,
                                isCustomizing: $showingCouncilCustomizer,
                                onUseDefault: {
                                    chatStore.useDefaultCouncilLineup()
                                    dismiss()
                                },
                                onUsePreset: { presetID in
                                    chatStore.useCouncilPreset(presetID)
                                },
                                onClear: {
                                    chatStore.clearCouncilMode()
                                },
                                onRemoveModel: { modelID in
                                    chatStore.toggleCouncilModel(modelID)
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 8, trailing: 14))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    if showingCouncilCustomizer || isSearchingModels {
                        modelSection("Choose Council Models", models: councilCandidateModels, showsCouncilButton: true, dismissOnSelect: false)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Model")
            .platformInlineNavigationTitle()
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(modelSearchPrompt))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                if chatStore.models.isEmpty {
                    await chatStore.refreshModels()
                }
            }
        }
        .platformMediumDetent()
    }

    private var modelSearchPrompt: String {
        let count = chatStore.pickerModels.count
        return count > 0 ? "Search \(count) models" : "Search models"
    }

    private func filtered(_ models: [ModelOption]) -> [ModelOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched: [ModelOption]
        if query.isEmpty {
            searched = models
        } else {
            searched = models.filter { model in
                let aliases = model.metadata?.aliases?.joined(separator: " ") ?? ""
                return model.id.localizedCaseInsensitiveContains(query) ||
                    model.displayName.localizedCaseInsensitiveContains(query) ||
                    aliases.localizedCaseInsensitiveContains(query) ||
                    (model.metadata?.modelDescription ?? "").localizedCaseInsensitiveContains(query)
            }
        }
        guard !activeFilters.isEmpty else { return searched }
        return searched.filter { model in
            activeFilters.allSatisfy { $0.matches(model) }
        }
    }

    private func unpinned(_ models: [ModelOption]) -> [ModelOption] {
        models.filter { !chatStore.isPinnedModel($0.id) }
    }

    private func secondaryModels(_ models: [ModelOption]) -> [ModelOption] {
        let primaryIDs = recommendedModelIDs
        return unpinned(models).filter { !primaryIDs.contains($0.id) }
    }

    @ViewBuilder
    private func modelSection(_ title: String, models: [ModelOption], showsCouncilButton: Bool, dismissOnSelect: Bool = true) -> some View {
        if !models.isEmpty {
            Section(title) {
                ForEach(models) { model in
                    ModelPickerRow(
                        model: model,
                        isSelected: model.id == chatStore.selectedModel,
                        councilIndex: chatStore.councilIndex(for: model.id),
                        canUseInCouncil: chatStore.canUseInCouncil(model.id),
                        showsCouncilButton: showsCouncilButton,
                        isPinned: chatStore.isPinnedModel(model.id),
                        attestationStatus: chatStore.currentAttestationStatus,
                        togglePinAction: {
                            chatStore.togglePinnedModel(model.id)
                        },
                        selectAction: {
                            if dismissOnSelect {
                                chatStore.selectModel(model.id)
                                dismiss()
                            } else {
                                chatStore.toggleCouncilModel(model.id)
                            }
                        }
                    )
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }
}

private struct ReasoningEffortPickerCard: View {
    let selectedEffort: ModelReasoningEffort
    let appliesToCurrentRoute: Bool
    let onSelect: (ModelReasoningEffort) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 24, height: 24)
                    .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Reasoning effort")
                        .font(.caption.weight(.semibold))
                    Text(appliesToCurrentRoute ? "Applied to NEAR Cloud requests when supported" : "Saved for Cloud models and mixed Council runs")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                ForEach(ModelReasoningEffort.allCases) { effort in
                    Button {
                        onSelect(effort)
                    } label: {
                        Text(effort.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .foregroundStyle(effort == selectedEffort ? Color.white : Color.textSecondary)
                            .background(effort == selectedEffort ? Color.primaryAction : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reasoning effort \(effort.title)")
                    .accessibilityHint(effort.detail)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ModelCapabilityFilterBar: View {
    @Binding var activeFilters: Set<ModelCapabilityFilter>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(activeFilters.isEmpty ? "All models" : "\(activeFilters.count) filter\(activeFilters.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !activeFilters.isEmpty {
                    Button("Clear") {
                        activeFilters.removeAll()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.brandBlue)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ModelCapabilityFilter.allCases) { filter in
                        Button {
                            toggle(filter)
                        } label: {
                            Label(filter.title, systemImage: filter.symbolName)
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .lineLimit(1)
                                .foregroundStyle(activeFilters.contains(filter) ? Color.white : Color.textSecondary)
                                .padding(.horizontal, 10)
                                .frame(height: 34)
                                .background(activeFilters.contains(filter) ? Color.primaryAction : Color.appPanelBackground, in: Capsule())
                                .overlay {
                                    Capsule()
                                        .stroke(activeFilters.contains(filter) ? Color.clear : Color.appBorder, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(filter.title) filter")
                        .accessibilityAddTraits(activeFilters.contains(filter) ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.vertical, 2)
    }

    private func toggle(_ filter: ModelCapabilityFilter) {
        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
    }
}

private struct CouncilPickerCard: View {
    let models: [ModelOption]
    let defaultModels: [ModelOption]
    let presets: [CouncilPresetOption]
    let maxModels: Int
    @Binding var isCustomizing: Bool
    let onUseDefault: () -> Void
    let onUsePreset: (String) -> Void
    let onClear: () -> Void
    let onRemoveModel: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 30, height: 30)
                    .background(Color.brandSky.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Council")
                        .font(.subheadline.weight(.semibold))
                    Text("Choose models manually, or start from a recommended lineup")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Label(councilStateTitle, systemImage: councilStateSymbol)
                    .font(.caption2.weight(.bold))
                    .labelStyle(.iconOnly)
                    .foregroundStyle(isCouncilActive ? Color.trustVerified : .secondary)
                    .frame(width: 30, height: 30)
                    .background((isCouncilActive ? Color.trustVerified : Color.secondary).opacity(0.10), in: Circle())
                    .accessibilityLabel(councilStateTitle)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(councilStateTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCouncilActive ? Color.trustVerified : .secondary)

                Text(councilStateDetail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ChipFlowLayout(spacing: 6, lineSpacing: 6) {
                if !displayModels.isEmpty {
                    ForEach(displayModels) { model in
                        Button {
                            if isCouncilActive {
                                onRemoveModel(model.id)
                            }
                        } label: {
                            Label(model.displayName, systemImage: isCouncilActive ? "xmark.circle.fill" : "sparkles")
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(isCouncilActive ? Color.brandBlue : .secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(isCouncilActive ? Color.brandBlue.opacity(0.10) : Color.appSecondaryBackground, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isCouncilActive)
                        .accessibilityLabel(isCouncilActive ? "Remove \(model.displayName) from Council" : "Recommended lineup includes \(model.displayName)")
                    }
                } else {
                    StatusChip(title: "Waiting for available models", symbolName: "clock", isPrimary: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                Button {
                    onUseDefault()
                } label: {
                    Label(autoCouncilButtonTitle, systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandBlue)
                .disabled(defaultModels.count < 2 || isAutoCouncilActive)
                .accessibilityHint("Use the recommended Council lineup for the next message")

                HStack(spacing: 8) {
                    Button {
                        isCustomizing.toggle()
                    } label: {
                        Label(isCustomizing ? "Hide Models" : "Choose Models", systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(isCustomizing ? "Hide Council model controls" : "Show Council model controls")

                    if isCouncilActive {
                        Button {
                            onClear()
                        } label: {
                            Label("Single", systemImage: "1.circle")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Return to a single model")
                    }
                }
            }

            if isCustomizing, !presets.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    Text("Lineups")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets) { preset in
                                Button {
                                    onUsePreset(preset.id)
                                } label: {
                                    CouncilPresetPill(preset: preset)
                                }
                                .buttonStyle(.plain)
                                .disabled(!preset.isAvailable)
                                .accessibilityLabel("Use \(preset.title) Council lineup")
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.12), lineWidth: 1)
        }
    }

    private var isCouncilActive: Bool {
        models.count > 1
    }

    private var isAutoCouncilActive: Bool {
        isCouncilActive && models.map(\.id) == defaultModels.map(\.id)
    }

    private var displayModels: [ModelOption] {
        let lineup = isCouncilActive ? models : defaultModels
        return Array(lineup.prefix(maxModels))
    }

    private var autoCouncilButtonTitle: String {
        isAutoCouncilActive ? "Recommended On" : "Use Recommended"
    }

    private var councilStateTitle: String {
        if isAutoCouncilActive {
            return "Recommended lineup active"
        }
        if isCouncilActive {
            return "Custom Council active"
        }
        return defaultModels.count > 1 ? "Recommended lineup ready" : "Council unavailable"
    }

    private var councilStateDetail: String {
        if isCouncilActive {
            return "\(models.count) models will answer in parallel."
        }
        if defaultModels.count > 1 {
            return "\(defaultModels.count) recommended models are ready."
        }
        return "At least two eligible chat models are needed."
    }

    private var councilStateSymbol: String {
        if isCouncilActive {
            return isAutoCouncilActive ? "checkmark.seal.fill" : "slider.horizontal.3"
        }
        return defaultModels.count > 1 ? "sparkles" : "exclamationmark.triangle"
    }
}

private struct CouncilPresetPill: View {
    let preset: CouncilPresetOption

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: preset.symbolName)
                    .font(.caption.weight(.bold))
                Text(preset.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(preset.isAvailable ? preset.previewNames : "Needs available models")
                .font(.caption2.weight(.medium))
                .foregroundStyle(preset.isAvailable ? Color.secondary : Color.secondary.opacity(0.72))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(preset.isAvailable ? Color.brandBlue : .secondary)
        .frame(width: 150, alignment: .topLeading)
        .frame(minHeight: 70, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(preset.isAvailable ? Color.brandBlue.opacity(0.08) : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(preset.isAvailable ? Color.brandBlue.opacity(0.14) : Color.appBorder, lineWidth: 1)
        }
        .opacity(preset.isAvailable ? 1 : 0.58)
    }
}

private struct ModelPickerSummary: View {
    let selectedModelName: String
    let selectedModelID: String
    let providerName: String
    let modelCount: Int
    let councilModelNames: [String]
    let webSearchEnabled: Bool
    let appWebGroundingEnabled: Bool
    let planName: String
    let hiddenPlanLockedModelCount: Int
    let ironclawRemoteWorkstationAvailable: Bool
    let ironclawTokenConfigured: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: isIronclawProvider ? "point.3.connected.trianglepath.dotted" : "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 30, height: 30)
                    .background(Color.brandBlue.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedModelName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            ChipFlowLayout(spacing: 6, lineSpacing: 6) {
                StatusChip(title: providerChipTitle, symbolName: providerChipSymbol, isPrimary: false)
                StatusChip(title: routeCostTitle, symbolName: routeCostSymbol, isPrimary: isNearCloudProvider || isIronclawProvider)
                if isNearCloudProvider {
                    StatusChip(title: "Not attested", symbolName: "shield.slash", isPrimary: false)
                }
                if councilModelNames.count > 1, !isNearCloudProvider, !isIronclawProvider {
                    StatusChip(title: "Council \(councilModelNames.count)", symbolName: "square.grid.2x2", isPrimary: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hiddenPlanLockedModelCount > 0, !isNearCloudProvider, !isIronclawProvider {
                HStack(spacing: 7) {
                    Image(systemName: "lock.open")
                        .font(.caption2.weight(.bold))
                    Text("Unlock \(hiddenPlanLockedModelCount) more models")
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    Text("Upgrade")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(Color.brandBlue)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appHairline)
                .frame(height: 1)
        }
    }

    private var summaryText: String {
        if isIronclawProvider {
            return isHostedIronclaw ? "Hosted git, code, shell, and research route" : "Phone-safe agent with hosted handoff"
        }
        if isNearCloudProvider {
            return "Anonymized provider route, outside TEE proof"
        }
        if councilModelNames.count > 1 {
            return councilModelNames.prefix(3).joined(separator: " · ") +
                (councilModelNames.count > 3 ? " · +" : "")
        }
        let locked = hiddenPlanLockedModelCount > 0 ? " · upgrade for \(hiddenPlanLockedModelCount) more" : ""
        return "\(modelCount) curated chat models · \(planName.capitalized) plan\(locked)"
    }

    private var providerChipTitle: String {
        if isIronclawProvider {
            return isHostedIronclaw ? "IronClaw hosted" : "IronClaw mobile"
        }
        return providerName
    }

    private var providerChipSymbol: String {
        if isIronclawProvider {
            return isHostedIronclaw ? "terminal" : "iphone"
        }
        if isNearCloudProvider {
            return "cloud"
        }
        return "lock.shield"
    }

    private var routeCostTitle: String {
        if isIronclawProvider {
            return ironclawTokenConfigured ? "Token saved" : "Connect token"
        }
        if isNearCloudProvider {
            return "Anonymized"
        }
        return "\(planName.capitalized) plan"
    }

    private var routeCostSymbol: String {
        if isIronclawProvider {
            return ironclawTokenConfigured ? "key.fill" : "key"
        }
        if isNearCloudProvider {
            return "eye.slash"
        }
        return "creditcard"
    }

    private var isIronclawProvider: Bool {
        providerName == "IronClaw"
    }

    private var isHostedIronclaw: Bool {
        selectedModelID == ModelOption.ironclawModelID
    }

    private var isNearCloudProvider: Bool {
        providerName == "NEAR Cloud"
    }
}

private struct ModelPickerRow: View {
    let model: ModelOption
    let isSelected: Bool
    let councilIndex: Int?
    let canUseInCouncil: Bool
    let showsCouncilButton: Bool
    let isPinned: Bool
    let attestationStatus: AttestationStatus
    let togglePinAction: () -> Void
    let selectAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: modelSymbol)
                .foregroundStyle(model.isEliteModel || model.isPrivateVerifiableChatModel ? Color.brandBlue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(model.metadata?.modelDescription?.isEmpty == false ? model.metadata!.modelDescription! : model.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack(spacing: 6) {
                    modelFact(title: routeFactTitle, symbolName: routeFactSymbol, tint: routeFactTint)
                    if let proofFactTitle {
                        modelFact(title: proofFactTitle, symbolName: proofFactSymbol, tint: proofFactTint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ChipFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(Array(model.capabilityBadges.prefix(2)), id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(badge == "DeepSeek alias" ? Color.brandBlue : .secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.appSecondaryBackground, in: Capsule())
                    }

                    if model.capabilityBadges.count < 2, let contextLength = model.metadata?.contextLength {
                        Text("\(contextLength.formatted()) ctx")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            VStack(spacing: 9) {
                if !showsCouncilButton {
                    Button {
                        togglePinAction()
                    } label: {
                        Image(systemName: isPinned ? "star.fill" : "star")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isPinned ? Color.primaryAction : .secondary)
                            .frame(width: 32, height: 32)
                            .background(isPinned ? Color.primaryAction.opacity(0.10) : Color.appSecondaryBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPinned ? "Unpin \(model.displayName)" : "Pin \(model.displayName)")
                }

                if isSelected, !showsCouncilButton {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.brandBlue)
                }

                if showsCouncilButton {
                    HStack(spacing: 5) {
                        Image(systemName: councilSymbol)
                            .font(.caption.weight(.bold))
                        Text(councilActionTitle)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(councilIndex == nil ? Color.brandBlue : Color.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(councilIndex == nil ? Color.brandBlue.opacity(0.08) : Color.brandBlue, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(councilIndex == nil ? Color.brandBlue.opacity(0.16) : Color.clear, lineWidth: 1)
                    }
                    .opacity(canUseInCouncil ? 1 : 0.35)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(rowIsActive ? Color.brandBlue.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !showsCouncilButton || canUseInCouncil else { return }
            selectAction()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(showsCouncilButton ? councilAccessibilityHint : "Select this model")
    }

    private var councilSymbol: String {
        councilIndex == nil ? "plus.circle.fill" : "minus.circle.fill"
    }

    private var councilActionTitle: String {
        councilIndex == nil ? "Add" : "Remove"
    }

    private var rowIsActive: Bool {
        showsCouncilButton ? councilIndex != nil : isSelected
    }

    private var councilAccessibilityHint: String {
        councilIndex == nil ? "Add this model to LLM Council" : "Remove this model from LLM Council"
    }

    private var modelSymbol: String {
        if model.isNearCloudModel {
            "cloud"
        } else if model.isEliteModel {
            "sparkles"
        } else if model.isRecommendedReasoningModel {
            "brain.head.profile"
        } else if model.isVerifiable {
            "checkmark.shield.fill"
        } else {
            "cpu"
        }
    }

    private func modelFact(title: String, symbolName: String, tint: Color) -> some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(tint.opacity(0.09), in: Capsule())
    }

    private var routeFactTitle: String {
        if model.isNearCloudModel {
            return "NEAR Cloud"
        }
        if model.isIronclawModel {
            return model.isIronclawHostedModel ? "Hosted agent" : "Phone agent"
        }
        if model.isLowerPriorityModel {
            return "Older"
        }
        return "Included"
    }

    private var routeFactSymbol: String {
        if model.isNearCloudModel {
            return "cloud"
        }
        if model.isIronclawModel {
            return "terminal"
        }
        if model.isLowerPriorityModel {
            return "tray.and.arrow.down"
        }
        return "creditcard"
    }

    private var routeFactTint: Color {
        if model.isNearCloudModel {
            return Color.brandBlue
        }
        if model.isIronclawModel {
            return Color.primaryAction
        }
        if model.isLowerPriorityModel {
            return Color.secondary
        }
        return Color.textSecondary
    }

    private var proofFactTitle: String? {
        if model.isNearCloudModel {
            return "Anonymized"
        }
        if model.isIronclawModel {
            return model.isIronclawHostedModel ? "Hosted" : "On phone"
        }
        guard model.isPrivateVerifiableChatModel else { return nil }
        switch attestationStatus.coverage(for: model.id) {
        case .covered:
            if let freshness = attestationStatus.freshness()?.shortLabel {
                return "Proof \(freshness)"
            }
            return "Proof fetched"
        case .stale:
            return "Proof stale"
        case .notCovered:
            return "Not covered"
        case .unknown:
            return "Proof not checked"
        }
    }

    private var proofFactSymbol: String {
        if model.isNearCloudModel {
            return "eye.slash"
        }
        if model.isIronclawModel {
            return model.isIronclawHostedModel ? "network" : "iphone"
        }
        switch attestationStatus.coverage(for: model.id) {
        case .covered:
            return "checkmark.shield.fill"
        case .stale:
            return "clock.badge.exclamationmark"
        case .notCovered:
            return "shield.slash"
        case .unknown:
            return "shield.lefthalf.filled"
        }
    }

    private var proofFactTint: Color {
        if model.isNearCloudModel || model.isIronclawModel {
            return Color.secondary
        }
        switch attestationStatus.coverage(for: model.id) {
        case .covered:
            return Color.trustVerified
        case .stale:
            return Color.warningState
        case .notCovered, .unknown:
            return Color.secondary
        }
    }
}

private struct ChipFlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    init(spacing: CGFloat = 6, lineSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = lineWidth == 0 ? size.width : lineWidth + spacing + size.width

            if lineWidth > 0, nextWidth > maxWidth {
                measuredWidth = max(measuredWidth, lineWidth)
                totalHeight += lineHeight + lineSpacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth = nextWidth
                lineHeight = max(lineHeight, size.height)
            }
        }

        measuredWidth = max(measuredWidth, lineWidth)
        totalHeight += lineHeight
        return CGSize(width: proposal.width ?? measuredWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let leadingSpace = x == bounds.minX ? 0 : spacing

            if x > bounds.minX, x + leadingSpace + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            let point = CGPoint(x: x + (x == bounds.minX ? 0 : spacing), y: y)
            subview.place(at: point, proposal: ProposedViewSize(width: size.width, height: size.height))
            x = point.x + size.width
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private enum SharePublicLinkExpiry: String, CaseIterable, Identifiable {
    case manual = "Manual disable"
    case sevenDays = "7 days"
    case thirtyDays = "30 days"

    var id: String { rawValue }

    var isAvailable: Bool {
        self == .manual
    }
}

private struct ShareConversationView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    let conversation: ConversationSummary
    @State private var isWorking = false
    @State private var inviteTarget = ""
    @State private var organizationPattern = ""
    @State private var selectedGroupID = ""
    @State private var groupName = ""
    @State private var groupMembers = ""
    @State private var editingShareGroup: ShareGroupInfo?
    @State private var permission: ShareGrantPermission = .read
    @State private var grantMode: ShareGrantMode = .people
    @State private var pendingDeleteID: String?
    @State private var publicLinkExpiry: SharePublicLinkExpiry = .manual
    @State private var showingPublicLinkPreview = false
    @State private var showingDisablePublicLinkConfirmation = false
    @State private var pendingSensitiveShareGrant: SensitiveShareGrant?

    private enum ShareGrantMode: String, CaseIterable, Identifiable {
        case people = "People"
        case group = "Group"
        case organization = "Organization"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .people: "person.badge.plus"
            case .group: "person.3"
            case .organization: "building.2"
            }
        }
    }

    private enum ShareGrantPermission: String, CaseIterable, Identifiable {
        case read = "Read"
        case write = "Write"

        var id: String { rawValue }
        var apiValue: String { rawValue.lowercased() }
    }

    private enum SensitiveShareGrant {
        case people
        case group
        case organization

        var label: String {
            switch self {
            case .people: "people"
            case .group: "this group"
            case .organization: "the organization"
            }
        }
    }

    private var publicURL: URL? {
        chatStore.publicURL(for: conversation)
    }

    private var publicShareEnabled: Bool {
        chatStore.shareInfo?.publicShare != nil
    }

    private var accessShares: [ConversationShareInfo] {
        chatStore.shareInfo?.shares.filter { !$0.isPublic } ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    shareHeader
                    publicLinkSection
                    grantAccessSection
                    accessListSection

                    if chatStore.isLoadingShareInfo || isWorking {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Updating share settings")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .frame(maxWidth: 560, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .background(Color.appBackground)
            .navigationTitle("Share")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await chatStore.loadShares(for: conversation)
                await chatStore.refreshShareGroups(showErrors: false)
                ensureSelectedGroup()
            }
            .onChange(of: chatStore.shareGroups) {
                ensureSelectedGroup()
            }
            .sheet(isPresented: $showingPublicLinkPreview) {
                PublicLinkPreviewView(
                    conversation: conversation,
                    messageCount: chatStore.messages.count,
                    sourceCount: publicLinkSourceCount,
                    expiry: publicLinkExpiry,
                    attestationStatus: chatStore.currentAttestationStatus,
                    isWorking: isWorking,
                    onConfirm: {
                        await enablePublicShare()
                    }
                )
            }
            .confirmationDialog(
                "Disable the public link?",
                isPresented: $showingDisablePublicLinkConfirmation,
                titleVisibility: .visible
            ) {
                Button("Disable Public Link", role: .destructive) {
                    Task { await disablePublicShare() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("People with the public URL will lose read-only access.")
            }
            .confirmationDialog(
                "Confirm shared access",
                isPresented: Binding(
                    get: { pendingSensitiveShareGrant != nil },
                    set: { if !$0 { pendingSensitiveShareGrant = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Grant Access", role: permission == .write ? .destructive : nil) {
                    guard let grant = pendingSensitiveShareGrant else { return }
                    pendingSensitiveShareGrant = nil
                    Task { await performShareGrant(grant) }
                }
                Button("Cancel", role: .cancel) {
                    pendingSensitiveShareGrant = nil
                }
            } message: {
                Text(shareGrantConfirmationMessage)
            }
        }
        .platformLargeDetent()
    }

    private var shareHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 44, height: 44)
                .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(chatStore.shareInfo?.canShare == false ? "View existing access." : "Invite people, organizations, or publish a read-only link.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var publicLinkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Public Link", systemImage: "globe")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text(publicShareEnabled ? "On" : "Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(publicShareEnabled ? Color.brandBlue : .secondary)
            }

            Menu {
                ForEach(SharePublicLinkExpiry.allCases) { expiry in
                    Button {
                        publicLinkExpiry = expiry
                    } label: {
                        Label(expiry.rawValue, systemImage: publicLinkExpiry == expiry ? "checkmark" : "clock")
                    }
                    .disabled(!expiry.isAvailable)
                }
            } label: {
                Label("Expiry: \(publicLinkExpiry.rawValue)", systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(publicShareEnabled)

            if publicShareEnabled, let publicURL {
                Text(publicURL.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 8) {
                    Button {
                        Clipboard.copy(publicURL.absoluteString)
                        chatStore.bannerMessage = "Link copied."
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandBlue)

                    Button(role: .destructive) {
                        showingDisablePublicLinkConfirmation = true
                    } label: {
                        Label("Disable", systemImage: "link.badge.minus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    showingPublicLinkPreview = true
                } label: {
                    Label("Review Public Link", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandBlue)
                .controlSize(.large)
                .disabled(chatStore.shareInfo?.canShare == false || isWorking)
            }

            Button {
                grantMode = .people
            } label: {
                Label("Invite People", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(chatStore.shareInfo?.canShare == false || isWorking)
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var grantAccessSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Grant Access", systemImage: grantMode.symbolName)
                    .font(.footnote.weight(.semibold))
                Spacer()
                Picker("Permission", selection: $permission) {
                    ForEach(ShareGrantPermission.allCases) { permission in
                        Text(permission.rawValue).tag(permission)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            Picker("Target", selection: $grantMode) {
                ForEach(ShareGrantMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch grantMode {
            case .people:
                TextField("email@company.com, alice.near", text: $inviteTarget, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .padding(11)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    requestShareGrant(.people)
                } label: {
                    Label("Invite", systemImage: "paperplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandBlue)
                .disabled(inviteTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking || chatStore.shareInfo?.canShare == false)
            case .group:
                groupAccessControls
            case .organization:
                TextField("*@near.org", text: $organizationPattern)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.plain)
                    .padding(11)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    requestShareGrant(.organization)
                } label: {
                    Label("Share Organization", systemImage: "building.2.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandBlue)
                .disabled(organizationPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking || chatStore.shareInfo?.canShare == false)
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var accessListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("People With Access", systemImage: "person.2")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text("\(accessShares.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if accessShares.isEmpty {
                Text("Only you can access this conversation unless the public link is enabled.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(accessShares) { share in
                        accessRow(share)
                        if share.id != accessShares.last?.id {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var groupAccessControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if chatStore.isLoadingShareGroups {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading groups")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else if chatStore.shareGroups.isEmpty {
                Text("Create a reusable group for frequent collaborators.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Picker("Share Group", selection: $selectedGroupID) {
                    ForEach(chatStore.shareGroups) { group in
                        Text("\(group.name) · \(group.members.count)").tag(group.id)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    requestShareGrant(.group)
                } label: {
                    Label("Share Group", systemImage: "person.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandBlue)
                .disabled(selectedGroupID.isEmpty || isWorking || chatStore.shareInfo?.canShare == false)

                VStack(spacing: 0) {
                    ForEach(chatStore.shareGroups) { group in
                        HStack(spacing: 10) {
                            Image(systemName: "person.3")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.brandBlue)
                                .frame(width: 28, height: 28)
                                .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(shareGroupSubtitle(group))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Button {
                                beginEditingShareGroup(group)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            .disabled(isWorking)
                            .accessibilityLabel("Edit Share Group")
                            Button(role: .destructive) {
                                Task { await chatStore.deleteShareGroup(group) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .disabled(isWorking)
                            .accessibilityLabel("Delete Share Group")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        if group.id != chatStore.shareGroups.last?.id {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Divider()

            if let editingShareGroup {
                HStack(spacing: 8) {
                    Label("Editing \(editingShareGroup.name)", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.brandBlue)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Cancel") {
                        cancelShareGroupEditing()
                    }
                    .font(.caption.weight(.semibold))
                    .disabled(isWorking)
                }
                .padding(.horizontal, 2)
            }

            TextField("Group name", text: $groupName)
                .textFieldStyle(.plain)
                .padding(11)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            TextField("email@company.com, alice.near", text: $groupMembers, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .padding(11)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                Task { await saveGroup() }
            } label: {
                Label(editingShareGroup == nil ? "Create Group" : "Save Group", systemImage: editingShareGroup == nil ? "plus" : "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(
                groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                groupMembers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                isWorking ||
                chatStore.shareInfo?.canShare == false
            )
        }
    }

    private func accessRow(_ share: ConversationShareInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: shareSymbol(share))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 30, height: 30)
                .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(shareDisplayName(share))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(shareSubtitle(share))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(role: .destructive) {
                Task { await removeAccess(share) }
            } label: {
                if pendingDeleteID == share.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "minus.circle")
                        .font(.body.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .disabled(isWorking || pendingDeleteID != nil || chatStore.shareInfo?.canShare == false)
            .accessibilityLabel("Remove access")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private func enablePublicShare() async {
        isWorking = true
        defer { isWorking = false }
        if let url = await chatStore.enablePublicShare(for: conversation) {
            Clipboard.copy(url.absoluteString)
        }
    }

    private func disablePublicShare() async {
        isWorking = true
        defer { isWorking = false }
        await chatStore.disablePublicShare(for: conversation)
    }

    private var shareGrantConfirmationMessage: String {
        let target = pendingSensitiveShareGrant?.label ?? "this target"
        if permission == .write {
            return "Write access lets \(target) add messages to this conversation. Confirm this is intended."
        }
        return "Organization sharing can grant access broadly. Confirm the domain and permission before continuing."
    }

    private func requestShareGrant(_ grant: SensitiveShareGrant) {
        if permission == .write || grant == .organization {
            pendingSensitiveShareGrant = grant
            return
        }
        Task { await performShareGrant(grant) }
    }

    private func performShareGrant(_ grant: SensitiveShareGrant) async {
        switch grant {
        case .people:
            await grantPeopleAccess()
        case .group:
            await grantSelectedGroupAccess()
        case .organization:
            await grantOrganizationAccess()
        }
    }

    private func grantPeopleAccess() async {
        isWorking = true
        defer { isWorking = false }
        await chatStore.grantDirectShare(
            rawRecipients: inviteTarget,
            permission: permission.apiValue,
            conversation: conversation
        )
        inviteTarget = ""
    }

    private func grantOrganizationAccess() async {
        isWorking = true
        defer { isWorking = false }
        await chatStore.grantOrganizationShare(
            emailPattern: organizationPattern,
            permission: permission.apiValue,
            conversation: conversation
        )
        organizationPattern = ""
    }

    private func saveGroup() async {
        isWorking = true
        defer { isWorking = false }
        if let editingShareGroup {
            await chatStore.updateShareGroup(editingShareGroup, name: groupName, rawMembers: groupMembers)
            cancelShareGroupEditing()
            ensureSelectedGroup()
            return
        }

        await chatStore.createShareGroup(name: groupName, rawMembers: groupMembers)
        groupName = ""
        groupMembers = ""
        ensureSelectedGroup()
    }

    private func grantSelectedGroupAccess() async {
        isWorking = true
        defer { isWorking = false }
        await chatStore.grantGroupShare(
            groupID: selectedGroupID,
            permission: permission.apiValue,
            conversation: conversation
        )
    }

    private func removeAccess(_ share: ConversationShareInfo) async {
        pendingDeleteID = share.id
        isWorking = true
        defer {
            pendingDeleteID = nil
            isWorking = false
        }
        await chatStore.removeConversationShare(share, conversation: conversation)
    }

    private func shareDisplayName(_ share: ConversationShareInfo) -> String {
        if let recipient = share.recipient {
            return recipient.value
        }
        if let pattern = share.orgEmailPattern {
            return pattern
        }
        if let groupID = share.groupID {
            return chatStore.shareGroups.first(where: { $0.id == groupID })?.name ?? "Group \(groupID)"
        }
        return share.shareType.capitalized
    }

    private func shareSubtitle(_ share: ConversationShareInfo) -> String {
        let permission = share.permission == "write" ? "Can write" : "Can read"
        switch share.shareType {
        case "direct":
            return "\(permission) · Direct"
        case "organization":
            return "\(permission) · Organization"
        case "group":
            return "\(permission) · Group"
        default:
            return permission
        }
    }

    private func shareSymbol(_ share: ConversationShareInfo) -> String {
        switch share.shareType {
        case "direct":
            return share.recipient?.kind == "near_account" ? "hexagon" : "envelope"
        case "organization":
            return "building.2"
        case "group":
            return "person.3"
        default:
            return "person"
        }
    }

    private func ensureSelectedGroup() {
        if selectedGroupID.isEmpty || !chatStore.shareGroups.contains(where: { $0.id == selectedGroupID }) {
            selectedGroupID = chatStore.shareGroups.first?.id ?? ""
        }
    }

    private func beginEditingShareGroup(_ group: ShareGroupInfo) {
        editingShareGroup = group
        groupName = group.name
        groupMembers = group.members.map(\.shareSheetFieldValue).joined(separator: ", ")
    }

    private func cancelShareGroupEditing() {
        editingShareGroup = nil
        groupName = ""
        groupMembers = ""
    }

    private func shareGroupSubtitle(_ group: ShareGroupInfo) -> String {
        let count = "\(group.members.count) member\(group.members.count == 1 ? "" : "s")"
        let preview = group.members.prefix(2).map(\.displayName).joined(separator: ", ")
        guard !preview.isEmpty else { return count }
        return "\(count) · \(preview)\(group.members.count > 2 ? ", +" : "")"
    }

    private var publicLinkSourceCount: Int {
        chatStore.activeProjectContextAttachments.count + chatStore.activeProjectContextLinks.count
    }
}

private extension ShareInviteRecipient {
    var displayName: String {
        value
    }

    var shareSheetFieldValue: String {
        value
    }
}

private struct PublicLinkPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let conversation: ConversationSummary
    let messageCount: Int
    let sourceCount: Int
    let expiry: SharePublicLinkExpiry
    let attestationStatus: AttestationStatus
    let isWorking: Bool
    let onConfirm: () async -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "globe")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.primaryAction)
                                .frame(width: 42, height: 42)
                                .background(Color.primaryAction.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text("Anyone with the URL can read this conversation.")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        AttestationStatusBadge(status: attestationStatus, modelID: nil)
                    }
                    .padding(.vertical, 4)
                }

                Section("Preview") {
                    SharePreviewRow(title: "Permission", value: "Read-only", symbolName: "eye")
                    SharePreviewRow(title: "Messages", value: "\(messageCount)", symbolName: "bubble.left.and.bubble.right")
                    SharePreviewRow(title: "Sources", value: sourceCount == 0 ? "None attached" : "\(sourceCount)", symbolName: "link")
                    SharePreviewRow(title: "Expiry", value: expiry.rawValue, symbolName: "clock")
                    SharePreviewRow(title: "Account metadata", value: "Owner identity is not added to the link preview.", symbolName: "person.crop.circle.badge.xmark")
                }

                Section {
                    Button {
                        Task {
                            await onConfirm()
                            dismiss()
                        }
                    } label: {
                        Label("Create Public Link", systemImage: "link.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primaryAction)
                    .disabled(isWorking)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .navigationTitle("Public Link Preview")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .platformMediumDetent()
    }
}

private struct SharePreviewRow: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primaryAction)
                .frame(width: 28, height: 28)
                .background(Color.primaryAction.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ShareGroupsView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var groupMembers = ""
    @State private var editingShareGroup: ShareGroupInfo?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.3")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 42, height: 42)
                            .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Share Groups")
                                .font(.headline)
                            Text("Reusable collaborator sets for conversation sharing.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Groups") {
                    if chatStore.isLoadingShareGroups {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading groups")
                                .foregroundStyle(.secondary)
                        }
                    } else if chatStore.shareGroups.isEmpty {
                        ContentUnavailableView("No share groups", systemImage: "person.3")
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(chatStore.shareGroups) { group in
                            HStack(spacing: 10) {
                                Image(systemName: "person.3")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.brandBlue)
                                    .frame(width: 30, height: 30)
                                    .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text(shareGroupSubtitle(group))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Button {
                                    beginEditing(group)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                .disabled(isWorking)
                                .accessibilityLabel("Edit Share Group")

                                Button(role: .destructive) {
                                    Task { await delete(group) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .disabled(isWorking)
                                .accessibilityLabel("Delete Share Group")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                Section(editingShareGroup == nil ? "Create Group" : "Edit Group") {
                    if let editingShareGroup {
                        HStack {
                            Label("Editing \(editingShareGroup.name)", systemImage: "pencil")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.brandBlue)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Button("Cancel") {
                                cancelEditing()
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }

                    TextField("Group name", text: $groupName)
                        .textFieldStyle(.plain)
                        .padding(11)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    TextField("email@company.com, alice.near", text: $groupMembers, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .padding(11)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button {
                        Task { await saveGroup() }
                    } label: {
                        Label(editingShareGroup == nil ? "Create Group" : "Save Group", systemImage: editingShareGroup == nil ? "plus" : "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandBlue)
                    .disabled(saveDisabled)
                }
            }
            .navigationTitle("Share Groups")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await chatStore.refreshShareGroups(showErrors: false)
            }
        }
        .platformMediumDetent()
    }

    private var saveDisabled: Bool {
        groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            groupMembers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            isWorking
    }

    private func saveGroup() async {
        isWorking = true
        defer { isWorking = false }

        if let editingShareGroup {
            await chatStore.updateShareGroup(editingShareGroup, name: groupName, rawMembers: groupMembers)
            cancelEditing()
        } else {
            await chatStore.createShareGroup(name: groupName, rawMembers: groupMembers)
            groupName = ""
            groupMembers = ""
        }
    }

    private func delete(_ group: ShareGroupInfo) async {
        isWorking = true
        defer { isWorking = false }
        await chatStore.deleteShareGroup(group)
        if editingShareGroup?.id == group.id {
            cancelEditing()
        }
    }

    private func beginEditing(_ group: ShareGroupInfo) {
        editingShareGroup = group
        groupName = group.name
        groupMembers = group.members.map(\.shareSheetFieldValue).joined(separator: ", ")
    }

    private func cancelEditing() {
        editingShareGroup = nil
        groupName = ""
        groupMembers = ""
    }

    private func shareGroupSubtitle(_ group: ShareGroupInfo) -> String {
        let count = "\(group.members.count) member\(group.members.count == 1 ? "" : "s")"
        let preview = group.members.prefix(2).map(\.displayName).joined(separator: ", ")
        guard !preview.isEmpty else { return count }
        return "\(count) · \(preview)\(group.members.count > 2 ? ", +" : "")"
    }
}

private struct RenameConversationView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Conversation Title")
                    .font(.headline)
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                Spacer()
            }
            .padding()
            .navigationTitle("Rename")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                }
            }
            .onAppear {
                title = chatStore.selectedConversationTitle
            }
        }
        .platformMediumDetent()
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        await chatStore.renameSelectedConversation(to: title)
        dismiss()
    }
}

private struct NewProjectView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var instructions = ""
    @State private var selectedPalette: ProjectPalette = .sky
    @State private var selectedIcon: ProjectIcon = .folder
    @State private var iconSearchText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ProjectIdentityPreview(
                        title: trimmedName.isEmpty ? "Untitled Project" : trimmedName,
                        subtitle: instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Sources, files, instructions, and notes" : "Instructions ready",
                        symbolName: selectedIcon.symbolName,
                        tintColor: selectedPalette.tintColor,
                        backgroundColor: selectedPalette.backgroundColor
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Project Name")
                            .font(.headline)
                        TextField("Launch research", text: $name)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Identity")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ProjectPalette.allCases) { palette in
                                    Button {
                                        selectedPalette = palette
                                    } label: {
                                        Circle()
                                            .fill(palette.tintColor)
                                            .frame(width: 30, height: 30)
                                            .overlay {
                                                Circle()
                                                    .stroke(selectedPalette == palette ? Color.primary : Color.clear, lineWidth: 2)
                                            }
                                            .padding(3)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(palette.label) project color")
                                }
                            }
                        }

                        TextField("Search icons", text: $iconSearchText)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                            ForEach(filteredProjectIcons) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon.symbolName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(selectedIcon == icon ? selectedPalette.tintColor : .secondary)
                                        .frame(height: 42)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            selectedIcon == icon ? selectedPalette.backgroundColor : Color.appSecondaryBackground,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(icon.label) project icon")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Instructions")
                            .font(.headline)
                        TextField("How should the assistant handle this workspace?", text: $instructions, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(4...8)
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Text("Project files, links, memory, and saved outputs will travel with chats in this workspace.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("New Project")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        chatStore.createProject(
                            named: name,
                            instructions: instructions,
                            iconName: selectedIcon.symbolName,
                            paletteName: selectedPalette.rawValue
                        )
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .platformMediumDetent()
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredProjectIcons: [ProjectIcon] {
        ProjectIcon.allCases.filter { $0.matches(iconSearchText) }
    }

}

private struct EditProjectView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    let project: ChatProject
    @State private var name: String
    @State private var instructions: String
    @State private var selectedPalette: ProjectPalette
    @State private var selectedIcon: ProjectIcon
    @State private var iconSearchText = ""

    init(project: ChatProject) {
        self.project = project
        _name = State(initialValue: project.name)
        _instructions = State(initialValue: project.instructions)
        _selectedPalette = State(initialValue: project.projectPalette)
        _selectedIcon = State(
            initialValue: ProjectIcon.allCases.first { $0.symbolName == project.projectIconName } ?? .folder
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ProjectIdentityPreview(
                        title: trimmedName.isEmpty ? project.name : trimmedName,
                        subtitle: projectSubtitle,
                        symbolName: selectedIcon.symbolName,
                        tintColor: selectedPalette.tintColor,
                        backgroundColor: selectedPalette.backgroundColor
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Project Name")
                            .font(.headline)
                        TextField("Project name", text: $name)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Color")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ProjectPalette.allCases) { palette in
                                    Button {
                                        selectedPalette = palette
                                    } label: {
                                        Circle()
                                            .fill(palette.tintColor)
                                            .frame(width: 30, height: 30)
                                            .overlay {
                                                Circle()
                                                    .stroke(selectedPalette == palette ? Color.primary : Color.clear, lineWidth: 2)
                                            }
                                            .padding(3)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(palette.label) project color")
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Icon")
                            .font(.headline)
                        TextField("Search icons", text: $iconSearchText)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                            ForEach(filteredProjectIcons) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon.symbolName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(selectedIcon == icon ? selectedPalette.tintColor : .secondary)
                                        .frame(height: 42)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            selectedIcon == icon ? selectedPalette.backgroundColor : Color.appSecondaryBackground,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(icon.label) project icon")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Instructions")
                            .font(.headline)
                        TextField("How should the assistant handle this workspace?", text: $instructions, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(4...8)
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Edit Project")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        chatStore.updateProject(
                            project.id,
                            name: name,
                            iconName: selectedIcon.symbolName,
                            paletteName: selectedPalette.rawValue,
                            instructions: instructions
                        )
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .platformMediumDetent()
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredProjectIcons: [ProjectIcon] {
        ProjectIcon.allCases.filter { $0.matches(iconSearchText) }
    }

    private var projectSubtitle: String {
        var parts: [String] = []
        if !project.conversationIDs.isEmpty {
            parts.append("\(project.conversationIDs.count) chat\(project.conversationIDs.count == 1 ? "" : "s")")
        }
        let sourceCount = project.links.count + project.attachments.count
        if sourceCount > 0 {
            parts.append("\(sourceCount) source\(sourceCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Project identity and instructions" : parts.joined(separator: " / ")
    }
}

private struct ProjectIdentityPreview: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let tintColor: Color
    let backgroundColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tintColor)
                .frame(width: 42, height: 42)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        }
    }
}

private struct ProjectFilesView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingFileImporter = false
    @State private var projectInstructions = ""
    @State private var projectMemory = ""
    @State private var projectLinkTitle = ""
    @State private var projectLinkURL = ""
    @State private var showingAddLinkForm = false
    @State private var showingFileLibrary = false
    @State private var selectedTab: ProjectContextTab = .sources
    @State private var previewFile: RemoteFileInfo?
    @State private var pendingLinkDelete: ProjectLink?
    @State private var pendingNoteDelete: ProjectNote?
    @State private var pendingAttachmentDelete: ChatAttachment?
    @State private var pendingRemoteFileDelete: RemoteFileInfo?

    private enum ProjectContextTab: String, CaseIterable, Identifiable {
        case sources = "Sources"
        case instructions = "Instructions"
        case notes = "Notes"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection

                Section {
                    Picker("Project Context", selection: $selectedTab) {
                        ForEach(ProjectContextTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Project context section")
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                selectedTabContent
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Project Context")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.pdf, .plainText, .text, .commaSeparatedText, .json, .data],
                allowsMultipleSelection: true
            ) { result in
                if case let .success(urls) = result {
                    Task {
                        for url in urls.prefix(12) {
                            await chatStore.addProjectAttachment(from: url)
                        }
                    }
                }
            }
            .sheet(item: $previewFile) { file in
                RemoteFilePreviewView(file: file)
                    .environmentObject(chatStore)
            }
            .confirmationDialog(
                "Remove this source?",
                isPresented: pendingLinkDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Remove Source", role: .destructive) {
                    if let pendingLinkDelete {
                        chatStore.deleteProjectLink(pendingLinkDelete)
                    }
                    pendingLinkDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingLinkDelete = nil
                }
            }
            .confirmationDialog(
                "Remove this note?",
                isPresented: pendingNoteDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Remove Note", role: .destructive) {
                    if let pendingNoteDelete {
                        chatStore.deleteProjectNote(pendingNoteDelete)
                    }
                    pendingNoteDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingNoteDelete = nil
                }
            }
            .confirmationDialog(
                "Remove this file from the project?",
                isPresented: pendingAttachmentDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Remove File", role: .destructive) {
                    if let pendingAttachmentDelete {
                        chatStore.removeProjectAttachment(pendingAttachmentDelete)
                    }
                    pendingAttachmentDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingAttachmentDelete = nil
                }
            }
            .confirmationDialog(
                "Delete this private file?",
                isPresented: pendingRemoteFileDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Delete File", role: .destructive) {
                    if let pendingRemoteFileDelete {
                        Task { await chatStore.deleteRemoteFile(pendingRemoteFileDelete) }
                    }
                    pendingRemoteFileDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingRemoteFileDelete = nil
                }
            } message: {
                Text("This removes the uploaded file from your private file library.")
            }
        }
        .platformLargeDetent()
        .onAppear {
            syncProjectFields()
        }
        .onChange(of: chatStore.selectedProject?.id) {
            syncProjectFields()
        }
        .task {
            await chatStore.refreshRemoteFiles(showErrors: false)
        }
    }

    private var pendingLinkDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingLinkDelete != nil },
            set: { if !$0 { pendingLinkDelete = nil } }
        )
    }

    private var pendingNoteDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingNoteDelete != nil },
            set: { if !$0 { pendingNoteDelete = nil } }
        )
    }

    private var pendingAttachmentDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingAttachmentDelete != nil },
            set: { if !$0 { pendingAttachmentDelete = nil } }
        )
    }

    private var pendingRemoteFileDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingRemoteFileDelete != nil },
            set: { if !$0 { pendingRemoteFileDelete = nil } }
        )
    }

    private var headerSection: some View {
        Section {
            ProjectContextHeroCard(
                title: chatStore.selectedProject?.name ?? "Project",
                symbolName: chatStore.selectedProject?.projectIconName ?? ProjectIcon.folder.symbolName,
                tintColor: chatStore.selectedProject?.tintColor ?? Color.trustFreshAccent,
                createdAt: chatStore.selectedProject?.createdAt,
                chats: chatStore.selectedProject?.conversationIDs.count ?? 0,
                sources: projectSourceCount,
                notes: chatStore.selectedProjectNotes.count,
                hasInstructions: !chatStore.selectedProjectInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)

            if !projectKnowledgeItems.isEmpty {
                ProjectKnowledgeSnapshotCard(items: projectKnowledgeItems)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
    }

    private var projectKnowledgeItems: [ProjectKnowledgeSnapshotCard.Item] {
        guard chatStore.selectedProject != nil else { return [] }
        var items: [ProjectKnowledgeSnapshotCard.Item] = []
        let instructions = chatStore.selectedProjectInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let memory = chatStore.selectedProjectMemorySummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            items.append(ProjectKnowledgeSnapshotCard.Item(symbolName: "text.alignleft", title: "Instructions", detail: Self.compactPreview(instructions)))
        }
        if !memory.isEmpty {
            items.append(ProjectKnowledgeSnapshotCard.Item(symbolName: "brain.head.profile", title: "Memory", detail: Self.compactPreview(memory)))
        }
        if !chatStore.selectedProjectLinks.isEmpty || !chatStore.selectedProjectAttachments.isEmpty {
            let linkHosts = chatStore.selectedProjectLinks
                .compactMap(\.host)
                .prefix(2)
                .joined(separator: ", ")
            let fileNames = chatStore.selectedProjectAttachments
                .map(\.name)
                .prefix(2)
                .joined(separator: ", ")
            let sourceParts = [linkHosts, fileNames].filter { !$0.isEmpty }
            let fallback = "\(projectSourceCount) saved source\(projectSourceCount == 1 ? "" : "s")"
            items.append(ProjectKnowledgeSnapshotCard.Item(symbolName: "folder.badge.gearshape", title: "Sources", detail: sourceParts.isEmpty ? fallback : sourceParts.joined(separator: " / ")))
        }
        if let note = chatStore.selectedProjectNotes.first {
            items.append(ProjectKnowledgeSnapshotCard.Item(symbolName: "bookmark", title: "Latest note", detail: Self.compactPreview(note.title.isEmpty ? note.text : note.title)))
        }
        return Array(items.prefix(3))
    }

    private static func compactPreview(_ text: String) -> String {
        let collapsed = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let clipped = String(collapsed.prefix(104))
        return collapsed.count > clipped.count ? "\(clipped)..." : clipped
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .sources:
            sourcesSections
        case .instructions:
            guidanceSections
        case .notes:
            savedSections
        }
    }

    @ViewBuilder
    private var sourcesSections: some View {
        Section(projectSourceCount == 0 ? "Sources" : "Sources (\(projectSourceCount))") {
            if projectSourceCount == 0 {
                ProjectContextEmptyActionRow(
                    title: "No sources yet",
                    message: "Add a link or file so project chats can use the same context.",
                    systemImage: "link.badge.plus"
                ) {
                    Button {
                        showingAddLinkForm = true
                    } label: {
                        Label("Add Link", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandBlue)

                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Add Files", systemImage: "paperclip")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            } else {
                ForEach(chatStore.selectedProjectLinks) { link in
                    ProjectLinkRow(link: link) {
                        pendingLinkDelete = link
                    }
                }

                ForEach(chatStore.selectedProjectAttachments) { attachment in
                    ProjectAttachmentRow(
                        attachment: attachment,
                        freshnessText: attachmentFreshnessText(for: attachment)
                    ) {
                        pendingAttachmentDelete = attachment
                    }
                }
            }
        }

        Section("Add") {
            if showingAddLinkForm {
                addLinkForm
            } else {
                Button {
                    showingAddLinkForm = true
                } label: {
                    ProjectContextActionRow(
                        title: "Add Link",
                        subtitle: "Save a URL as reusable project context.",
                        systemImage: "plus.circle"
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                showingFileImporter = true
            } label: {
                ProjectContextActionRow(
                    title: chatStore.isUploadingAttachment ? "Uploading Files" : "Add Files",
                    subtitle: "Upload documents directly into this project.",
                    systemImage: chatStore.isUploadingAttachment ? "arrow.triangle.2.circlepath" : "paperclip"
                )
            }
            .buttonStyle(.plain)
            .disabled(chatStore.isUploadingAttachment)

            Button {
                showingFileLibrary.toggle()
                if showingFileLibrary, chatStore.remoteFiles.isEmpty {
                    Task { await chatStore.refreshRemoteFiles(showErrors: false) }
                }
            } label: {
                ProjectContextActionRow(
                    title: showingFileLibrary ? "Hide File Library" : "Browse File Library",
                    subtitle: "Add existing uploaded files to this project.",
                    systemImage: showingFileLibrary ? "chevron.up.circle" : "tray.full"
                )
            }
            .buttonStyle(.plain)
        }

        if showingFileLibrary {
            fileLibrarySections
        }
    }

    private var addLinkForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Source title", text: $projectLinkTitle)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            TextField("https://example.com/report", text: $projectLinkURL)
                .textFieldStyle(.plain)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Text("Saved links stay with this project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Cancel") {
                    resetProjectLinkForm()
                    showingAddLinkForm = false
                }
                .buttonStyle(.borderless)
                Button("Add") {
                    chatStore.addSelectedProjectLink(title: projectLinkTitle, url: projectLinkURL)
                    resetProjectLinkForm()
                    showingAddLinkForm = false
                }
                .buttonStyle(.bordered)
                .disabled(projectLinkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var fileLibrarySections: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "tray.full")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.primaryAction)
                        .frame(width: 34, height: 34)
                        .background(Color.primaryAction.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("File Library")
                            .font(.headline)
                        Text("Use existing uploaded files as project sources.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Button {
                        Task { await chatStore.refreshRemoteFiles(showErrors: true) }
                    } label: {
                        Image(systemName: chatStore.isLoadingRemoteFiles ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.borderless)
                    .disabled(chatStore.isLoadingRemoteFiles)
                    .accessibilityLabel(chatStore.isLoadingRemoteFiles ? "Refreshing Files" : "Refresh Files")
                }
            }
            .padding(.vertical, 3)
        }

        Section("Uploaded Files") {
            if chatStore.isLoadingRemoteFiles && chatStore.remoteFiles.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading private files")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 18)
            } else if chatStore.remoteFiles.isEmpty {
                ProjectContextEmptyActionRow(
                    title: "No uploaded files",
                    message: "Upload a file into this project to make it reusable here.",
                    systemImage: "tray"
                ) {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Add Files", systemImage: "paperclip")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandBlue)

                    Button {
                        Task { await chatStore.refreshRemoteFiles(showErrors: true) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(chatStore.isLoadingRemoteFiles)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            } else {
                ForEach(chatStore.remoteFiles) { file in
                    RemoteFileRow(
                        file: file,
                        onPreview: { previewFile = file },
                        onAttach: { chatStore.attachRemoteFileToPrompt(file) },
                        onAddToProject: { chatStore.addRemoteFileToSelectedProject(file) },
                        onDelete: {
                            pendingRemoteFileDelete = file
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var guidanceSections: some View {
        Section("Instructions") {
            TextField("How should the assistant handle this project?", text: $projectInstructions, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(4...8)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Text("Used with every request in this project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Save") {
                    chatStore.updateSelectedProjectInstructions(projectInstructions)
                }
                .buttonStyle(.bordered)
                .disabled(!instructionsChanged)
            }
        }

        Section("Project Notes") {
            TextField("What should the assistant remember about this project?", text: $projectMemory, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(4...10)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Text("Saved locally and injected into every project request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Save") {
                    chatStore.updateSelectedProjectMemory(projectMemory)
                }
                .buttonStyle(.bordered)
                .disabled(!memoryChanged)
            }
        }
    }

    @ViewBuilder
    private var savedSections: some View {
        Section("Notes") {
            if chatStore.selectedProjectNotes.isEmpty {
                ProjectContextEmptyActionRow(
                    title: "No notes yet",
                    message: "Save useful assistant answers from chat to keep them with this project.",
                    systemImage: "bookmark"
                ) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back to Chat", systemImage: "bubble.left")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandBlue)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            } else {
                ForEach(chatStore.selectedProjectNotes) { note in
                    ProjectNoteRow(note: note) {
                        pendingNoteDelete = note
                    }
                }
            }
        }
    }

    private var projectSourceCount: Int {
        chatStore.selectedProjectLinks.count + chatStore.selectedProjectAttachments.count
    }

    private var instructionsChanged: Bool {
        projectInstructions.trimmingCharacters(in: .whitespacesAndNewlines) !=
            chatStore.selectedProjectInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var memoryChanged: Bool {
        projectMemory.trimmingCharacters(in: .whitespacesAndNewlines) !=
            chatStore.selectedProjectMemorySummary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func syncProjectFields() {
        projectInstructions = chatStore.selectedProjectInstructions
        projectMemory = chatStore.selectedProjectMemorySummary
    }

    private func resetProjectLinkForm() {
        projectLinkTitle = ""
        projectLinkURL = ""
    }

    private func attachmentFreshnessText(for attachment: ChatAttachment) -> String? {
        guard let remoteFile = chatStore.remoteFiles.first(where: { $0.id == attachment.id }) else {
            return nil
        }
        return ProjectContextFreshness.label(for: remoteFile.createdAt, prefix: "Added")
    }

}

private struct ProjectKnowledgeSnapshotCard: View {
    struct Item: Identifiable, Hashable {
        let id = UUID()
        let symbolName: String
        let title: String
        let detail: String
    }

    let items: [Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("What this project knows", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: item.symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 24, height: 24)
                            .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(item.detail)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}

private struct ProjectContextHeroCard: View {
    let title: String
    let symbolName: String
    let tintColor: Color
    let createdAt: Date?
    let chats: Int
    let sources: Int
    let notes: Int
    let hasInstructions: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tintColor)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(metadataText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Circle()
                        .fill(isActive ? Color.brandSky : Color.brandGrey)
                        .frame(width: 7, height: 7)
                    Text(isActive ? "Active" : "Ready")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(.white.opacity(0.12), in: Capsule())
            }

            if metrics.isEmpty {
                ProjectContextHeroMetric(title: "Add sources", symbolName: "plus.circle", active: false)
            } else {
                HStack(spacing: 7) {
                    ForEach(metrics) { metric in
                        ProjectContextHeroMetric(title: metric.title, symbolName: metric.symbolName, active: true)
                    }
                }
            }
        }
        .padding(14)
        .background {
            CommandCardBackground(cornerRadius: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
        .shadow(color: Color.brandBlue.opacity(0.14), radius: 18, y: 8)
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }

    private var isActive: Bool {
        sources > 0 || notes > 0 || hasInstructions
    }

    private var metadataText: String {
        var parts: [String] = []
        if let createdAt {
            parts.append("Created \(ProjectContextFreshness.relativeDateText(for: createdAt))")
        }
        if chats > 0 {
            parts.append(countLabel(chats, singular: "chat"))
        }
        if parts.isEmpty {
            return "Sources, instructions, and notes for this workspace"
        }
        return parts.joined(separator: " / ")
    }

    private var metrics: [HeroMetric] {
        var items: [HeroMetric] = []
        if sources > 0 {
            items.append(HeroMetric(title: countLabel(sources, singular: "source"), symbolName: "link"))
        }
        if hasInstructions {
            items.append(HeroMetric(title: "Instructions", symbolName: "text.alignleft"))
        }
        if notes > 0 {
            items.append(HeroMetric(title: countLabel(notes, singular: "note"), symbolName: "bookmark"))
        }
        return items
    }

    private struct HeroMetric: Identifiable {
        let id = UUID()
        let title: String
        let symbolName: String
    }
}

private struct ProjectContextHeroMetric: View {
    let title: String
    let symbolName: String
    let active: Bool

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(active ? Color.brandSky : .white.opacity(0.64))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(.white.opacity(active ? 0.14 : 0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum ProjectContextFreshness {
    static func label(for timeInterval: TimeInterval?, prefix: String) -> String? {
        guard let timeInterval else { return nil }
        return label(for: Date(timeIntervalSince1970: timeInterval), prefix: prefix)
    }

    static func label(for date: Date, prefix: String) -> String {
        "\(prefix) \(relativeDateText(for: date))"
    }

    static func relativeDateText(for date: Date) -> String {
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 {
            return "just now"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60))m ago"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3600))h ago"
        }
        if elapsed < 604_800 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct ProjectContextActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 28, height: 28)
                .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ProjectContextEmptyActionRow<Actions: View>: View {
    let title: String
    let message: String
    let systemImage: String
    let actions: Actions

    init(
        title: String,
        message: String,
        systemImage: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 38, height: 38)
                .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                actions
            }
            .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

private struct ProjectAttachmentRow: View {
    let attachment: ChatAttachment
    let freshnessText: String?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: attachment.systemImageName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove File")
        }
        .padding(.vertical, 3)
    }

    private var detailText: String {
        var parts = [attachment.displayKind]
        if let displaySize = attachment.displaySize {
            parts.append(displaySize)
        }
        if let freshnessText {
            parts.append(freshnessText)
        }
        return parts.joined(separator: " / ")
    }
}

private struct ProjectNoteRow: View {
    let note: ProjectNote
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bookmark.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(note.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(note.createdAt, style: .date)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                Clipboard.copy(note.text)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Copy Note")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete Note")
        }
        .padding(.vertical, 3)
    }
}

private struct ProjectLinkRow: View {
    @Environment(\.openURL) private var openURL
    let link: ProjectLink
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "link")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(link.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(link.urlString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            if let url = link.url {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open Link")
            }

            Button {
                Clipboard.copy(link.urlString)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Copy Link")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete Link")
        }
        .padding(.vertical, 3)
    }

    private var detailText: String {
        let host = link.host ?? link.urlString
        return "\(host) / \(ProjectContextFreshness.label(for: link.createdAt, prefix: "Added"))"
    }
}

private struct RemoteFileRow: View {
    let file: RemoteFileInfo
    let onPreview: () -> Void
    let onAttach: () -> Void
    let onAddToProject: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.systemImageName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let freshnessText = ProjectContextFreshness.label(for: file.createdAt, prefix: "Uploaded") {
                    Text(freshnessText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button(action: onPreview) {
                Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Preview File")

            Menu {
                Button(action: onAttach) {
                    Label("Attach to Prompt", systemImage: "paperclip")
                }
                Button(action: onAddToProject) {
                    Label("Add to Project", systemImage: "folder.badge.plus")
                }
                Button(action: onPreview) {
                    Label("Preview", systemImage: "eye")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete from NEAR", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("File Actions")
        }
        .padding(.vertical, 3)
    }

    private var detailText: String {
        if let displaySize = file.displaySize {
            return "\(file.displayKind) / \(displaySize)"
        }
        return file.displayKind
    }
}

private struct RemoteFilePreviewView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    let file: RemoteFileInfo

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    previewBody
                }
                .padding(16)
            }
            .background(Color.appBackground)
            .navigationTitle("File Preview")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            chatStore.attachRemoteFileToPrompt(file)
                        } label: {
                            Label("Attach to Prompt", systemImage: "paperclip")
                        }
                        Button {
                            chatStore.addRemoteFileToSelectedProject(file)
                        } label: {
                            Label("Add to Project", systemImage: "folder.badge.plus")
                        }
                        if let preview = chatStore.remoteFilePreview, preview.id == file.id {
                            Button {
                                Clipboard.copy(preview.text)
                            } label: {
                                Label("Copy Preview", systemImage: "doc.on.doc")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("File Preview Actions")
                }
            }
            .task {
                await chatStore.previewRemoteFile(file)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: file.systemImageName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 40, height: 40)
                .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(file.name)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            Text(headerDetail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var previewBody: some View {
        if chatStore.isLoadingRemoteFilePreview {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading preview")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 28)
        } else if let preview = chatStore.remoteFilePreview, preview.id == file.id {
            VStack(alignment: .leading, spacing: 10) {
                if preview.isTruncated {
                    Label("Showing the first \(ByteCountFormatter.string(fromByteCount: Int64(preview.byteCount), countStyle: .file)) preview window.", systemImage: "scissors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(preview.text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        } else {
            ContentUnavailableView("No preview available", systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }

    private var headerDetail: String {
        var parts = [file.displayKind]
        if let displaySize = file.displaySize {
            parts.append(displaySize)
        }
        if let freshnessText = ProjectContextFreshness.label(for: file.createdAt, prefix: "Uploaded") {
            parts.append(freshnessText)
        }
        return parts.joined(separator: " · ")
    }
}

private struct ArchivedChatsView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingArchiveExporter = false
    @State private var archiveDocument = ConversationExportDocument()

    private var archived: [ConversationSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chatStore.archivedConversations }
        return chatStore.archivedConversations.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
                $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private var archivedJSON: String {
        guard let data = try? JSONEncoder().encode(chatStore.archivedConversations),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: prettyData, encoding: .utf8) else {
            return "[]"
        }
        return pretty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "archivebox")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(chatStore.archivedConversations.count) archived conversations")
                                .font(.headline)
                            Text("Restore chats when you need them back, or delete them permanently.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Conversations") {
                    if archived.isEmpty {
                        ContentUnavailableView("No archived conversations", systemImage: "archivebox")
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(archived) { conversation in
                            HStack(spacing: 10) {
                                Image(systemName: "bubble.left")
                                    .foregroundStyle(Color.brandBlue)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conversation.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    if let createdAt = conversation.createdAt {
                                        Text(Date(timeIntervalSince1970: createdAt), style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 0)

                                Button {
                                    chatStore.unarchiveConversation(conversation)
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Unarchive")

                                Button(role: .destructive) {
                                    chatStore.requestDeleteConversation(conversation)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Delete")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                if !chatStore.archivedConversations.isEmpty {
                    Section {
                        Button {
                            chatStore.unarchiveAllConversations()
                        } label: {
                            Label("Unarchive All", systemImage: "arrow.uturn.backward.circle")
                        }

                        Button {
                            Clipboard.copy(archivedJSON)
                            chatStore.bannerMessage = "Archived JSON copied."
                        } label: {
                            Label("Copy Archive JSON", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            archiveDocument = ConversationExportDocument(data: Data(archivedJSON.utf8))
                            showingArchiveExporter = true
                        } label: {
                            Label("Export Archive JSON", systemImage: "square.and.arrow.up.on.square")
                        }
                    }
                }
            }
            .navigationTitle("Archived")
            .platformInlineNavigationTitle()
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search archived chats")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onChange(of: chatStore.openSelectedConversationToken) { _, token in
                if token != nil {
                    dismiss()
                }
            }
            .fileExporter(
                isPresented: $showingArchiveExporter,
                document: archiveDocument,
                contentType: .json,
                defaultFilename: archiveFilename
            ) { result in
                switch result {
                case .success:
                    chatStore.bannerMessage = "Archive JSON exported."
                case let .failure(error):
                    chatStore.bannerMessage = error.localizedDescription
                }
            }
        }
    }

    private var archiveFilename: String {
        let date = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return "near-private-chat-archive-\(date).json"
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
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.conversation.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text("\(snapshot.messages.count) messages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if snapshot.canWrite {
                    Button {
                        chatStore.openSharedPreviewForWriting()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Open shared conversation for writing")
                }

                Button {
                    chatStore.cloneSharedPreviewToChat()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Copy and Continue")

                Button {
                    Clipboard.copy(transcript)
                } label: {
                    Image(systemName: "doc.text")
                }
                .accessibilityLabel("Copy Transcript")
            }
            .padding()

            Divider()

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
}

private struct SharedWithMeView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "person.2")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 34, height: 34)
                            .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Shared With Me")
                                .font(.headline)
                            Text("Conversations others shared with your NEAR account.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
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
        HStack(spacing: 10) {
            Image(systemName: item.canWrite ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 30, height: 30)
                .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        var parts = [item.canWrite ? "Can write" : "Read only"]
        if let createdAt = item.createdAt {
            parts.append(Date(timeIntervalSince1970: createdAt).formatted(date: .abbreviated, time: .omitted))
        }
        if let error = item.error, !error.isEmpty {
            parts.append(error)
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
            await chatStore.openSharedConversation(from: item.conversationID, knownCanWrite: item.canWrite)
        }
    }
}

private struct AccountSettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    let onRunSetupAgain: () -> Void
    @State private var systemPrompt = ""
    @State private var webSearchEnabled = true
    @State private var largeTextAsFileEnabled = true
    @State private var temperature = ""
    @State private var topP = ""
    @State private var maxTokens = ""
    @State private var reasoningEffort: ModelReasoningEffort = .automatic
    @State private var nearCloudAPIKey = ""
    @State private var ironclawEnabled = false
    @State private var ironclawEndpoint = ""
    @State private var ironclawToken = ""
    @State private var ironclawThreadID = ""
    @State private var isSavingSettings = false
    @State private var showingChatImporter = false
    @State private var showingShareGroups = false
    @State private var showingCapabilities = false
    @State private var isImportingChats = false
    @State private var powerToolsUnlocked = false
    @FocusState private var focusedPowerToolField: PowerToolField?

    private enum PowerToolField: Hashable {
        case nearCloudKey
        case ironclawEndpoint
        case temperature
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.brandBlue.opacity(0.13))
                            .frame(width: 44, height: 44)
                            .overlay {
                                Text(String(sessionStore.displayName.prefix(1)).uppercased())
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(Color.brandBlue)
                            }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(sessionStore.displayName)
                                .font(.headline)
                                .lineLimit(1)
                            if let email = sessionStore.profile?.user.email {
                                Text(email)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Capabilities") {
                    Button {
                        showingCapabilities = true
                    } label: {
                        CapabilitiesEntryRow(
                            statusLine: capabilitySummary,
                            detail: "See what is ready now, what needs setup, and which routes keep proof."
                        )
                    }
                    .buttonStyle(.plain)
                }

                Section("Composer Setup") {
                    Button {
                        if let accountID = sessionStore.setupAccountID {
                            UserSetupStorage.clearCompletion(for: accountID)
                        }
                        dismiss()
                        onRunSetupAgain()
                    } label: {
                        Label("Run Setup Again", systemImage: "slider.horizontal.3")
                    }
                    Text("Keeps your chats, projects, and account. It only updates source, model, and starter defaults.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showsPowerTools {
                    Section("Developer Diagnostics") {
                        if chatStore.diagnosticChecks.isEmpty {
                            InfoRow(title: "Preflight", value: "Run before demos to verify models, web, IronClaw, and keys.")
                        } else {
                            ForEach(chatStore.diagnosticChecks) { check in
                                DiagnosticCheckRow(check: check)
                            }
                        }

                        Button {
                            Task { await chatStore.runDiagnostics() }
                        } label: {
                            Label(chatStore.isRunningDiagnostics ? "Running Diagnostics" : "Run Full Diagnostics", systemImage: "stethoscope")
                        }
                        .disabled(chatStore.isRunningDiagnostics)
                    }
                }

                Section("Composer") {
                    Toggle("Web Search", isOn: $webSearchEnabled)
                    Toggle("Large Paste as File", isOn: $largeTextAsFileEnabled)

                    TextField("System prompt", text: $systemPrompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...8)
                        .padding(10)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                }

                Section("Privacy") {
                    Button {
                        showingChatImporter = true
                    } label: {
                        Label(isImportingChats ? "Importing Chats" : "Import Chats", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isImportingChats)
                }

                Section("Sharing") {
                    Button {
                        showingShareGroups = true
                    } label: {
                        Label("Manage Share Groups", systemImage: "person.3")
                    }
                }

                Section("Models & Billing") {
                    InfoRow(title: "Status", value: chatStore.billingSnapshot?.summary ?? "Not loaded")
                    if let active = chatStore.billingSnapshot?.activeSubscription {
                        InfoRow(title: "Provider", value: active.provider)
                        if let currentPeriodEnd = active.currentPeriodEnd {
                            InfoRow(title: "Renews", value: currentPeriodEnd)
                        }
                    }
                    ForEach(Array((chatStore.billingSnapshot?.plans ?? []).prefix(3))) { plan in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.name)
                                .font(.subheadline.weight(.semibold))
                            Text(planDetail(plan))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        Task { await chatStore.refreshBilling() }
                    } label: {
                        Label(chatStore.isLoadingBilling ? "Refreshing Billing" : "Refresh Billing", systemImage: "creditcard")
                    }
                    .disabled(chatStore.isLoadingBilling)
                }

                if showsPowerTools {
                    Section("Developer") {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 12) {
                                InfoRow(title: "Endpoint", value: AppConfiguration.production.baseURL.absoluteString, monospaced: true)
                                InfoRow(title: "Callback", value: AppConfiguration.production.callbackURL.absoluteString, monospaced: true)
                                InfoRow(title: "Auth", value: sessionStore.session?.sessionID.isEmpty == false ? "Browser session" : "Session token")

                                Divider()

                                AdvancedParamField(
                                    title: "Temperature",
                                    detail: "0-2",
                                    placeholder: "Default",
                                    text: $temperature,
                                    keyboard: .decimalPad
                                )
                                .focused($focusedPowerToolField, equals: .temperature)
                                AdvancedParamField(
                                    title: "Top P",
                                    detail: "0-1",
                                    placeholder: "Default",
                                    text: $topP,
                                    keyboard: .decimalPad
                                )
                                AdvancedParamField(
                                    title: "Max Tokens",
                                    detail: "1-200000",
                                    placeholder: "Default",
                                    text: $maxTokens,
                                    keyboard: .numberPad
                                )
                                InfoRow(title: "Active", value: advancedParams.summary)

                                HStack {
                                    Button {
                                        Task { await saveChatSettings() }
                                    } label: {
                                        Label(isSavingSettings ? "Saving" : "Save", systemImage: "checkmark.circle")
                                    }
                                    .disabled(isSavingSettings)

                                    Spacer()

                                    Button {
                                        temperature = ""
                                        topP = ""
                                        maxTokens = ""
                                        reasoningEffort = .automatic
                                    } label: {
                                        Label("Reset", systemImage: "arrow.counterclockwise")
                                    }
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            Label("Connection & Advanced Params", systemImage: "hammer")
                        }
                    }

                    Section("Models") {
                        InfoRow(
                            title: "NEAR Cloud models",
                            value: chatStore.nearCloudKeyConfigured ? "API key saved" : "Add API key",
                            monospaced: false
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Reasoning effort", systemImage: "brain.head.profile")
                                .font(.subheadline.weight(.semibold))
                            Picker("Reasoning effort", selection: $reasoningEffort) {
                                ForEach(ModelReasoningEffort.allCases) { effort in
                                    Text(effort.title).tag(effort)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text(reasoningEffort.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Applied to NEAR Cloud chat requests as a reasoning budget when the provider supports it. Auto omits the field.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                Task { await saveChatSettings() }
                            } label: {
                                Label(isSavingSettings ? "Saving" : "Save Cloud Defaults", systemImage: "checkmark.circle")
                            }
                            .disabled(isSavingSettings)
                        }
                        .padding(.vertical, 4)

                        SecureField("sk-...", text: $nearCloudAPIKey)
                            .tokenInputTraits()
                            .focused($focusedPowerToolField, equals: .nearCloudKey)

                        HStack {
                            Button {
                                chatStore.saveNearCloudAPIKey(nearCloudAPIKey)
                                nearCloudAPIKey = ""
                            } label: {
                                Label("Save Key", systemImage: "key")
                            }
                            .disabled(nearCloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Spacer()

                            if chatStore.nearCloudKeyConfigured {
                                Button(role: .destructive) {
                                    chatStore.clearNearCloudAPIKey()
                                    nearCloudAPIKey = ""
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Section("Integrations") {
                        InfoRow(title: "Status", value: chatStore.ironclawStatusText)
                        Toggle("Enable Hosted Agent", isOn: $ironclawEnabled)

                        IronclawBridgeReadinessCard(
                            endpointConnected: chatStore.ironclawRemoteWorkstationAvailable,
                            tokenConfigured: chatStore.ironclawTokenConfigured,
                            lastVerifiedAt: chatStore.ironclawLastVerifiedAt,
                            isChecking: chatStore.isTestingIronclawWorkstation,
                            toolNames: chatStore.ironclawToolNames
                        )

                        TextField("https://your-ironclaw.example.com", text: $ironclawEndpoint)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .tokenInputTraits()
                            .focused($focusedPowerToolField, equals: .ironclawEndpoint)

                        SecureField(chatStore.ironclawTokenConfigured ? "Token saved" : "Bearer token", text: $ironclawToken)
                            .tokenInputTraits()

                        TextField("Optional thread id", text: $ironclawThreadID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .tokenInputTraits()

                        Text("Use a public HTTPS bridge from your computer, for example Cloudflare Tunnel, Tailscale Funnel, or ngrok. Direct LAN and localhost URLs are blocked on iPhone builds. Use Tools to verify shell/git before a serious run.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button {
                                saveIronclawBridge()
                            } label: {
                                Label("Save Bridge", systemImage: "point.3.connected.trianglepath.dotted")
                            }

                            Spacer()

                            Button {
                                Task { await chatStore.testIronclawConnection() }
                            } label: {
                                Label(chatStore.isTestingIntegration ? "Testing" : "Test", systemImage: "checkmark.circle")
                            }
                            .disabled(chatStore.isTestingIntegration)

                            Button {
                                Task { await chatStore.testIronclawWorkstation() }
                            } label: {
                                Label(chatStore.isTestingIronclawWorkstation ? "Checking" : "Tools", systemImage: "terminal")
                            }
                            .disabled(chatStore.isTestingIronclawWorkstation)
                        }

                        if chatStore.ironclawSettings.hasEndpoint || chatStore.ironclawTokenConfigured {
                            Button(role: .destructive) {
                                chatStore.disconnectIronclaw()
                                loadIronclawBridge()
                            } label: {
                                Label("Disconnect IronClaw", systemImage: "trash")
                            }
                        }
                    }
                } else {
                    Section("Power Tools") {
                        PowerToolsUnlockCard(
                            onShowAll: { revealPowerTools() },
                            onCloudKey: { revealPowerTools(focus: .nearCloudKey) },
                            onIronclaw: { revealPowerTools(focus: .ironclawEndpoint) },
                            onAdvanced: { revealPowerTools(focus: .temperature) },
                            onDiagnostics: {
                                revealPowerTools()
                                Task { await chatStore.runDiagnostics() }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                Section {
                    Button(role: .destructive) {
                        sessionStore.signOut()
                        dismiss()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Account")
            .platformInlineNavigationTitle()
            .onAppear {
                systemPrompt = chatStore.systemPrompt
                webSearchEnabled = chatStore.webSearchEnabled
                largeTextAsFileEnabled = chatStore.largeTextAsFileEnabled
                loadAdvancedParams(chatStore.advancedModelParams)
                nearCloudAPIKey = ""
                loadIronclawBridge()
                powerToolsUnlocked = powerToolsUnlocked || isPowerMode
                if chatStore.billingSnapshot == nil {
                    Task { await chatStore.refreshBilling() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingChatImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    Task {
                        isImportingChats = true
                        await chatStore.importChats(from: url)
                        isImportingChats = false
                    }
                case let .failure(error):
                    chatStore.bannerMessage = error.localizedDescription
                }
            }
            .sheet(isPresented: $showingShareGroups) {
                ShareGroupsView()
                    .environmentObject(chatStore)
            }
            .sheet(isPresented: $showingCapabilities) {
                CapabilitiesView(
                    onOpenAccountSettings: nil,
                    onOpenSecurity: nil,
                    onOpenAgentWorkspace: nil,
                    onRunSetupAgain: nil
                )
                .environmentObject(chatStore)
                .environmentObject(sessionStore)
            }
        }
        .platformLargeDetent()
    }

    private func saveChatSettings() async {
        isSavingSettings = true
        defer { isSavingSettings = false }
        await chatStore.saveUserSettings(
            systemPrompt: systemPrompt,
            webSearchEnabled: webSearchEnabled,
            largeTextAsFileEnabled: largeTextAsFileEnabled,
            advancedParams: advancedParams
        )
        loadAdvancedParams(chatStore.advancedModelParams)
    }

    private var advancedParams: AdvancedModelParams {
        AdvancedModelParams(
            temperature: parseDouble(temperature, min: 0, max: 2),
            topP: parseDouble(topP, min: 0, max: 1),
            maxTokens: parseInt(maxTokens, min: 1, max: 200_000),
            reasoningEffort: reasoningEffort
        ).sanitized
    }

    private var setupProfile: UserSetupProfile {
        guard let accountID = sessionStore.setupAccountID else { return .defaults }
        return UserSetupStorage.load(for: accountID) ?? .defaults
    }

    private var isPowerMode: Bool {
        setupProfile.experienceMode == .power
    }

    private var showsPowerTools: Bool {
        powerToolsUnlocked || isPowerMode || chatStore.routeReadinessIssue != nil
    }

    private var capabilitySummary: String {
        [
            "Private ready",
            chatStore.nearCloudKeyConfigured ? "Cloud connected" : "Cloud not connected",
            chatStore.ironclawRemoteWorkstationAvailable ? "Agent connected" : "Agent phone ready"
        ].joined(separator: " · ")
    }

    private func revealPowerTools(focus: PowerToolField? = nil) {
        if let accountID = sessionStore.setupAccountID {
            var profile = setupProfile
            profile.experienceMode = .power
            UserSetupStorage.save(profile, for: accountID)
        }
        powerToolsUnlocked = true
        guard let focus else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedPowerToolField = focus
        }
    }

    private func loadAdvancedParams(_ params: AdvancedModelParams) {
        temperature = params.temperature.map { formatNumber($0) } ?? ""
        topP = params.topP.map { formatNumber($0) } ?? ""
        maxTokens = params.maxTokens.map(String.init) ?? ""
        reasoningEffort = params.reasoningEffort
    }

    private func loadIronclawBridge() {
        ironclawEnabled = chatStore.ironclawSettings.isEnabled
        ironclawEndpoint = chatStore.ironclawSettings.baseURL
        ironclawThreadID = chatStore.ironclawSettings.threadID
        ironclawToken = ""
    }

    private func saveIronclawBridge() {
        chatStore.saveIronclawIntegration(
            isEnabled: ironclawEnabled,
            baseURL: ironclawEndpoint,
            authToken: ironclawToken,
            threadID: ironclawThreadID
        )
        loadIronclawBridge()
    }

    private func parseDouble(_ value: String, min: Double, max: Double) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let number = Double(trimmed) else { return nil }
        return Swift.min(Swift.max(number, min), max)
    }

    private func parseInt(_ value: String, min: Int, max: Int) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let number = Int(trimmed) else { return nil }
        return Swift.min(Swift.max(number, min), max)
    }

    private func formatNumber(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        return formatted
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private func planDetail(_ plan: SubscriptionPlan) -> String {
        var parts: [String] = []
        if let price = plan.price {
            parts.append(price == 0 ? "Free" : String(format: "$%.2f", price))
        }
        if let maxTokens = plan.monthlyTokens?.max {
            parts.append("\(maxTokens.formatted()) tokens")
        }
        if let modelCount = plan.allowedModels?.count, modelCount > 0 {
            parts.append("\(modelCount) models")
        }
        if let trialDays = plan.trialPeriodDays, trialDays > 0 {
            parts.append("\(trialDays)d trial")
        }
        return parts.isEmpty ? "Plan details unavailable" : parts.joined(separator: " · ")
    }
}

private struct CapabilitiesEntryRow: View {
    let statusLine: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 34, height: 34)
                .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Capability Center")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(statusLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct CapabilitiesView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss

    let onOpenAccountSettings: (() -> Void)?
    let onOpenSecurity: (() -> Void)?
    let onOpenAgentWorkspace: (() -> Void)?
    let onRunSetupAgain: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    capabilityHeader
                    CapabilityStatusStrip(items: statusItems)

                    CapabilityCard(
                        iconName: "lock.shield",
                        title: "Private Inference",
                        status: privateStatus,
                        statusColor: privateStatusColor,
                        summary: "Private chat works immediately on iPhone and can attach proof when the selected route supports it.",
                        trustLine: "Trust boundary: attestation proves the serving environment, not that an answer is true.",
                        detail: privateDetail,
                        primaryAction: privatePrimaryAction,
                        secondaryAction: nil
                    )

                    CapabilityCard(
                        iconName: "cloud.fill",
                        title: "NEAR AI Cloud",
                        status: cloudStatus,
                        statusColor: cloudStatusColor,
                        summary: "Connect Cloud when you want more external models inside the same conversation flow.",
                        trustLine: "Trust boundary: Cloud turns are anonymized or proxied, but they are not NEAR Private TEE proof.",
                        detail: cloudDetail,
                        primaryAction: cloudPrimaryAction,
                        secondaryAction: nil
                    )

                    CapabilityCard(
                        iconName: "terminal.fill",
                        title: "IronClaw Agent",
                        status: agentStatus,
                        statusColor: agentStatusColor,
                        summary: "Use phone-safe agent skills now, then hand off repo, shell, and workstation tasks when hosted IronClaw is connected.",
                        trustLine: "Trust boundary: agent runs can read files, use tools, and act with any connected credentials.",
                        detail: agentDetail,
                        primaryAction: agentPrimaryAction,
                        secondaryAction: agentSecondaryAction
                    )

                    CapabilityCard(
                        iconName: "square.grid.2x2.fill",
                        title: "Council",
                        status: councilStatus,
                        statusColor: councilStatusColor,
                        summary: "Compare private and Cloud models in one chat, then synthesize the strongest answer.",
                        trustLine: "Trust boundary: mixed councils can include both proof-backed private legs and external Cloud legs.",
                        detail: councilDetail,
                        primaryAction: councilPrimaryAction,
                        secondaryAction: nil
                    )

                    if let footerAction = footerAction {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Next step")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            CapabilityActionButton(action: footerAction)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
                .frame(maxWidth: 640, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .background(HomeSurfaceBackground().ignoresSafeArea())
            .navigationTitle("Capabilities")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .platformLargeDetent()
    }

    private var capabilityHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Private chat is ready now. Connect Cloud and IronClaw only when you need broader model coverage or agent runs.")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(headerStatusLine)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let email = sessionStore.profile?.user.email {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusItems: [CapabilityStatusItemModel] {
        [
            CapabilityStatusItemModel(title: "Private", value: privateStatus, tint: privateStatusColor),
            CapabilityStatusItemModel(title: "Cloud", value: cloudStatus, tint: cloudStatusColor),
            CapabilityStatusItemModel(title: "Agent", value: agentStatus, tint: agentStatusColor),
            CapabilityStatusItemModel(title: "Council", value: councilStatus, tint: councilStatusColor)
        ]
    }

    private var headerStatusLine: String {
        [
            "Private ready",
            chatStore.nearCloudKeyConfigured ? "Cloud connected" : "Cloud not connected",
            chatStore.ironclawRemoteWorkstationAvailable ? "Agent connected" : "Agent phone ready"
        ].joined(separator: " · ")
    }

    private var privateStatus: String {
        guard let snapshot = chatStore.attestationSnapshot else { return "Ready" }
        switch AttestationFreshness.classify(attestedAt: snapshot.fetchedAt) {
        case .underTwoMinutes:
            return "Proof fresh"
        case .underOneHour:
            return "Proof checked"
        case .stale:
            return "Proof stale"
        }
    }

    private var privateStatusColor: Color {
        guard let snapshot = chatStore.attestationSnapshot else { return Color.brandBlue }
        switch AttestationFreshness.classify(attestedAt: snapshot.fetchedAt) {
        case .underTwoMinutes, .underOneHour:
            return Color.proofVerified
        case .stale:
            return Color.proofStale
        }
    }

    private var privateDetail: String {
        guard let snapshot = chatStore.attestationSnapshot else {
            return "Current route: \(chatStore.selectedProviderDisplayName). Fetch proof from Security when you need a signed private-route report."
        }

        let coveredCount = max(snapshot.modelAttestationCount, snapshot.coveredModelIDs.count)
        let freshness = AttestationFreshness.classify(attestedAt: snapshot.fetchedAt).shortLabel
        let countLabel = "\(coveredCount) model\(coveredCount == 1 ? "" : "s")"
        return "Last report: \(countLabel) covered · \(freshness) · current route \(chatStore.selectedProviderDisplayName)."
    }

    private var cloudStatus: String {
        chatStore.nearCloudKeyConfigured ? "Connected" : "Not connected"
    }

    private var cloudStatusColor: Color {
        chatStore.nearCloudKeyConfigured ? Color.brandBlue : Color.proofStale
    }

    private var cloudDetail: String {
        if chatStore.nearCloudKeyConfigured {
            let plan = chatStore.billingSnapshot?.activeSubscription?.plan ?? "API key saved"
            return chatStore.selectedRouteUsesNearCloud
                ? "Current route uses \(chatStore.selectedModelDisplayName) through NEAR Cloud. \(plan)."
                : "Cloud unlocks premium external model rows in the picker. \(plan)."
        }
        return "Add a NEAR Cloud key before sending with locked Cloud routes or mixed Cloud councils."
    }

    private var agentStatus: String {
        if chatStore.ironclawRemoteWorkstationAvailable {
            return "Workstation connected"
        }
        if chatStore.agentModels.contains(where: { $0.id == ModelOption.ironclawMobileModelID }) {
            return "Phone ready"
        }
        return "Not ready"
    }

    private var agentStatusColor: Color {
        if chatStore.ironclawRemoteWorkstationAvailable {
            return Color.proofVerified
        }
        return chatStore.agentModels.contains(where: { $0.id == ModelOption.ironclawMobileModelID }) ? Color.brandBlue : Color.proofStale
    }

    private var agentDetail: String {
        if let verifiedAt = chatStore.ironclawLastVerifiedAt, chatStore.ironclawRemoteWorkstationAvailable {
            return "Hosted tools last verified \(verifiedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))."
        }
        return chatStore.ironclawStatusText
    }

    private var councilStatus: String {
        let activeCount = chatStore.councilModelIDs.count
        if activeCount >= 2 {
            return "Current lineup ready"
        }
        if chatStore.defaultCouncilModels.count >= 2 {
            return "Auto lineup ready"
        }
        return "Needs one more model"
    }

    private var councilStatusColor: Color {
        (chatStore.councilModelIDs.count >= 2 || chatStore.defaultCouncilModels.count >= 2) ? Color.brandBlue : Color.proofStale
    }

    private var councilDetail: String {
        let models = chatStore.councilModelNames.isEmpty ? chatStore.defaultCouncilModels.map(\.displayName) : chatStore.councilModelNames
        let lineup = models.prefix(3).joined(separator: " · ")
        let suffix = models.count > 3 ? " +\(models.count - 3) more" : ""

        if models.isEmpty {
            return "Council turns on once at least two compatible chat models are available."
        }

        if !chatStore.nearCloudKeyConfigured,
           chatStore.defaultCouncilModels.contains(where: \.isNearCloudModel) {
            return "Auto lineup is available, but Cloud legs stay locked until a key is added. \(lineup)\(suffix)."
        }

        return "Lineup: \(lineup)\(suffix)."
    }

    private var privatePrimaryAction: CapabilityCardAction? {
        guard let onOpenSecurity else { return nil }
        return CapabilityCardAction(title: "Open Security", systemImage: "checkmark.shield", role: .primary) {
            dismissThen(onOpenSecurity)
        }
    }

    private var cloudPrimaryAction: CapabilityCardAction? {
        guard let onOpenAccountSettings else { return nil }
        return CapabilityCardAction(
            title: chatStore.nearCloudKeyConfigured ? "Manage Cloud" : "Add Cloud Key",
            systemImage: chatStore.nearCloudKeyConfigured ? "slider.horizontal.3" : "key",
            role: .primary
        ) {
            dismissThen(onOpenAccountSettings)
        }
    }

    private var agentPrimaryAction: CapabilityCardAction? {
        if chatStore.ironclawRemoteWorkstationAvailable, let onOpenAgentWorkspace {
            return CapabilityCardAction(title: "Open Agent", systemImage: "terminal", role: .primary) {
                dismissThen(onOpenAgentWorkspace)
            }
        }
        guard let onOpenAccountSettings else { return nil }
        return CapabilityCardAction(title: "Connect Agent", systemImage: "point.3.connected.trianglepath.dotted", role: .primary) {
            dismissThen(onOpenAccountSettings)
        }
    }

    private var agentSecondaryAction: CapabilityCardAction? {
        guard chatStore.ironclawRemoteWorkstationAvailable, let onOpenAccountSettings else { return nil }
        return CapabilityCardAction(title: "Manage Endpoint", systemImage: "slider.horizontal.3", role: .secondary) {
            dismissThen(onOpenAccountSettings)
        }
    }

    private var councilPrimaryAction: CapabilityCardAction? {
        guard chatStore.councilModelIDs.count < 2, chatStore.defaultCouncilModels.count >= 2 else { return nil }
        return CapabilityCardAction(title: "Use Auto-Council", systemImage: "square.grid.2x2", role: .primary) {
            chatStore.useDefaultCouncilLineup()
        }
    }

    private var footerAction: CapabilityCardAction? {
        guard let onRunSetupAgain else { return nil }
        return CapabilityCardAction(title: "Run Setup Again", systemImage: "slider.horizontal.3", role: .secondary) {
            dismissThen(onRunSetupAgain)
        }
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            action()
        }
    }
}

private struct CapabilityStatusItemModel: Identifiable {
    let title: String
    let value: String
    let tint: Color

    var id: String { title }
}

private struct CapabilityStatusStrip: View {
    let items: [CapabilityStatusItemModel]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.tint)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.appPanelBackground, in: Capsule())
                }
            }
        }
    }
}

private struct CapabilityCardAction {
    enum Role {
        case primary
        case secondary
    }

    let title: String
    let systemImage: String
    let role: Role
    let action: () -> Void
}

private struct CapabilityCard: View {
    let iconName: String
    let title: String
    let status: String
    let statusColor: Color
    let summary: String
    let trustLine: String
    let detail: String
    let primaryAction: CapabilityCardAction?
    let secondaryAction: CapabilityCardAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 38, height: 38)
                    .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                }

                Spacer(minLength: 0)
            }

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(trustLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if primaryAction != nil || secondaryAction != nil {
                HStack(spacing: 8) {
                    if let primaryAction {
                        CapabilityActionButton(action: primaryAction)
                    }
                    if let secondaryAction {
                        CapabilityActionButton(action: secondaryAction)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        }
    }
}

private struct CapabilityActionButton: View {
    let action: CapabilityCardAction

    var body: some View {
        Button(action: action.action) {
            Label(action.title, systemImage: action.systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(action.role == .primary ? Color.white : Color.primaryAction)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(backgroundShape)
                .overlay {
                    if action.role == .secondary {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if action.role == .primary {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primaryAction)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.appSecondaryBackground)
        }
    }
}

private struct IronclawBridgeReadinessCard: View {
    let endpointConnected: Bool
    let tokenConfigured: Bool
    let lastVerifiedAt: Date?
    let isChecking: Bool
    let toolNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Agent Readiness")
                        .font(.subheadline.weight(.semibold))
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                readinessPill(title: "Endpoint", value: endpointConnected ? "Hosted" : "Missing", symbolName: "server.rack", active: endpointConnected)
                readinessPill(title: "Token", value: tokenConfigured ? "Saved" : "Optional", symbolName: "key", active: tokenConfigured)
                readinessPill(title: "Tools", value: toolValue, symbolName: "chevron.left.forwardslash.chevron.right", active: toolsAvailable)
                readinessPill(title: "Repo Auth", value: "Gated", symbolName: "lock.shield", active: true)
            }

            if !toolNames.isEmpty {
                Text(toolSummary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var toolValue: String {
        if isChecking {
            return "Checking"
        }
        if !toolNames.isEmpty {
            return "\(toolNames.count) tools"
        }
        if let lastVerifiedAt {
            return lastVerifiedAt.formatted(date: .omitted, time: .shortened)
        }
        return "Verify"
    }

    private var statusLine: String {
        if isChecking {
            return "Checking shell and git"
        }
        if lastVerifiedAt != nil {
            return toolNames.isEmpty ? "Shell and git verified" : "Shell, git, files, and agent tools verified"
        }
        if !toolNames.isEmpty {
            return "Tool catalog available; run Tools for shell/git preflight"
        }
        if endpointConnected {
            return "Endpoint ready; verify tools"
        }
        return "Add a hosted HTTPS endpoint"
    }

    private var toolsAvailable: Bool {
        lastVerifiedAt != nil || !toolNames.isEmpty
    }

    private var toolSummary: String {
        let priority = ["shell", "github", "grep", "read_file", "write_file", "apply_patch", "nearai_web_search"]
        let available = priority.filter { toolNames.contains($0) }
        let names = available.isEmpty ? Array(toolNames.prefix(6)) : available
        return names.joined(separator: " · ")
    }

    private func readinessPill(title: String, value: String, symbolName: String, active: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(active ? Color.brandBlue : .secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(active ? Color.brandBlue.opacity(0.07) : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PowerToolsUnlockCard: View {
    let onShowAll: () -> Void
    let onCloudKey: () -> Void
    let onIronclaw: () -> Void
    let onAdvanced: () -> Void
    let onDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 38, height: 38)
                    .background(Color.actionPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Power Tools")
                        .font(.headline)
                    Text("Keep the app simple by default, but add Cloud keys, hosted IronClaw, diagnostics, or advanced model controls whenever you need them.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: onShowAll) {
                Label("Show Power Tools", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.actionPrimary)

            VStack(spacing: 8) {
                PowerToolQuickAction(title: "Add NEAR Cloud key", symbolName: "key", action: onCloudKey)
                PowerToolQuickAction(title: "Connect IronClaw bridge", symbolName: "terminal", action: onIronclaw)
                PowerToolQuickAction(title: "Advanced model params", symbolName: "brain.head.profile", action: onAdvanced)
                PowerToolQuickAction(title: "Run diagnostics", symbolName: "stethoscope", action: onDiagnostics)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PowerToolQuickAction: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textSecondary.opacity(0.75))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct AdvancedParamField: View {
    let title: String
    let detail: String
    let placeholder: String
    @Binding var text: String
    let keyboard: UIKeyboardType

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .frame(maxWidth: 120)
        }
    }
}

private struct SecurityView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var localVerificationMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    attestationSummary
                }

                Section("Current Session") {
                    SecurityStateRow(title: "Route", value: routeSummary, symbolName: routeSymbolName)
                    SecurityStateRow(title: "Endpoint", value: endpointSummary, symbolName: "network")
                    SecurityStateRow(title: "Request signing", value: signingSummary, symbolName: "signature")
                    SecurityStateRow(title: "Selected model", value: chatStore.selectedModelDisplayName, symbolName: "cpu")
                }

                Section("Proof Actions") {
                    proofActionsContent
                }

                Section("Proof Facts") {
                    proofFactsContent
                }

                Section("What This Means") {
                    ForEach(AttestationEducation.standard.sections) { section in
                        AttestationEducationRow(section: section)
                    }
                }

                Section("Report") {
                    if let error = chatStore.attestationFetchErrorMessage {
                        InfoRow(title: "Last fetch", value: error)
                    }
                    if let snapshot = chatStore.attestationSnapshot {
                        InfoRow(
                            title: "Fetched",
                            value: snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard)
                        )
                        InfoRow(title: "Nonce", value: snapshot.nonce, monospaced: true)
                        InfoRow(title: "Model", value: proofModelPhrase(snapshot), monospaced: snapshot.model != nil)
                        InfoRow(title: "Coverage", value: attestationCoveragePhrase(snapshot))
                        if let address = snapshot.chatGatewayAddress {
                            InfoRow(title: "Chat gateway", value: address, monospaced: true)
                        }
                        if let address = snapshot.cloudGatewayAddress {
                            InfoRow(title: "Cloud gateway", value: address, monospaced: true)
                        }

                        DisclosureGroup {
                            ScrollView(.horizontal, showsIndicators: true) {
                                Text(snapshot.prettyJSON)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 220)
                        } label: {
                            Label("Raw JSON", systemImage: "curlybraces")
                        }
                        .padding(.vertical, 4)

                        Button {
                            Clipboard.copy(snapshot.prettyJSON)
                            chatStore.bannerMessage = "Attestation copied."
                        } label: {
                            Label("Copy Report", systemImage: "doc.on.doc")
                        }
                    } else if chatStore.isLoadingAttestation {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Fetching attestation")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No report fetched yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if canFetchAttestation {
                        Button {
                            Task { await chatStore.refreshAttestationReport() }
                        } label: {
                            Label(
                                chatStore.attestationSnapshot == nil ? "Fetch Attestation" : "Refresh Attestation",
                                systemImage: "arrow.clockwise"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.brandBlue)
                        .disabled(chatStore.isLoadingAttestation)
                    } else {
                        Label(fetchAttestationDisabledText, systemImage: "shield.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Security")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                if canFetchAttestation, chatStore.attestationSnapshot == nil, !chatStore.isLoadingAttestation {
                    await chatStore.refreshAttestationReport()
                }
            }
        }
    }

    @ViewBuilder
    private var proofActionsContent: some View {
        if let snapshot = chatStore.attestationSnapshot {
            Button {
                verifyProofOnDevice(snapshot)
            } label: {
                Label("Verify on-device", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityHint("Checks the cached attestation proof on this device. It does not verify answer truth.")

            ShareLink(
                item: snapshot.prettyJSON,
                subject: Text("NEAR Private Chat attestation JSON"),
                message: Text("Attestation JSON only. It does not include conversation text.")
            ) {
                Label("Share Proof JSON", systemImage: "square.and.arrow.up")
            }
            .accessibilityHint("Shares only the attestation JSON report.")

            if let localVerificationMessage {
                Text(localVerificationMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Label(proofActionsUnavailableText, systemImage: "shield.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {} label: {
                Label("Verify on-device", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(true)
            .accessibilityHint("Fetch attestation first to verify proof on this device.")

            Button {} label: {
                Label("Share Proof JSON", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(true)
            .accessibilityHint("Fetch attestation first to share proof JSON.")
        }
    }

    @ViewBuilder
    private var proofFactsContent: some View {
        if let snapshot = chatStore.attestationSnapshot {
            ProofFactRow(
                title: "Model",
                value: proofModelPhrase(snapshot),
                detail: proofModelDetail(snapshot),
                symbolName: "cpu"
            )
            ProofFactRow(
                title: "Runtime",
                value: proofRuntimePhrase(snapshot),
                detail: endpointSummary,
                symbolName: "server.rack"
            )
            ProofFactRow(
                title: "TEE",
                value: proofTEEPhrase(snapshot),
                detail: "Proof covers route/model evidence when present. It does not prove answer truthfulness.",
                symbolName: "lock.shield"
            )
            ProofFactRow(
                title: "Freshness",
                value: chatStore.currentAttestationStatus.freshness()?.shortLabel ?? "unknown",
                detail: snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard),
                symbolName: "clock"
            )
        } else {
            ProofFactRow(
                title: "Proof data",
                value: "No attestation JSON on device",
                detail: proofActionsUnavailableText,
                symbolName: "shield.slash"
            )
        }
    }

    private func verifyProofOnDevice(_ snapshot: AttestationSnapshot) {
        let status = chatStore.currentAttestationStatus
        let copy = status.userFacingCopy()
        let nonceText = snapshot.nonce.isEmpty ? "Nonce is missing." : "Nonce is present."
        let message = "On-device check: \(copy.title). \(nonceText) This checks proof metadata, not answer truth."
        localVerificationMessage = message
        chatStore.bannerMessage = message
    }

    private var attestationSummary: some View {
        if chatStore.selectedRouteUsesNearCloud || (chatStore.isCouncilModeEnabled && chatStore.activeCouncilHasNearCloudRoutes) {
            return AnyView(cloudTrustSummary)
        }

        let proof = ProofCapsuleViewModel(
            status: chatStore.currentAttestationStatus,
            isLoading: chatStore.isLoadingAttestation,
            modelID: chatStore.selectedModel
        )
        return AnyView(VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: proof.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(proof.tintColor)
                    .frame(width: 44, height: 44)
                    .background(proof.tintColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(proof.title)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                    Text(proof.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ProofCapsule(viewModel: proof)
                Text(AttestationEducation.standard.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chatStore.currentAttestationStatus.accessibilityLabel())
        .accessibilityHint(chatStore.currentAttestationStatus.accessibilityHint()))
    }

    private var cloudTrustSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "eye.slash")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 44, height: 44)
                    .background(Color.brandBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Anonymized cloud route")
                        .font(.headline)
                    Text("NEAR Cloud forwards the request without provider-facing app identity. It is not NEAR Private TEE-attested.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            StatusChip(title: "Anonymized · not attested", symbolName: "cloud", isPrimary: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("NEAR Cloud route anonymized, not TEE-attested")
    }

    private var canFetchAttestation: Bool {
        if chatStore.isCouncilModeEnabled {
            return !chatStore.activeCouncilHasExternalRoutes && chatStore.selectedRouteKind == .nearPrivate
        }
        return chatStore.selectedRouteKind == .nearPrivate
    }

    private var proofActionsUnavailableText: String {
        if chatStore.isLoadingAttestation {
            return "Fetching attestation JSON. Proof actions will unlock when a report is on this device."
        }
        if canFetchAttestation {
            return "Fetch attestation to enable on-device verification and proof JSON sharing."
        }
        return fetchAttestationDisabledText
    }

    private var fetchAttestationDisabledText: String {
        if chatStore.isCouncilModeEnabled, chatStore.activeCouncilHasExternalRoutes {
            return "TEE proof is available for all-private Council lineups. Remove NEAR Cloud models to fetch proof."
        }
        return "Switch to a NEAR Private model to fetch TEE proof."
    }

    private func attestationCoveragePhrase(_ snapshot: AttestationSnapshot) -> String {
        if !snapshot.coveredModelIDs.isEmpty {
            if snapshot.coveredModelIDs.count == 1, let model = snapshot.coveredModelIDs.first {
                return "\(model) covered by proof"
            }
            return "\(snapshot.coveredModelIDs.count) models covered by proof"
        }
        if let model = snapshot.model, snapshot.modelAttestationCount <= 1 {
            return "\(model) covered by proof"
        }
        if snapshot.modelAttestationCount > 0 {
            return "\(snapshot.modelAttestationCount) model proof entries"
        }
        return "No model coverage in this report"
    }

    private func proofModelPhrase(_ snapshot: AttestationSnapshot) -> String {
        if !snapshot.coveredModelIDs.isEmpty {
            if snapshot.coveredModelIDs.count == 1, let model = snapshot.coveredModelIDs.first {
                return model
            }
            if snapshot.coveredModelIDs.contains(where: { AttestationEvidence.normalizedModelID($0) == AttestationEvidence.normalizedModelID(chatStore.selectedModel) }) {
                return "\(chatStore.selectedModel) + \(snapshot.coveredModelIDs.count - 1) more"
            }
            return "\(snapshot.coveredModelIDs.count) covered models"
        }
        if let model = snapshot.model {
            return model
        }
        if snapshot.modelAttestationCount > 0 {
            return "\(snapshot.modelAttestationCount) model attestations, IDs unavailable"
        }
        return "Coverage metadata not in report"
    }

    private func proofModelDetail(_ snapshot: AttestationSnapshot) -> String? {
        if !snapshot.coveredModelIDs.isEmpty || snapshot.model != nil {
            return chatStore.currentAttestationStatus.coverage(for: chatStore.selectedModel) == .covered ? "Covered by the current proof." : "Current selected model may need a refreshed proof."
        }
        return "The private model can still run; this report just cannot prove model coverage."
    }

    private func proofRuntimePhrase(_ snapshot: AttestationSnapshot) -> String {
        if snapshot.chatGatewayAddress != nil {
            return "NEAR Private chat gateway"
        }
        if snapshot.cloudGatewayAddress != nil {
            return "NEAR Cloud gateway"
        }
        return routeSummary
    }

    private func proofTEEPhrase(_ snapshot: AttestationSnapshot) -> String {
        if snapshot.modelAttestationCount > 0 {
            return "Model TEE evidence present"
        }
        if snapshot.chatGatewayAddress != nil || snapshot.cloudGatewayAddress != nil {
            return "Gateway evidence present"
        }
        return "TEE facts not present"
    }

    private var routeSummary: String {
        if chatStore.isCouncilModeEnabled {
            return "LLM Council"
        }
        switch chatStore.selectedRouteKind {
        case .nearPrivate:
            return "NEAR Private"
        case .nearCloud:
            return "NEAR Cloud"
        case .ironclawMobile:
            return "IronClaw Mobile"
        case .ironclawHosted:
            return "IronClaw Hosted"
        }
    }

    private var routeSymbolName: String {
        switch chatStore.selectedRouteKind {
        case .nearPrivate:
            return "lock.shield"
        case .nearCloud:
            return "cloud"
        case .ironclawMobile:
            return "iphone"
        case .ironclawHosted:
            return "terminal"
        }
    }

    private var endpointSummary: String {
        switch chatStore.selectedRouteKind {
        case .nearPrivate:
            return "private.near.ai"
        case .nearCloud:
            return "cloud-api.near.ai"
        case .ironclawMobile:
            return chatStore.ironclawRemoteWorkstationAvailable ? "Phone + workstation" : "Phone runtime"
        case .ironclawHosted:
            return chatStore.ironclawSettings.hasUsableHostedEndpoint ? "Configured gateway" : "Not configured"
        }
    }

    private var signingSummary: String {
        chatStore.attestationSnapshot?.signingAlgorithm.uppercased() ?? "ECDSA"
    }
}

private struct AttestationEducationRow: View {
    let section: AttestationEducationSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))
            Text(section.body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}

private struct InfoRow: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

private struct ProofFactRow: View {
    let title: String
    let value: String
    let detail: String?
    let symbolName: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityHint(detail ?? "")
    }
}

private struct DiagnosticCheckRow: View {
    let check: AppDiagnosticCheck

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.state.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(stateColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(check.title)
                    .font(.subheadline.weight(.semibold))
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 3)
    }

    private var stateColor: Color {
        switch check.state {
        case .running: Color.textSecondary
        case .passed: Color.proofVerified
        case .warning: Color.proofStale
        case .failed: Color.proofMismatch
        }
    }
}

private struct SecurityStateRow: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "circle.fill")
                .font(.caption2)
                .foregroundStyle(Color.textSecondary.opacity(0.38))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

private struct EmptyChatView: View {
    @EnvironmentObject private var chatStore: ChatStore

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
        if chatStore.selectedProviderDisplayName == "IronClaw" {
            return chatStore.ironclawRemoteWorkstationAvailable ? "Hosted agent ready." : "Mobile agent ready."
        }
        if chatStore.isCouncilModeEnabled {
            return "Council is ready to compare answers."
        }
        if chatStore.researchModeEnabled && !chatStore.selectedRouteUsesNearCloud {
            return "Search current sources."
        }
        return "Private by default. Add web, files, or sources when useful."
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
                EmptyPromptSuggestion(title: "5 bullets", symbolName: "list.bullet", prompt: "Summarize \(projectName)'s launch brief in 5 bullets."),
                EmptyPromptSuggestion(title: "Find risks", symbolName: "exclamationmark.triangle", prompt: "Review \(projectName)'s files, links, and notes. What launch risks should I address?"),
                EmptyPromptSuggestion(title: "Draft memo", symbolName: "doc.text", prompt: "Draft a launch-risk memo from \(projectName)'s project files.")
            ]
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

        return [
            EmptyPromptSuggestion(title: "5 bullets", symbolName: "list.bullet", prompt: "Summarize the launch brief in 5 bullets."),
            EmptyPromptSuggestion(title: "Compare", symbolName: "square.grid.2x2", prompt: "Compare Anthropic and OpenAI for this task: "),
            EmptyPromptSuggestion(title: "Risk memo", symbolName: "doc.text", prompt: "Draft a launch-risk memo from project files.")
        ]
    }
}

private struct AgentWorkspaceView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if chatStore.ironclawRemoteWorkstationAvailable {
                        AgentMissionControlPanel()
                            .environmentObject(chatStore)
                    } else {
                        AgentWorkspaceHeader()
                            .environmentObject(chatStore)
                        AgentWorkspaceSetupPanel()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
                .frame(maxWidth: 640, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.appBackground)
            .navigationTitle(chatStore.ironclawRemoteWorkstationAvailable ? "Agent" : "Connect Agent")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .platformLargeDetent()
    }
}

private struct AgentWorkspaceHeader: View {
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 42, height: 42)
                    .background(Color.brandBlue.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect Agent")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Connect a hosted IronClaw workstation, then launch repo, research, and code tasks from your phone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ChipFlowLayout(spacing: 7, lineSpacing: 7) {
                StatusChip(title: chatStore.ironclawRemoteWorkstationAvailable ? "Workstation on" : "Workstation off", symbolName: "server.rack", isPrimary: chatStore.ironclawRemoteWorkstationAvailable)
                StatusChip(title: chatStore.ironclawToolNames.isEmpty ? "Shell + git" : "\(chatStore.ironclawToolNames.count) tools", symbolName: "terminal", isPrimary: chatStore.ironclawRemoteWorkstationAvailable)
                StatusChip(title: chatStore.ironclawTokenConfigured ? "Token saved" : "Token needed", symbolName: "key", isPrimary: false)
                StatusChip(title: "Phone controlled", symbolName: "iphone", isPrimary: false)
            }
        }
    }
}

private struct AgentWorkspaceSetupPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connect IronClaw", systemImage: "server.rack")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Add a hosted HTTPS endpoint and token in Account settings. Local LAN gateways are not shown as phone-ready routes.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: 460, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}

private struct AgentWorkspacePrinciples: View {
    private struct Principle: Identifiable {
        var id: String { title }
        let title: String
        let symbolName: String
        let detail: String
    }

    private let rows: [Principle] = [
        Principle(title: "Ask", symbolName: "text.badge.plus", detail: "If a repo, issue, or task brief is missing, the agent asks before mutating anything."),
        Principle(title: "Inspect", symbolName: "magnifyingglass", detail: "The workstation checks files, git status, stack, and safe test commands first."),
        Principle(title: "Report", symbolName: "doc.text", detail: "Every run should return commands, changed files, tests, and remaining risk.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Run Contract")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.symbolName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.brandBlue)
                        .frame(width: 24, height: 24)
                        .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(row.detail)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct AgentMissionControlPanel: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var missionBrief = ""
    @State private var showingProjectFiles = false

    private struct ToolbeltCapability: Identifiable {
        var id: String { title }
        let title: String
        let symbolName: String
        let isAvailable: Bool
    }

    private struct PromptSuggestion: Identifiable {
        var id: String { title }
        let title: String
        let symbolName: String
        let prompt: String
    }

    private let promptSuggestions: [PromptSuggestion] = [
        PromptSuggestion(
            title: "Repo task",
            symbolName: "wrench.and.screwdriver",
            prompt: "Update this repo to "
        ),
        PromptSuggestion(
            title: "PR / issue",
            symbolName: "arrow.triangle.branch",
            prompt: "Review this PR or issue and identify the highest-impact fixes: "
        ),
        PromptSuggestion(
            title: "Research",
            symbolName: "globe",
            prompt: "Research the latest context on this and turn it into concrete next actions: "
        ),
        PromptSuggestion(
            title: "Plan",
            symbolName: "checklist",
            prompt: "Plan the safest way to build this, including tests and risks: "
        )
    ]

    private var availableCapabilities: [ToolbeltCapability] {
        toolbeltCapabilities.filter(\.isAvailable)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                launcherHeader
                quickStartRow
                agentComposer
                if !trimmedMissionBrief.isEmpty {
                    agentSkillPreview
                }
                agentContextPanel
            }
            .padding(14)
            .background {
                CommandCardBackground()
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.11), lineWidth: 1)
            }
            .shadow(color: Color.brandBlue.opacity(0.14), radius: 18, y: 8)

        }
        .frame(maxWidth: 520, alignment: .leading)
        .sheet(isPresented: $showingProjectFiles) {
            ProjectFilesView()
                .environmentObject(chatStore)
        }
    }

    private var launcherHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: "terminal")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.brandBlack)
                    .frame(width: 42, height: 42)
                    .background(Color.brandSky, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Agent")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(agentReadinessTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 0)

                Button {
                    Task { await chatStore.testIronclawWorkstation() }
                } label: {
                    Image(systemName: chatStore.isTestingIronclawWorkstation ? "arrow.triangle.2.circlepath" : "checkmark.seal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.brandSky)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(chatStore.isTestingIronclawWorkstation)
                .accessibilityLabel("Verify IronClaw workstation")
            }
        }
    }

    private var agentContextPanel: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: chatStore.selectedProject == nil ? "folder.badge.plus" : "folder")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandSky)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(chatStore.selectedProject?.name ?? "No project selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(agentContextLine)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if chatStore.selectedProject != nil {
                Button {
                    showingProjectFiles = true
                } label: {
                    Label("Context", systemImage: "folder.badge.gearshape")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Color.brandSky)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open project context")
            }
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var agentComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("What should the agent do?", text: $missionBrief, axis: .vertical)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .lineLimit(4...8)
                .font(.body)
                .frame(minHeight: 112, alignment: .topLeading)
                .accessibilityLabel("Agent mission brief")

            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                    Text("Auto tools")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.brandSky)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.brandSky.opacity(0.16), in: Capsule())

                Spacer(minLength: 0)

                Button {
                    launch()
                } label: {
                    Label("Run", systemImage: "arrow.up")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Color.brandBlack)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Color.brandSky, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(trimmedMissionBrief.isEmpty)
                .accessibilityLabel("Launch IronClaw agent")
            }
        }
        .padding(14)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
    }

    private var agentSkillPreview: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandSky)
                Text("Likely tools")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            ChipFlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(detectedSkills) { skill in
                    Label(skill.title, systemImage: skill.symbolName)
                        .font(.caption2.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var quickStartRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Examples")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.54))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(promptSuggestions) { suggestion in
                        Button {
                            missionBrief = suggestion.prompt
                        } label: {
                            Label(suggestion.title, systemImage: suggestion.symbolName)
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .frame(height: 34)
                                .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var agentContextLine: String {
        guard let project = chatStore.selectedProject else {
            return "Add a repo, issue, PR, source, or file in the brief."
        }

        var parts: [String] = []
        if !project.links.isEmpty {
            parts.append(project.links.count == 1 ? "1 source" : "\(project.links.count) sources")
        }
        if !project.attachments.isEmpty {
            parts.append(project.attachments.count == 1 ? "1 file" : "\(project.attachments.count) files")
        }
        if !project.notes.isEmpty {
            parts.append(project.notes.count == 1 ? "1 saved note" : "\(project.notes.count) saved notes")
        }
        if let primarySource = project.links.first {
            parts.append(primarySource.host ?? primarySource.displayTitle)
        }
        return parts.isEmpty ? "\(project.name) has no saved context yet." : "\(project.name) · \(parts.joined(separator: " · "))"
    }

    private var agentReadinessTitle: String {
        if chatStore.isTestingIronclawWorkstation {
            return "Checking hosted workstation"
        }
        if availableCapabilities.isEmpty {
            return "Describe the outcome; the app will pick the route"
        }

        let priority = ["Shell", "Git", "Web", "Patch", "GitHub"]
        let names = priority.filter { name in
            availableCapabilities.contains(where: { $0.title == name })
        }
        return "Ready: \(names.prefix(3).joined(separator: " + "))"
    }

    private var detectedSkills: [IronclawSkillProfile] {
        IronclawSkillCatalog.suggestedSkills(for: missionBrief, limit: 4)
    }

    private var trimmedMissionBrief: String {
        missionBrief.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var toolbeltCapabilities: [ToolbeltCapability] {
        let tools = Set(chatStore.ironclawToolNames.map { $0.lowercased() })
        let workstationFallback = chatStore.ironclawRemoteWorkstationAvailable && tools.isEmpty
        func has(_ names: String...) -> Bool {
            workstationFallback || names.contains { tools.contains($0) }
        }
        return [
            ToolbeltCapability(title: "Shell", symbolName: "terminal", isAvailable: has("shell")),
            ToolbeltCapability(title: "Git", symbolName: "arrow.triangle.branch", isAvailable: has("git", "shell")),
            ToolbeltCapability(title: "Patch", symbolName: "wrench.and.screwdriver", isAvailable: has("apply_patch")),
            ToolbeltCapability(title: "Web", symbolName: "globe", isAvailable: has("nearai_web_search")),
            ToolbeltCapability(title: "GitHub", symbolName: "chevron.left.forwardslash.chevron.right", isAvailable: has("github"))
        ]
    }

    private func launch() {
        if chatStore.ironclawRemoteWorkstationAvailable {
            chatStore.selectModel(ModelOption.ironclawModelID)
        } else if chatStore.selectedModelOption?.isIronclawModel != true {
            chatStore.selectModel(ModelOption.ironclawMobileModelID)
        }
        chatStore.sourceMode = .auto
        chatStore.researchModeEnabled = false
        chatStore.draft = "Agent mission: \(trimmedMissionBrief)"
        chatStore.sendDraft()
        dismiss()
    }
}

private struct IronclawAgentReadinessPanel: View {
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: statusSymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statusColor)
                .frame(width: 28, height: 28)
                .background(statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Stack")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button {
                Task { await chatStore.testIronclawWorkstation() }
            } label: {
                Image(systemName: chatStore.isTestingIronclawWorkstation ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 30, height: 30)
                    .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(chatStore.isTestingIronclawWorkstation || !chatStore.ironclawRemoteWorkstationAvailable)
            .accessibilityLabel("Verify IronClaw tools")
        }
        .padding(12)
        .frame(maxWidth: 460, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var statusSymbol: String {
        if chatStore.isTestingIronclawWorkstation {
            return "arrow.triangle.2.circlepath"
        }
        if chatStore.ironclawLastVerifiedAt != nil {
            return "checkmark.seal.fill"
        }
        if !chatStore.ironclawToolNames.isEmpty {
            return "terminal.fill"
        }
        if chatStore.ironclawRemoteWorkstationAvailable {
            return "terminal"
        }
        return "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        if chatStore.ironclawLastVerifiedAt != nil {
            return .green
        }
        if !chatStore.ironclawToolNames.isEmpty {
            return Color.brandBlue
        }
        if chatStore.ironclawRemoteWorkstationAvailable || chatStore.isTestingIronclawWorkstation {
            return Color.brandBlue
        }
        return .orange
    }

    private var statusText: String {
        if chatStore.isTestingIronclawWorkstation {
            return "Checking hosted shell and git"
        }
        if let verifiedAt = chatStore.ironclawLastVerifiedAt {
            if chatStore.ironclawToolNames.isEmpty {
                return "Shell and git verified at \(verifiedAt.formatted(date: .omitted, time: .shortened))"
            }
            return "\(chatStore.ironclawToolNames.count) tools: \(toolbeltSummary)"
        }
        if !chatStore.ironclawToolNames.isEmpty {
            return "\(chatStore.ironclawToolNames.count) tools available: \(toolbeltSummary)"
        }
        if chatStore.ironclawRemoteWorkstationAvailable {
            return "Hosted endpoint connected; tools need verification"
        }
        return "Hosted endpoint not connected"
    }

    private var toolbeltSummary: String {
        let available = Set(chatStore.ironclawToolNames.map { $0.lowercased() })
        let labels: [(String, String)] = [
            ("shell", "shell"),
            ("github", "github"),
            ("grep", "grep"),
            ("read_file", "files"),
            ("apply_patch", "patch"),
            ("nearai_web_search", "web")
        ]
        let present = labels.compactMap { name, label in
            available.contains(name) ? label : nil
        }
        return present.isEmpty ? "toolbelt verified" : present.joined(separator: " · ")
    }

}

private struct CapabilityRail: View {
    struct Item: Identifiable {
        var id: String { title }
        let symbolName: String
        let title: String
        let value: String
    }

    let items: [Item]

    var body: some View {
        ChipFlowLayout(spacing: 7, lineSpacing: 7) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.symbolName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.brandBlue)
                    Text("\(item.title): \(item.value)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.appPanelBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.appBorder, lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MessageBubble: View {
    @EnvironmentObject private var chatStore: ChatStore
    let message: ChatMessage
    @State private var showingArtifact = false
    @State private var showingSecurity = false
    @State private var editingUserMessage: ChatMessage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 36)
            } else {
                AssistantAvatar()
                    .padding(.top, 1)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(message.role == .user ? "You" : message.modelDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if message.role == .assistant, let badge = statusBadge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(badge == "Failed" ? .red : Color.brandBlue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background((badge == "Failed" ? Color.red.opacity(0.08) : Color.brandBlue.opacity(0.08)), in: Capsule())
                    }
                    if let attestationStatus = messageAttestationStatus {
                        Button {
                            showingSecurity = true
                        } label: {
                            AttestedMessageChip(
                                status: attestationStatus,
                                modelID: message.model
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open attestation details")
                    }
                }

                Group {
                    if message.text.isEmpty && message.isStreaming {
                        HStack(spacing: 8) {
                            TypingDots()
                            Text(message.streamingStatusText)
                                .foregroundStyle(.secondary)
                        }
                    } else if message.role == .assistant {
                        MarkdownMessageText(text: message.text.isEmpty ? " " : message.text)
                    } else {
                        Text(message.text.isEmpty ? " " : message.text)
                            .textSelection(.enabled)
                    }
                }
                .font(.body)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(.horizontal, message.role == .user ? 14 : 0)
                .padding(.vertical, message.role == .user ? 11 : 0)
                .background(message.role == .user ? Color.brandBlue : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contextMenu {
                    Button {
                        Clipboard.copy(message.text)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    if message.role == .assistant {
                        Button {
                            chatStore.copySignedSnippet(for: message)
                        } label: {
                            Label("Copy Signed Snippet", systemImage: "checkmark.shield")
                        }

                        Button {
                            chatStore.regenerateResponse(for: message)
                        } label: {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                        }

                        Button {
                            chatStore.saveMessageAsProjectNote(message)
                        } label: {
                            Label(
                                chatStore.isMessageSavedToSelectedProject(message) ? "Saved to Project" : "Save to Project",
                                systemImage: chatStore.isMessageSavedToSelectedProject(message) ? "checkmark.circle" : "bookmark"
                            )
                        }
                        .disabled(chatStore.isMessageSavedToSelectedProject(message))
                    } else {
                        Button {
                            editingUserMessage = message
                        } label: {
                            Label("Edit & Branch", systemImage: "pencil")
                        }
                    }
                }

                if message.role == .assistant,
                   let branchVariant = message.branchVariant,
                   branchVariant.count > 1,
                   !message.isStreaming {
                    ResponseVariantPicker(variant: branchVariant) { responseID in
                        chatStore.selectResponseVariant(responseID)
                    }
                }

                if message.shouldShowAgentRunStatus {
                    AgentRunStatusStrip(message: message, toolCount: chatStore.ironclawToolNames.count) {
                        chatStore.regenerateResponse(for: message)
                    } onCancel: {
                        chatStore.cancelStream()
                    }
                }

                if !message.attachments.isEmpty {
                    MessageAttachmentStrip(attachments: message.attachments)
                }

                if message.role == .assistant && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !message.isStreaming {
                    AssistantInlineActions(
                        canSaveToProject: chatStore.selectedProject != nil,
                        isSavedToProject: chatStore.isMessageSavedToSelectedProject(message),
                        canOpen: message.isArtifactCandidate,
                        onCopy: { Clipboard.copy(message.text) },
                        onCopySigned: { chatStore.copySignedSnippet(for: message) },
                        onRegenerate: { chatStore.regenerateResponse(for: message) },
                        onSave: { chatStore.saveMessageAsProjectNote(message) },
                        onOpen: { showingArtifact = true },
                    )
                }

                if let pendingApproval = message.pendingApproval {
                    IronclawApprovalCard(messageID: message.id, approval: pendingApproval)
                        .environmentObject(chatStore)
                }

                if message.status == "failed", !message.shouldShowAgentRunStatus {
                    Label("Failed", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if message.role == .assistant && !message.sources.isEmpty {
                    SearchContextStrip(query: message.searchQuery, sources: message.sources)
                }
            }
            .frame(maxWidth: message.role == .user ? 560 : 740, alignment: message.role == .user ? .trailing : .leading)

            if message.role != .user {
                Spacer(minLength: 36)
            }
        }
        .sheet(isPresented: $showingArtifact) {
            ArtifactOutputView(message: message)
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingSecurity) {
            SecurityView()
                .environmentObject(chatStore)
        }
        .sheet(item: $editingUserMessage) { userMessage in
            EditUserMessageView(message: userMessage)
                .environmentObject(chatStore)
        }
    }

    private var statusBadge: String? {
        switch message.status {
        case "reasoning":
            return "Reasoning"
        case "searching":
            return "Web search"
        case "approval":
            return "Approval"
        case "failed":
            return "Failed"
        default:
            return nil
        }
    }

    private var messageAttestationStatus: AttestationStatus? {
        guard message.role == .assistant,
              let modelID = message.model,
              ChatStore.routeKind(forModelID: modelID) == .nearPrivate else {
            return nil
        }
        let status = AttestationStatus(snapshot: chatStore.attestationSnapshot, selectedModelID: modelID)
        switch status.effectiveState() {
        case .valid, .stale, .mismatch:
            return status
        case .unknown, .unavailable:
            return nil
        }
    }
}

private struct AttestedMessageChip: View {
    let status: AttestationStatus
    let modelID: String?

    var body: some View {
        let isCovered = status.coverage(for: modelID) == .covered
        let copy = status.userFacingCopy()
        Label(copy.badge, systemImage: status.symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isCovered ? Color.verifiedGreen : status.tintColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(status.tintColor.opacity(0.10), in: Capsule())
            .accessibilityHint(copy.detail)
    }
}

private struct ResponseVariantPicker: View {
    let variant: MessageBranchVariant
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            variantButton(
                symbolName: "chevron.left",
                responseID: variant.previousResponseID,
                label: "Previous response variant"
            )

            Text("Response \(variant.displayIndex) of \(variant.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            variantButton(
                symbolName: "chevron.right",
                responseID: variant.nextResponseID,
                label: "Next response variant"
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.appPanelBackground, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Response variant \(variant.displayIndex) of \(variant.count)")
    }

    private func variantButton(symbolName: String, responseID: String?, label: String) -> some View {
        Button {
            if let responseID {
                onSelect(responseID)
            }
        } label: {
            Image(systemName: symbolName)
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .foregroundStyle(responseID == nil ? Color.secondary.opacity(0.45) : Color.brandBlue)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(responseID == nil)
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct EditUserMessageView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    let message: ChatMessage
    @State private var prompt: String

    init(message: ChatMessage) {
        self.message = message
        _prompt = State(initialValue: message.text)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Edit prompt", text: $prompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(5...12)
                        .padding(10)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } header: {
                    Text("Edit Prompt")
                } footer: {
                    Text("This starts a new branch from the original turn.")
                }

                if !message.attachments.isEmpty {
                    Section("Kept Files") {
                        ForEach(message.attachments) { attachment in
                            Label {
                                Text(attachment.name)
                                    .lineLimit(1)
                            } icon: {
                                Image(systemName: attachment.systemImageName)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Edit Message")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        chatStore.editAndResend(message, replacementText: prompt)
                        dismiss()
                    }
                    .disabled(trimmedPrompt.isEmpty && message.attachments.isEmpty)
                }
            }
        }
        .platformMediumDetent()
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct AgentRunStatusStrip: View {
    let message: ChatMessage
    let toolCount: Int
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        TimelineView(.periodic(from: message.createdAt, by: 1)) { context in
            let isStale = isStaleRun(now: context.date)
            HStack(spacing: 8) {
                Image(systemName: symbolName(isStale: isStale))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tintColor(isStale: isStale))
                    .frame(width: 24, height: 24)
                    .background(tintColor(isStale: isStale).opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title(isStale: isStale))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(elapsedText(now: context.date))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let detail = detailText(isStale: isStale) {
                        Text(detail)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if isStale && message.isStreaming {
                    Button(action: onCancel) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop stalled IronClaw run")
                } else if message.status == "failed" || isStale {
                    Button(action: onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry IronClaw run")
                }
            }
            .padding(9)
            .frame(maxWidth: 520, alignment: .leading)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tintColor(isStale: isStale).opacity(message.status == "failed" || isStale ? 0.24 : 0.16), lineWidth: 1)
            }
        }
    }

    private func title(isStale: Bool) -> String {
        if message.status == "failed" {
            return "Run stopped"
        }
        if isStale {
            return "No output received"
        }
        if message.pendingApproval != nil || message.status == "approval" {
            return "Waiting for approval"
        }
        if message.status == "searching" {
            return "Gathering context"
        }
        return "Agent running"
    }

    private func detailText(isStale: Bool) -> String? {
        if message.status == "failed" {
            return "The bridge stopped before a final answer. Retry after checking the hosted endpoint."
        }
        if isStale {
            return message.isStreaming
                ? "The hosted run may have stalled. Stop it, then retry from the phone."
                : "The hosted run may have stalled. Retry starts a fresh phone-controlled run."
        }
        if message.pendingApproval != nil || message.status == "approval" {
            return "Approve or deny the requested tool action to continue."
        }
        return nil
    }

    private func symbolName(isStale: Bool) -> String {
        if message.status == "failed" {
            return "exclamationmark.triangle.fill"
        }
        if isStale {
            return "clock.badge.exclamationmark"
        }
        if message.pendingApproval != nil || message.status == "approval" {
            return "lock.shield.fill"
        }
        return "arrow.triangle.2.circlepath"
    }

    private func tintColor(isStale: Bool) -> Color {
        if message.status == "failed" { return .red }
        if isStale { return .orange }
        return Color.brandBlue
    }

    private func elapsedText(now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(message.createdAt))
        if message.status == "failed" {
            return "after \(Self.compactDuration(elapsed))"
        }
        if isStaleRun(now: now) {
            return "for \(Self.compactDuration(elapsed))"
        }
        if message.pendingApproval != nil || message.status == "approval" {
            return "paused \(Self.compactDuration(elapsed))"
        }
        return Self.compactDuration(elapsed)
    }

    private func isStaleRun(now: Date) -> Bool {
        guard message.pendingApproval == nil,
              message.status != "failed" else {
            return false
        }
        let activeStatuses = ["reasoning", "searching", "running", "queued", "in_progress"]
        guard message.isStreaming || activeStatuses.contains(message.status.lowercased()) else {
            return false
        }
        return now.timeIntervalSince(message.createdAt) > 2 * 60
    }

    private static func compactDuration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded(.down))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h"
    }
}

private struct AssistantInlineActions: View {
    let canSaveToProject: Bool
    let isSavedToProject: Bool
    let canOpen: Bool
    let onCopy: () -> Void
    let onCopySigned: () -> Void
    let onRegenerate: () -> Void
    let onSave: () -> Void
    let onOpen: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                actionButton(symbolName: "doc.on.doc", label: "Copy", action: onCopy)
                actionButton(symbolName: "checkmark.shield", label: "Copy Signed Snippet", action: onCopySigned)
                saveButton
                if canOpen {
                    actionButton(symbolName: "rectangle.expand.vertical", label: "Open Output", action: onOpen)
                }
                actionButton(symbolName: "arrow.clockwise", label: "Regenerate", action: onRegenerate)
            }
        }
        .scrollClipDisabled()
        .padding(.top, 2)
    }

    private var saveButton: some View {
        Button(action: onSave) {
            Label(saveLabel, systemImage: saveSymbolName)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(saveForeground)
                .frame(height: 30)
                .padding(.horizontal, 10)
                .background(saveBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSavedToProject)
        .accessibilityLabel(saveAccessibilityLabel)
    }

    private func actionButton(symbolName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var saveLabel: String {
        if isSavedToProject {
            return "Saved"
        }
        return canSaveToProject ? "Save" : "Project"
    }

    private var saveSymbolName: String {
        if isSavedToProject {
            return "checkmark"
        }
        return canSaveToProject ? "bookmark.fill" : "bookmark"
    }

    private var saveForeground: Color {
        isSavedToProject || canSaveToProject ? Color.brandBlue : .secondary
    }

    private var saveBackground: Color {
        isSavedToProject || canSaveToProject ? Color.brandBlue.opacity(0.10) : Color.appSecondaryBackground
    }

    private var saveAccessibilityLabel: String {
        if isSavedToProject {
            return "Saved to Project"
        }
        return canSaveToProject ? "Save to Project" : "Select a Project to Save"
    }
}

private struct ArtifactOutputView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    let message: ChatMessage

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 32, height: 32)
                            .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.modelDisplayName)
                                .font(.headline.weight(.semibold))
                            Text(message.createdAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    Divider()

                    MarkdownMessageText(text: message.text)
                        .font(.body)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.appBackground)
            .navigationTitle("Output")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Clipboard.copy(message.text)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copy Output")

                    Button {
                        chatStore.copySignedSnippet(for: message)
                    } label: {
                        Image(systemName: "checkmark.shield")
                    }
                    .accessibilityLabel("Copy Signed Snippet")

                    Button {
                        chatStore.saveMessageAsProjectNote(message)
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .accessibilityLabel("Save Output to Project")
                }
            }
        }
    }
}

private extension ChatMessage {
    var isArtifactCandidate: Bool {
        guard role == .assistant, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return text.count > 1_200 ||
            text.contains("```") ||
            text.contains("\n|") ||
            text.localizedCaseInsensitiveContains("# ")
    }
}

private struct HostedHandoffPreflightSheet: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    let preflight: HostedIronclawHandoffPreflight

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 40, height: 40)
                            .background(Color.brandBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Run on hosted IronClaw?")
                                .font(.title3.weight(.semibold))
                            Text("This sends the prompt and selected phone context to \(preflight.destinationHost).")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("What leaves the phone")
                            .font(.subheadline.weight(.semibold))
                        ForEach(preflight.disclosedItems, id: \.self) { item in
                            Label(item, systemImage: "checkmark.shield")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if !preflight.promptPreview.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Prompt preview")
                                .font(.subheadline.weight(.semibold))
                            Text(preflight.promptPreview)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(8)
                                .textSelection(.enabled)
                        }
                    }

                    VStack(spacing: 10) {
                        Button {
                            chatStore.confirmHostedHandoff(preflight)
                            dismiss()
                        } label: {
                            Label("Run on workstation", systemImage: "terminal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(role: .cancel) {
                            chatStore.cancelHostedHandoff()
                            dismiss()
                        } label: {
                            Text("Keep on phone")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(20)
            }
            .background(HomeSurfaceBackground().ignoresSafeArea())
            .navigationTitle("Confirm Handoff")
            .platformInlineNavigationTitle()
        }
    }
}

private struct IronclawApprovalCard: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.openURL) private var openURL
    @State private var credentialToken = ""
    @State private var pendingGateURL: URL?
    @State private var confirmingAlways = false
    let messageID: String
    let approval: IronclawPendingGate

    var body: some View {
        if approval.isAuthenticationGate {
            authenticationBody
        } else {
            approvalBody
        }
    }

    private var approvalBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Approval required")
                        .font(.subheadline.weight(.semibold))
                    Text(approval.toolName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(approval.description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let parameterPreview = approval.parameterPreview {
                Text(parameterPreview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 8) {
                Button {
                    chatStore.resolveIronclawApproval(messageID: messageID, approval: approval, action: .approve)
                } label: {
                    Label("Allow once", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)

                if approval.locallyAllowsAlways {
                    Button {
                        confirmingAlways = true
                    } label: {
                        Label("Always", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.bordered)
                } else if let reason = approval.alwaysUnavailableReason {
                    Label(reason, systemImage: "lock.shield")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(role: .destructive) {
                    chatStore.resolveIronclawApproval(messageID: messageID, approval: approval, action: .deny)
                } label: {
                    Label("Deny", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .confirmationDialog(
            "Always approve this tool?",
            isPresented: $confirmingAlways,
            titleVisibility: .visible
        ) {
            Button("Always approve \(approval.toolName)") {
                chatStore.resolveIronclawApproval(messageID: messageID, approval: approval, action: .always)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only applies to the hosted IronClaw scope returned by the endpoint. Powerful command, file, network, and credential tools still require per-run approval on phone.")
        }
        .confirmationDialog(
            "Open external site?",
            isPresented: Binding(
                get: { pendingGateURL != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingGateURL = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingGateURL
        ) { url in
            Button("Open \(url.host ?? "site")") {
                openURL(url)
                pendingGateURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingGateURL = nil
            }
        } message: { url in
            Text("IronClaw returned this HTTPS URL. Continue only if you recognize the host: \(url.host ?? "unknown").")
        }
    }

    private var authenticationBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tool sign-in required")
                        .font(.subheadline.weight(.semibold))
                    Text("\(approval.authenticationDisplayName) - \(approval.toolName)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(approval.authenticationHelpText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Label("Hosted workstation", systemImage: "terminal")
                Label("Credential gated", systemImage: "lock.shield")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.brandBlue)

            if let parameterPreview = approval.parameterPreview {
                Text(parameterPreview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let authURL = approval.authURLValue {
                Button {
                    openGateURL(authURL)
                } label: {
                    Label("Open sign-in\(approval.authURLHost.map { " - \($0)" } ?? "")", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                .font(.caption.weight(.semibold))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("\(approval.authenticationDisplayName) token", text: $credentialToken)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .tokenInputTraits()
                        .onSubmit(submitCredential)

                    HStack(spacing: 8) {
                        Button(action: submitCredential) {
                            Label("Save credential", systemImage: "key")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmedCredentialToken.isEmpty)

                        Button(role: .destructive) {
                            chatStore.resolveIronclawApproval(messageID: messageID, approval: approval, action: .deny)
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            if let setupURL = approval.setupURLValue {
                Button {
                    openGateURL(setupURL)
                } label: {
                    Label("Setup guide\(approval.setupURLHost.map { " - \($0)" } ?? "")", systemImage: "book")
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))
            }

            if approval.authURLValue != nil {
                Button(role: .destructive) {
                    chatStore.resolveIronclawApproval(messageID: messageID, approval: approval, action: .deny)
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))
            }
        }
        .padding(12)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .confirmationDialog(
            "Open external site?",
            isPresented: Binding(
                get: { pendingGateURL != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingGateURL = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingGateURL
        ) { url in
            Button("Open \(url.host ?? "site")") {
                openURL(url)
                pendingGateURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingGateURL = nil
            }
        } message: { url in
            Text("IronClaw returned this HTTPS URL. Continue only if you recognize the host: \(url.host ?? "unknown").")
        }
    }

    private var trimmedCredentialToken: String {
        credentialToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openGateURL(_ url: URL) {
        guard Self.isFamiliarGateHost(url.host) else {
            pendingGateURL = url
            return
        }
        openURL(url)
    }

    private static func isFamiliarGateHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "github.com" ||
            host == "accounts.google.com" ||
            host == "cloud.near.ai" ||
            host == "near.ai" ||
            host.hasSuffix(".near.ai") ||
            host.hasSuffix(".agents.near.ai")
    }

    private func submitCredential() {
        let token = trimmedCredentialToken
        guard !token.isEmpty else { return }
        chatStore.resolveIronclawCredential(messageID: messageID, approval: approval, token: token)
        credentialToken = ""
    }
}

private struct AssistantAvatar: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.brandBlue.opacity(0.10))
            Image(systemName: "lock.shield.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandBlue)
        }
        .frame(width: 30, height: 30)
    }
}

private struct MessageAttachmentStrip: View {
    let attachments: [ChatAttachment]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(attachments) { attachment in
                Label {
                    Text(attachment.name)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: attachment.systemImageName)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private enum ComposerFocusMode: String, CaseIterable, Identifiable {
    case auto
    case web
    case project
    case research

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .web: "Web"
        case .project: "Project"
        case .research: "Research"
        }
    }

    var symbolName: String {
        switch self {
        case .auto: "sparkles"
        case .web: "globe"
        case .project: "folder"
        case .research: "doc.text.magnifyingglass"
        }
    }
}

private enum SlashCommandAction {
    case council
    case agent
    case verify
    case project
    case sources
}

private struct SlashCommandSuggestion: Identifiable {
    var id: String { command }
    let command: String
    let title: String
    let subtitle: String
    let symbolName: String
    let action: SlashCommandAction
}

private struct InputBar: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var showingFileImporter = false
    @State private var showingProjectFiles = false
    @State private var showingSecurity = false
    @State private var showingAgentWorkspace = false
    @State private var showingAccountSettings = false
    @State private var showingCapabilities = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowProjectContextStrip {
                ProjectContextStrip(
                    attachments: chatStore.activeProjectContextAttachments,
                    linkCount: chatStore.activeProjectContextLinks.count
                )
            }

            if !chatStore.pendingAttachments.isEmpty {
                AttachmentStrip(attachments: chatStore.pendingAttachments) { attachment in
                    chatStore.removePendingAttachment(attachment)
                }
            }

            if chatStore.isUploadingAttachment {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Uploading file")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }

            if let issue = chatStore.routeReadinessIssue {
                RouteReadinessRecoveryCard(
                    issue: issue,
                    onPrimaryAction: { handleRouteReadinessRecovery(issue.recoveryAction) },
                    onSwitchPrivate: { chatStore.performRouteReadinessRecovery(.switchToPrivate) },
                    onViewCapabilities: { showingCapabilities = true }
                )
            } else if let notice = chatStore.selectedRouteNotice {
                Label(notice, systemImage: chatStore.selectedRouteUsesNearCloud ? "cloud" : "point.3.connected.trianglepath.dotted")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 2)
            }

            focusModeRow

            if !visibleSlashCommands.isEmpty {
                slashCommandTray
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField(composerPlaceholder, text: $chatStore.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .tokenInputTraits()
                    .autocorrectionDisabled()
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .onSubmit {
                        chatStore.sendDraft()
                        isFocused = false
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                    .disabled(chatStore.isStreaming)
                    .accessibilityLabel("Message")
                    .accessibilityHint(chatStore.isStreaming ? "Stop the current response before editing the draft." : "Enter a message or slash command.")

                HStack(spacing: 8) {
                    Button {
                        AppHaptics.selection()
                        showingFileImporter = true
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(chatStore.isStreaming)
                    .accessibilityLabel("Attach File")

                    Spacer(minLength: 0)

                    Button {
                        if chatStore.isStreaming {
                            AppHaptics.mediumImpact()
                            chatStore.cancelStream()
                        } else {
                            AppHaptics.lightImpact()
                            chatStore.sendDraft()
                            isFocused = false
                        }
                    } label: {
                        Image(systemName: chatStore.isStreaming ? "stop.fill" : "arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(sendIconColor)
                            .frame(width: 32, height: 32)
                            .background(sendButtonColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(sendDisabled)
                    .scaleEffect(sendButtonScale)
                    .opacity(reduceMotion ? (sendDisabled ? 0.72 : 1) : 1)
                    .animation(sendButtonAnimation, value: canSend)
                    .animation(sendButtonAnimation, value: chatStore.isStreaming)
                    .accessibilityLabel(chatStore.isStreaming ? "Stop response" : "Send message")
                    .accessibilityHint(chatStore.isStreaming ? "Stops the current response." : "Sends the draft and staged attachments.")
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isFocused ? Color.brandBlue.opacity(0.45) : Color.appBorder, lineWidth: 1)
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .plainText, .text, .commaSeparatedText, .json, .data],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                for url in urls.prefix(5) {
                    Task { await chatStore.addAttachment(from: url) }
                }
            }
        }
        .sheet(isPresented: $showingProjectFiles) {
            ProjectFilesView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingSecurity) {
            SecurityView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingAgentWorkspace) {
            AgentWorkspaceView()
                .environmentObject(chatStore)
        }
        .sheet(isPresented: $showingAccountSettings) {
            AccountSettingsView(onRunSetupAgain: {})
                .environmentObject(chatStore)
                .environmentObject(sessionStore)
        }
        .sheet(isPresented: $showingCapabilities) {
            CapabilitiesView(
                onOpenAccountSettings: {
                    showingAccountSettings = true
                },
                onOpenSecurity: {
                    showingSecurity = true
                },
                onOpenAgentWorkspace: {
                    showingAgentWorkspace = true
                },
                onRunSetupAgain: nil
            )
            .environmentObject(chatStore)
            .environmentObject(sessionStore)
        }
    }

    private var shouldShowProjectContextStrip: Bool {
        !chatStore.activeProjectContextAttachments.isEmpty || !chatStore.activeProjectContextLinks.isEmpty
    }

    private var canSend: Bool {
        !chatStore.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !chatStore.pendingAttachments.isEmpty
    }

    private var sendDisabled: Bool {
        if chatStore.isStreaming {
            return false
        }
        return !canSend
    }

    private var sendButtonColor: Color {
        if chatStore.isStreaming {
            return .red.opacity(0.90)
        }
        return sendDisabled ? Color.appSecondaryBackground : Color.brandBlue
    }

    private var sendIconColor: Color {
        sendDisabled && !chatStore.isStreaming ? .secondary : .white
    }

    private var sendButtonScale: CGFloat {
        guard !reduceMotion else { return 1 }
        if chatStore.isStreaming {
            return 1
        }
        return canSend ? 1 : 0.9
    }

    private var sendButtonAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.72)
    }

    private var composerPlaceholder: String {
        if chatStore.selectedRouteUsesNearCloud || chatStore.selectedProviderDisplayName == "IronClaw" {
            return chatStore.inputPlaceholder
        }
        if researchButtonActive {
            return "Ask for a researched answer with citations"
        }
        switch chatStore.sourceMode {
        case .auto:
            return "Ask anything"
        case .web:
            return "Ask with live web"
        case .files:
            return "Ask your project files"
        case .links:
            return "Ask your saved links"
        case .all:
            return "Ask across sources"
        }
    }

    private var researchButtonActive: Bool {
        chatStore.researchModeEnabled && !chatStore.selectedRouteUsesNearCloud
    }

    private var composerSourceTitle: String {
        if chatStore.selectedRouteUsesNearCloud {
            return "Cloud"
        }
        if researchButtonActive {
            return "Research"
        }
        return chatStore.sourceMode.shortTitle
    }

    private var composerContextModes: [ChatSourceMode] {
        [.auto, .web, .files, .links]
    }

    private var focusModes: [ComposerFocusMode] {
        [.auto, .web, .project, .research]
    }

    private var selectedFocusMode: ComposerFocusMode? {
        if chatStore.selectedRouteUsesNearCloud {
            return nil
        }
        if researchButtonActive {
            return .research
        }
        switch chatStore.sourceMode {
        case .auto: return .auto
        case .web: return .web
        case .files, .links, .all: return .project
        }
    }

    private var focusModeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(focusModes) { mode in
                    Button {
                        selectFocusMode(mode)
                    } label: {
                        Label(mode.title, systemImage: mode.symbolName)
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .foregroundStyle(focusModeColor(mode))
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(focusModeBackground(mode), in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(focusModeBorder(mode), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(chatStore.isStreaming || chatStore.selectedRouteUsesNearCloud)
                    .accessibilityLabel(selectedFocusMode == mode ? "Focus: \(mode.title), selected" : "Focus: \(mode.title)")
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var slashCommands: [SlashCommandSuggestion] {
        [
            SlashCommandSuggestion(
                command: "/council",
                title: "Council",
                subtitle: "Use a multi-model answer",
                symbolName: "square.grid.2x2",
                action: .council
            ),
            SlashCommandSuggestion(
                command: "/agent",
                title: "Agent",
                subtitle: "Open IronClaw mission control",
                symbolName: "terminal",
                action: .agent
            ),
            SlashCommandSuggestion(
                command: "/verify",
                title: "Verify",
                subtitle: "Open attestation details",
                symbolName: "checkmark.shield",
                action: .verify
            ),
            SlashCommandSuggestion(
                command: "/project",
                title: "Project",
                subtitle: "Open project context",
                symbolName: "folder.badge.gearshape",
                action: .project
            ),
            SlashCommandSuggestion(
                command: "/sources",
                title: "Sources",
                subtitle: "Use available web, file, and link context",
                symbolName: "rectangle.3.group",
                action: .sources
            )
        ]
    }

    private var slashQuery: String? {
        let trimmed = chatStore.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let token = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first ?? Substring(trimmed)
        return String(token.dropFirst()).lowercased()
    }

    private var visibleSlashCommands: [SlashCommandSuggestion] {
        guard let query = slashQuery else { return [] }
        guard !query.isEmpty else { return slashCommands }
        return slashCommands.filter { suggestion in
            suggestion.command.dropFirst().lowercased().hasPrefix(query) ||
                suggestion.title.lowercased().contains(query)
        }
    }

    private var slashCommandTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(visibleSlashCommands) { suggestion in
                Button {
                    applySlashCommand(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 24, height: 24)
                            .background(Color.brandBlue.opacity(0.09), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.command)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.primary)
                            Text(suggestion.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "return")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(suggestion.command), \(suggestion.title)")
                .accessibilityHint(suggestion.subtitle)
            }
        }
    }

    private func selectFocusMode(_ mode: ComposerFocusMode) {
        guard !chatStore.selectedRouteUsesNearCloud else { return }
        AppHaptics.selection()
        switch mode {
        case .auto:
            chatStore.selectSourceMode(.auto)
        case .web:
            chatStore.selectSourceMode(.web)
        case .project:
            chatStore.selectSourceMode(chatStore.selectedProject == nil ? .files : .all)
            if chatStore.selectedProject == nil && chatStore.pendingAttachments.isEmpty {
                showingProjectFiles = true
            }
        case .research:
            if chatStore.sourceMode != .web {
                chatStore.sourceMode = .web
            }
            if !chatStore.researchModeEnabled {
                chatStore.toggleResearchMode()
            }
        }
    }

    private func applySlashCommand(_ suggestion: SlashCommandSuggestion) {
        AppHaptics.selection()
        let remainder = remainingDraft(after: suggestion.command)
        switch suggestion.action {
        case .council:
            chatStore.useDefaultCouncilLineup()
            chatStore.draft = remainder
            isFocused = true
        case .agent:
            chatStore.draft = remainder.isEmpty ? "" : "Agent mission: \(remainder)"
            showingAgentWorkspace = true
            isFocused = false
        case .verify:
            chatStore.draft = remainder
            showingSecurity = true
            isFocused = false
        case .project:
            chatStore.draft = remainder
            showingProjectFiles = true
            isFocused = false
        case .sources:
            if !chatStore.selectedRouteUsesNearCloud {
                chatStore.selectSourceMode(chatStore.selectedProject == nil ? .web : .all)
            }
            chatStore.draft = remainder
            showingProjectFiles = chatStore.selectedProject != nil
            isFocused = chatStore.selectedProject == nil
        }
    }

    private func handleRouteReadinessRecovery(_ action: ChatStore.RouteReadinessIssue.RecoveryAction) {
        AppHaptics.selection()
        switch action {
        case .addNearCloudKey, .configureIronClawEndpoint:
            showingAccountSettings = true
        case .switchToPrivate, .editCouncilLineup:
            chatStore.performRouteReadinessRecovery(action)
        }
    }

    private func remainingDraft(after command: String) -> String {
        let trimmed = chatStore.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(command) else { return "" }
        return trimmed
            .dropFirst(command.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func focusModeColor(_ mode: ComposerFocusMode) -> Color {
        guard selectedFocusMode == mode else { return .secondary }
        return mode == .auto ? Color.brandBlack : Color.white
    }

    private func focusModeBackground(_ mode: ComposerFocusMode) -> Color {
        guard selectedFocusMode == mode else { return Color.clear }
        return mode == .auto ? Color.brandSky : Color.brandBlue
    }

    private func focusModeBorder(_ mode: ComposerFocusMode) -> Color {
        guard selectedFocusMode == mode else { return Color.appBorder.opacity(0.8) }
        return Color.clear
    }
}

private struct RouteReadinessRecoveryCard: View {
    let issue: ChatStore.RouteReadinessIssue
    let onPrimaryAction: () -> Void
    let onSwitchPrivate: () -> Void
    let onViewCapabilities: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.appSymbolBlueBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(issue.message)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button(action: onPrimaryAction) {
                    Label(issue.recoveryTitle, systemImage: primarySymbolName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color.primaryAction, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                if issue.recoveryAction != .switchToPrivate {
                    Button(action: onSwitchPrivate) {
                        Text("Use Private")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.primaryAction)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: onViewCapabilities) {
                Label("View Capabilities", systemImage: "square.grid.2x2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primaryAction)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(issue.title). \(issue.message)")
    }

    private var symbolName: String {
        switch issue.route {
        case .nearCloud: "key"
        case .hostedIronclaw: "terminal"
        case .council: "square.grid.2x2"
        }
    }

    private var primarySymbolName: String {
        switch issue.recoveryAction {
        case .addNearCloudKey: "key"
        case .configureIronClawEndpoint: "point.3.connected.trianglepath.dotted"
        case .switchToPrivate: "lock.shield"
        case .editCouncilLineup: "slider.horizontal.3"
        }
    }
}

private struct ProjectContextStrip: View {
    let attachments: [ChatAttachment]
    let linkCount: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Label(contextLabel, systemImage: "folder")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.brandBlue.opacity(0.10), in: Capsule())

                ForEach(attachments.prefix(4)) { attachment in
                    Label(attachment.name, systemImage: attachment.systemImageName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.appSecondaryBackground, in: Capsule())
                }
            }
        }
    }

    private var contextLabel: String {
        var parts: [String] = []
        if !attachments.isEmpty {
            parts.append(countLabel(attachments.count, singular: "file"))
        }
        if linkCount > 0 {
            parts.append(countLabel(linkCount, singular: "source link"))
        }
        return parts.isEmpty ? "Project context" : parts.joined(separator: " · ")
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}

private struct AttachmentStrip: View {
    let attachments: [ChatAttachment]
    let onRemove: (ChatAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: attachment.systemImageName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 28, height: 28)
                            .background(Color.brandBlue.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(attachmentShelfTitle(for: attachment))
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                            Text(attachmentShelfDetail(for: attachment))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(attachmentShelfTitle(for: attachment)), \(attachmentShelfDetail(for: attachment))")
                        Button {
                            AppHaptics.selection()
                            onRemove(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(attachment.name)")
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 56)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func attachmentShelfTitle(for attachment: ChatAttachment) -> String {
        if attachment.isLocalPendingText {
            return "Large paste staged"
        }
        if attachment.kind == "pdf_text" {
            return "PDF text extracted"
        }
        return attachment.name
    }

    private func attachmentShelfDetail(for attachment: ChatAttachment) -> String {
        var parts: [String] = []
        if attachment.isLocalPendingText {
            parts.append("Uploads as text on send")
            parts.append(attachment.name)
        } else if attachment.kind == "pdf_text" {
            parts.append("Readable text attachment")
            parts.append(attachment.name)
        } else {
            parts.append(attachment.displayKind)
        }
        if let displaySize = attachment.displaySize {
            parts.append(displaySize)
        }
        return parts.joined(separator: " · ")
    }
}

private struct MarkdownMessageText: View {
    let text: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlock.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(blocks) { block in
                switch block.kind {
                case let .paragraph(value):
                    InlineMarkdownText(text: value)
                        .lineSpacing(2)
                case let .heading(value, level):
                    InlineMarkdownText(text: value)
                        .font(level <= 2 ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
                        .padding(.top, 2)
                case let .unorderedList(items):
                    MarkdownBulletList(items: items)
                case let .orderedList(items):
                    MarkdownNumberedList(items: items)
                case let .quote(value):
                    MarkdownQuote(text: value)
                case let .code(code, language):
                    MarkdownCodeBlock(code: code, language: language)
                case .divider:
                    Divider()
                        .padding(.vertical, 3)
                case let .table(rows):
                    MarkdownTable(rows: rows)
                }
            }
        }
        .textSelection(.enabled)
    }
}

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case paragraph(String)
        case heading(String, level: Int)
        case unorderedList([String])
        case orderedList([(Int, String)])
        case quote(String)
        case code(String, language: String?)
        case divider
        case table([[String]])
    }

    let id: Int
    let kind: Kind

    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0
        var blockID = 0

        func nextID() -> Int {
            defer { blockID += 1 }
            return blockID
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let current = lines[index]
                    if current.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(current)
                    index += 1
                }
                blocks.append(MarkdownBlock(id: nextID(), kind: .code(codeLines.joined(separator: "\n"), language: language.isEmpty ? nil : language)))
                continue
            }

            if isDivider(trimmed) {
                blocks.append(MarkdownBlock(id: nextID(), kind: .divider))
                index += 1
                continue
            }

            if let heading = heading(from: trimmed) {
                blocks.append(MarkdownBlock(id: nextID(), kind: .heading(heading.text, level: heading.level)))
                index += 1
                continue
            }

            if isTableStart(at: index, lines: lines) {
                var rows: [[String]] = [tableRow(from: lines[index])]
                index += 2
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard current.contains("|"), !current.isEmpty, !isDivider(current) else { break }
                    rows.append(tableRow(from: current))
                    index += 1
                }
                blocks.append(MarkdownBlock(id: nextID(), kind: .table(rows)))
                continue
            }

            if let firstItem = unorderedListItem(from: trimmed) {
                var items = [firstItem]
                index += 1
                while index < lines.count,
                      let item = unorderedListItem(from: lines[index].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(MarkdownBlock(id: nextID(), kind: .unorderedList(items)))
                continue
            }

            if let firstItem = orderedListItem(from: trimmed) {
                var items = [firstItem]
                index += 1
                while index < lines.count,
                      let item = orderedListItem(from: lines[index].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(MarkdownBlock(id: nextID(), kind: .orderedList(items)))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines = [String(trimmed.drop(while: { $0 == ">" || $0 == " " }))]
                index += 1
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard current.hasPrefix(">") else { break }
                    quoteLines.append(String(current.drop(while: { $0 == ">" || $0 == " " })))
                    index += 1
                }
                blocks.append(MarkdownBlock(id: nextID(), kind: .quote(quoteLines.joined(separator: "\n"))))
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let current = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !current.isEmpty,
                      !current.hasPrefix("```"),
                      !isDivider(current),
                      heading(from: current) == nil,
                      unorderedListItem(from: current) == nil,
                      orderedListItem(from: current) == nil,
                      !current.hasPrefix(">"),
                      !isTableStart(at: index, lines: lines) else {
                    break
                }
                paragraphLines.append(current)
                index += 1
            }
            blocks.append(MarkdownBlock(id: nextID(), kind: .paragraph(paragraphLines.joined(separator: " "))))
        }

        return blocks.isEmpty ? [MarkdownBlock(id: 0, kind: .paragraph(text))] : blocks
    }

    private static func heading(from line: String) -> (text: String, level: Int)? {
        guard line.hasPrefix("#") else { return nil }
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let stripped = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? nil : (stripped, level)
    }

    private static func unorderedListItem(from line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedListItem(from line: String) -> (Int, String)? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty,
              let number = Int(digits),
              line.dropFirst(digits.count).hasPrefix(". ") else {
            return nil
        }
        return (number, String(line.dropFirst(digits.count + 2)))
    }

    private static func isDivider(_ line: String) -> Bool {
        let normalized = line.replacingOccurrences(of: " ", with: "")
        return normalized == "---" || normalized == "***" || normalized == "___"
    }

    private static func isTableStart(at index: Int, lines: [String]) -> Bool {
        guard lines.indices.contains(index + 1) else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard header.contains("|"), separator.contains("|") else { return false }
        let allowed = CharacterSet(charactersIn: "|:- ")
        return separator.unicodeScalars.allSatisfy { allowed.contains($0) } &&
            separator.contains("-")
    }

    private static func tableRow(from line: String) -> [String] {
        var columns = line.split(separator: "|", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if columns.first?.isEmpty == true {
            columns.removeFirst()
        }
        if columns.last?.isEmpty == true {
            columns.removeLast()
        }
        return columns
    }
}

private struct MarkdownBulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4, weight: .bold))
                        .foregroundStyle(.secondary)
                    InlineMarkdownText(text: item)
                        .lineSpacing(2)
                }
            }
        }
    }
}

private struct MarkdownNumberedList: View {
    let items: [(Int, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(item.0).")
                        .font(.callout.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 22, alignment: .trailing)
                    InlineMarkdownText(text: item.1)
                        .lineSpacing(2)
                }
            }
        }
    }
}

private struct MarkdownQuote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Color.brandBlue.opacity(0.55))
                .frame(width: 3)
            InlineMarkdownText(text: text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(.vertical, 2)
    }
}

private struct MarkdownCodeBlock: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language {
                    Text(language.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    Clipboard.copy(code)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Copy Code")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.brandBlack.opacity(0.035))

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct MarkdownTable: View {
    let rows: [[String]]

    private var columnCount: Int {
        rows.map(\.count).max() ?? 0
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { columnIndex in
                            InlineMarkdownText(text: row.indices.contains(columnIndex) ? row[columnIndex] : "")
                                .font(rowIndex == 0 ? .caption.weight(.semibold) : .caption)
                                .foregroundStyle(rowIndex == 0 ? .primary : .secondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(
                                    minWidth: columnIndex == 0 ? 74 : 92,
                                    maxWidth: columnIndex == 0 ? 96 : 128,
                                    alignment: .leading
                                )
                                .background(rowIndex == 0 ? Color.brandBlue.opacity(0.08) : Color.clear)
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct InlineMarkdownText: View {
    let text: String

    private var attributedText: AttributedString {
        var attributed = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        for run in attributed.runs {
            guard let url = run.link, !Self.isSafeInlineURL(url) else { continue }
            attributed[run.range].link = nil
        }
        return attributed
    }

    private static func isSafeInlineURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }
        return true
    }

    var body: some View {
        Text(attributedText)
    }
}

private struct SearchContextStrip: View {
    let query: String?
    let sources: [WebSearchSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                Text("Evidence")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(headerText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(sources.prefix(5).enumerated()), id: \.element.id) { index, source in
                    if let url = source.safeURL {
                        Link(destination: url) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.caption2.monospacedDigit().weight(.bold))
                                    .foregroundStyle(Color.brandBlue)
                                    .frame(width: 20, height: 20)
                                    .background(Color.brandBlue.opacity(0.10), in: Circle())

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(sourceTitle(source))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(sourceSubtitle(source))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: 620, alignment: .leading)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.10), lineWidth: 1)
        )
    }

    private var headerText: String {
        let sourceCount = sources.count
        let sourceText = sourceCount == 1 ? "1 source" : "\(sourceCount) sources"
        guard let query = displayQuery, !query.isEmpty else {
            return sourceText
        }
        return "Searched \(query) · \(sourceText)"
    }

    private var displayQuery: String? {
        guard var value = query?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        if let range = value.range(of: "Mission brief from phone:", options: .caseInsensitive) {
            value = String(value[range.upperBound...])
        }
        if let range = value.range(of: "Execution contract:", options: .caseInsensitive) {
            value = String(value[..<range.lowerBound])
        }
        value = value
            .replacingOccurrences(
                of: #"(?i)^(?:IronClaw Agent|Hosted IronClaw) Mission:\s*(?:[^:]+:\s*)?"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count > 96 {
            return "\(value.prefix(93))..."
        }
        return value.isEmpty ? nil : value
    }

    private func sourceTitle(_ source: WebSearchSource) -> String {
        let title = source.title?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return title.count > 34 ? "\(title.prefix(31))..." : title
        }
        return source.host
    }

    private func sourceSubtitle(_ source: WebSearchSource) -> String {
        var parts = [source.host]
        if let publishedAt = source.publishedAt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !publishedAt.isEmpty {
            parts.append(publishedAt)
        }
        return parts.joined(separator: " · ")
    }
}

private struct TypingDots: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.brandBlue)
                    .frame(width: 5, height: 5)
                    .opacity(pulse ? 0.35 : 1)
                    .animation(
                        .easeInOut(duration: 0.7)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: pulse
                    )
            }
        }
        .onAppear {
            pulse = true
        }
    }
}

private extension View {
    func workspaceListRow(top: CGFloat = 3, bottom: CGFloat = 3) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 14, bottom: bottom, trailing: 14))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private extension ChatMessage {
    var shouldShowAgentRunStatus: Bool {
        guard role == .assistant, model == ModelOption.ironclawModelID else {
            return false
        }
        return isStreaming ||
            pendingApproval != nil ||
            ["reasoning", "searching", "approval", "failed", "running", "queued", "in_progress"].contains(status.lowercased())
    }

    var modelDisplayName: String {
        if model == ModelOption.ironclawMobileModelID {
            return "IronClaw Mobile"
        }
        if model == ModelOption.ironclawModelID {
            return "Hosted IronClaw"
        }
        if model == ModelOption.llmCouncilSynthesisModelID {
            return "Council Synthesis"
        }
        return model?.split(separator: "/").last.map(String.init) ?? "Assistant"
    }

    var streamingStatusText: String {
        if model == ModelOption.ironclawMobileModelID {
            switch status {
            case "reasoning":
                return "Running IronClaw Mobile"
            case "searching":
                return "Searching with NEAR Private"
            default:
                return "Running mobile agent"
            }
        }

        if model == ModelOption.ironclawModelID {
            switch status {
            case "reasoning":
                return "Running IronClaw agent"
            case "approval":
                return "Waiting for approval"
            case "searching":
                if let searchQuery, !searchQuery.isEmpty {
                    return "Searching \(searchQuery)"
                }
                return "Searching web before IronClaw"
            default:
                return "Waiting for final IronClaw output"
            }
        }

        if model == ModelOption.llmCouncilSynthesisModelID {
            return status == "searching" ? "Checking sources" : "Synthesizing council"
        }

        switch status {
        case "searching":
            if let searchQuery, !searchQuery.isEmpty {
                return "Searching \(searchQuery)"
            }
            return "Searching web"
        case "reasoning":
            return "Reasoning"
        case "approval":
            return "Needs approval"
        default:
            return "Thinking"
        }
    }
}
