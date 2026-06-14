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
        if homeInboxSectionPlan.showsWorkboard,
           !shouldPrioritizeSetupOverToday,
           homeOrchestrationPlan.hasContent {
            HomeOrchestrationSurface(
                plan: homeOrchestrationPlan,
                onAction: runHomeOrchestrationAction
            )
        }
    }

    @ViewBuilder
    var homeDefaultStarterSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Streams")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .accessibilityIdentifier("home.streams.title")

                    Text(homeStreamsSubtitleText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("home.streams.subtitle")
                }

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.actionPrimary)
                        .frame(width: 5, height: 5)
                    Text(homeLiveCountText)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.actionPrimary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Color.actionFill.opacity(0.9), in: RoundedRectangle.app(AppRadius.pill))
                .overlay {
                    RoundedRectangle.app(AppRadius.pill)
                        .stroke(Color.actionPrimary.opacity(0.18), lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(homeLiveCountText)
                .accessibilityIdentifier("home.streams.liveCount")
            }
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)

            homeTodayFeedSection
        }
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.default.streams")
    }

    private var homeLiveCountText: String {
        HomeStreamsCopy.liveCountText(for: homeFeedScopeCounts)
    }

    private var homeStreamsSubtitleText: String {
        HomeStreamsCopy.subtitle(for: homeFeedScopeCounts)
    }

    @ViewBuilder
    var homeLibraryShortcuts: some View {
        if homeInboxSectionPlan.showsLibraryShortcuts {
            HStack(spacing: 8) {
                if homeInboxSectionPlan.showsSharedLibraryShortcut {
                    homeLibraryShortcut(
                        title: "Shared",
                        count: filteredSharedWithMe.count,
                        symbolName: "person.2",
                        filter: .shared
                    )
                }

                if homeInboxSectionPlan.showsArchivedLibraryShortcut {
                    homeLibraryShortcut(
                        title: "Archive",
                        count: homeInboxSectionPlan.archivedItemCount,
                        symbolName: "archivebox",
                        filter: .archived
                    )
                }
            }
            .padding(.horizontal, 16)
        }
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
