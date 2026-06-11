import SwiftUI

extension HomeScreen {
    var homeFilterControls: some View {
        HomeFilterStrip(
            selectedFilter: $homeStore.selectedHomeFilter,
            counts: filterCounts,
            onSelect: selectHomeFilter
        )
        .padding(.horizontal, 16)
        .padding(.top, searchQuery.isEmpty ? 0 : 12)
    }

    @ViewBuilder
    var homeWorkboardSurface: some View {
        if homeInboxSectionPlan.showsWorkboard, !shouldPrioritizeSetupOverToday {
            HomeOrchestrationSurface(
                plan: homeOrchestrationPlan,
                onAction: runHomeOrchestrationAction
            )
        }
    }

    var homeLibraryShortcuts: some View {
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

    func homeLibraryShortcut(title: String, count: Int, symbolName: String, filter: HomeFilter) -> some View {
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
            .frame(minHeight: 44)
            .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.pill))
            .overlay {
                RoundedRectangle.app(AppRadius.pill)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) items")
    }


}
