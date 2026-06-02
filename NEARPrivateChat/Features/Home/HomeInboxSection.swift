import SwiftUI

struct HomeInboxSectionPlan: Equatable {
    let selectedFilter: HomeFilter
    let searchQuery: String
    let activeConversationCount: Int
    let activeProjectCount: Int
    let projectContextMatchCount: Int
    let sharedWithMeCount: Int
    let archivedConversationCount: Int
    let archivedProjectCount: Int

    init(
        selectedFilter: HomeFilter,
        searchQuery: String,
        activeConversationCount: Int,
        activeProjectCount: Int,
        projectContextMatchCount: Int,
        sharedWithMeCount: Int,
        archivedConversationCount: Int,
        archivedProjectCount: Int
    ) {
        self.selectedFilter = selectedFilter
        self.searchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activeConversationCount = activeConversationCount
        self.activeProjectCount = activeProjectCount
        self.projectContextMatchCount = projectContextMatchCount
        self.sharedWithMeCount = sharedWithMeCount
        self.archivedConversationCount = archivedConversationCount
        self.archivedProjectCount = archivedProjectCount
    }

    var isSearching: Bool {
        !searchQuery.isEmpty
    }

    var filterCounts: [HomeFilter: Int] {
        [
            .all: activeConversationCount + activeProjectCount + projectContextMatchCount,
            .shared: sharedWithMeCount,
            .archived: archivedConversationCount + archivedProjectCount
        ]
    }

    var showsActiveInbox: Bool {
        selectedFilter == .all
    }

    var showsProjectContext: Bool {
        showsActiveInbox && projectContextMatchCount > 0
    }

    var showsProjects: Bool {
        showsActiveInbox && activeProjectCount > 0
    }

    var showsConversations: Bool {
        showsActiveInbox && activeConversationCount > 0
    }

    var showsWorkboard: Bool {
        showsActiveInbox && !isSearching
    }

    var showsSharedWithMe: Bool {
        selectedFilter == .shared && sharedWithMeCount > 0
    }

    var showsArchivedProjects: Bool {
        selectedFilter == .archived && archivedProjectCount > 0
    }

    var showsArchivedConversations: Bool {
        selectedFilter == .archived && archivedConversationCount > 0
    }

    var hasActiveContent: Bool {
        activeConversationCount > 0 || activeProjectCount > 0 || projectContextMatchCount > 0
    }

    var showsActiveSetupEmptyState: Bool {
        showsActiveInbox && activeConversationCount == 0
    }

    var showsActiveSearchEmptyState: Bool {
        showsActiveInbox && isSearching && !hasActiveContent
    }

    var showsSharedEmptyState: Bool {
        selectedFilter == .shared && sharedWithMeCount == 0
    }

    var showsArchivedEmptyState: Bool {
        selectedFilter == .archived && archivedConversationCount == 0 && archivedProjectCount == 0
    }
}

struct HomeInboxEmptyState: View {
    let title: String
    let subtitle: String
    let symbolName: String
    var isLoading = false
    var actionTitle: String? = nil
    var actionSymbolName: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if isLoading {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: symbolName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionSymbolName ?? "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primaryAction)
                .background(Color.secondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}

struct HomeFilterStrip: View {
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
                    Text(selectedFilter == .all ? "Today" : "\(selectedFilter.title) items")
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

struct HomeRecentsRow: View {
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

struct HomeRecentCard: View {
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

