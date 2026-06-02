import SwiftUI

extension HomeScreen {
    var homeRecentChatsSection: some View {
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
