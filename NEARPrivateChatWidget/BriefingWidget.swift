import SwiftUI
import WidgetKit

// MARK: - Timeline entry

struct BriefingEntry: TimelineEntry {
    let date: Date
    /// The most-recently-run briefing snapshot, or `nil` when there are none.
    let snapshot: BriefingSnapshot?
    /// Most-recent briefings (for the systemLarge list), newest first.
    let recent: [BriefingSnapshot]
    /// Total number of briefings the user has, for the systemMedium footer.
    let totalCount: Int
    /// Drives the redacted placeholder look in the gallery/loading state.
    let isPlaceholder: Bool

    static let placeholder = BriefingEntry(
        date: Date(),
        snapshot: BriefingSnapshot(
            id: "placeholder",
            title: "Daily news brief",
            summary: "Top headlines, refreshed every weekday morning.",
            lastRunAt: Date()
        ),
        recent: [
            BriefingSnapshot(id: "p1", title: "Daily news brief", summary: "Top headlines, refreshed every weekday morning.", lastRunAt: Date()),
            BriefingSnapshot(id: "p2", title: "ETH price watcher", summary: "$2,005 · −0.8%", lastRunAt: Date()),
            BriefingSnapshot(id: "p3", title: "My NEAR account", summary: "2,911.17 NEAR · $7,103", lastRunAt: Date())
        ],
        totalCount: 3,
        isPlaceholder: true
    )

    static let empty = BriefingEntry(
        date: Date(),
        snapshot: nil,
        recent: [],
        totalCount: 0,
        isPlaceholder: false
    )
}

// MARK: - Timeline provider

struct BriefingProvider: TimelineProvider {
    func placeholder(in context: Context) -> BriefingEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (BriefingEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BriefingEntry>) -> Void) {
        let entry = loadEntry()
        // The app reloads the timeline whenever it writes a fresh snapshot, so
        // this scheduled refresh is just a safety net for background runs.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> BriefingEntry {
        let snapshots = Self.readSnapshots()
        let sorted = snapshots.sorted { lhs, rhs in
            switch (lhs.lastRunAt, rhs.lastRunAt) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return false
            }
        }
        return BriefingEntry(
            date: Date(),
            snapshot: sorted.first,
            recent: Array(sorted.prefix(5)),
            totalCount: snapshots.count,
            isPlaceholder: false
        )
    }

    private static func readSnapshots() -> [BriefingSnapshot] {
        guard let url = BriefingSharedStore.sharedFileURL(BriefingSharedStore.snapshotFileName),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder.briefingSnapshot.decode([BriefingSnapshot].self, from: data) else {
            return []
        }
        return decoded
    }
}

// MARK: - Views

struct BriefingWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: BriefingEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallBody
            case .systemLarge:
                largeBody
            default:
                mediumBody
            }
        }
        .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private var smallBody: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                header
                Text(snapshot.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(snapshot.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
                Text(timeLabel(for: snapshot))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private var mediumBody: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 8) {
                header
                Text(snapshot.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(snapshot.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
                HStack {
                    Text(timeLabel(for: snapshot))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 8)
                    if entry.totalCount > 1 {
                        Text("\(entry.totalCount) briefings")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private var largeBody: some View {
        if entry.recent.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 10) {
                header
                ForEach(Array(entry.recent.prefix(4))) { snapshot in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(snapshot.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if snapshot.id != entry.recent.prefix(4).last?.id {
                        Divider().opacity(0.4)
                    }
                }
                Spacer(minLength: 0)
                if entry.totalCount > entry.recent.prefix(4).count {
                    Text("+\(entry.totalCount - entry.recent.prefix(4).count) more in Private Chat")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text("Today")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text("No briefings yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Create a briefing in Private Chat to see its latest result here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func timeLabel(for snapshot: BriefingSnapshot) -> String {
        guard let lastRunAt = snapshot.lastRunAt else { return "Not run yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: lastRunAt, relativeTo: Date()))"
    }
}

// MARK: - Widget

struct BriefingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: BriefingWidgetRefresher.kind, provider: BriefingProvider()) { entry in
            BriefingWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today Briefing")
        .description("Your latest scheduled briefing at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    BriefingWidget()
} timeline: {
    BriefingEntry.placeholder
    BriefingEntry.empty
}

#Preview("Medium", as: .systemMedium) {
    BriefingWidget()
} timeline: {
    BriefingEntry.placeholder
    BriefingEntry.empty
}

#Preview("Large", as: .systemLarge) {
    BriefingWidget()
} timeline: {
    BriefingEntry.placeholder
    BriefingEntry.empty
}
