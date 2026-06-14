import SwiftUI

struct TodaySection: View {
    @ObservedObject var store: BriefingStore
    var onOpenBriefing: (Briefing) -> Void
    var onNewBriefing: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if store.briefings.isEmpty {
            Text("Turn any source, note, or chat into a recurring check. Results land here and open back into chat.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SuggestedBriefingsView(store: store, onOpen: onOpenBriefing)
            } else {
                let liveBriefings = store.briefings.filter { $0.latestResult != nil }
                if !liveBriefings.isEmpty {
                    labeledSection("Live", count: "\(liveBriefings.count) active")
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(liveBriefings) { briefing in
                            BriefingTile(briefing: briefing) {
                                onOpenBriefing(briefing)
                            }
                        }
                    }
                }

                labeledSection("Scheduled", count: "\(store.briefings.count) upcoming")
                    .padding(.top, liveBriefings.isEmpty ? 0 : 2)
                VStack(spacing: 0) {
                    ForEach(store.briefings) { briefing in
                        ScheduleRow(briefing: briefing) {
                            onOpenBriefing(briefing)
                        }
                        .contextMenu {
                            Button { store.setPinned(briefing, !briefing.isPinned) } label: {
                                Label(briefing.isPinned ? "Unpin" : "Pin to top", systemImage: briefing.isPinned ? "pin.slash" : "pin")
                            }
                            Button { store.setPaused(briefing, !briefing.isPaused) } label: {
                                Label(briefing.isPaused ? "Unmute" : "Mute", systemImage: briefing.isPaused ? "bell" : "bell.slash")
                            }
                            if briefing.snoozedUntil != nil {
                                Button { store.unsnooze(briefing) } label: { Label("End snooze", systemImage: "moon") }
                            } else {
                                Button { store.snooze(briefing, days: 1) } label: { Label("Snooze 1 day", systemImage: "moon.zzz") }
                            }
                            Divider()
                            Button(role: .destructive) { store.remove(briefing) } label: { Label("Delete", systemImage: "trash") }
                        }
                        if briefing.id != store.briefings.last?.id {
                            Divider()
                                .overlay(Color.appHairline)
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }

                SuggestedBriefingsView(store: store, onOpen: onOpenBriefing)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today")
                    .font(.title2.weight(.bold))
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 12)
            Button(action: onNewBriefing) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appPanelBackground)
                    .frame(width: 32, height: 32)
                    .background(Color.actionPrimary, in: Circle())
            }
            .buttonStyle(.plain)
            .minimumTouchTarget()
            .accessibilityLabel("New workflow")
        }
    }

    private func labeledSection(_ title: String, count: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.textSecondary)
            Spacer(minLength: 8)
            if let count {
                Text(count)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}

/// Standalone "Today" dashboard surface — `TodaySection` wrapped for full-screen
/// presentation from the home top bar.
struct DashboardScreen: View {
    @ObservedObject var store: BriefingStore
    var onOpenBriefing: (Briefing) -> Void
    var onNewBriefing: () -> Void
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                TodaySection(
                    store: store,
                    onOpenBriefing: onOpenBriefing,
                    onNewBriefing: onNewBriefing
                )
            }
            .background(Color.appBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
    }
}
