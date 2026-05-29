import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Identifiers and storage locations shared by the app and the home-screen
/// widget. Both targets compile this file, so the App Group plumbing lives in
/// exactly one place.
enum BriefingSharedStore {
    /// App Group both the app and the widget extension are entitled to. Must
    /// match the `com.apple.security.application-groups` entry in both
    /// `.entitlements` files.
    static let appGroupIdentifier = "group.ai.near.privatechat"

    /// Folder inside the shared App Group container that holds briefing files.
    static let directoryName = "NEARPrivateChat"

    /// Canonical briefings file the app persists `[Briefing]` to.
    static let briefingsFileName = "briefings.json"

    /// Flattened, widget-ready snapshot the app writes alongside `briefings.json`.
    /// Decoupled from the app's full `Briefing`/`MessageWidget` graph so the
    /// widget never has to compile any SwiftUI view code or design tokens.
    static let snapshotFileName = "briefing-widget-snapshot.json"

    /// Shared App Group container, or `nil` if the entitlement is missing (e.g.
    /// a stripped build). Callers fall back to a local directory.
    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// `<AppGroup>/NEARPrivateChat/<file>` when the group is available.
    static func sharedFileURL(_ fileName: String) -> URL? {
        containerURL()?
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

/// A single briefing reduced to what the widget renders: a title, a short
/// one-line summary, and when it last ran. The app produces these from its rich
/// `Briefing`/`MessageWidget` values; the widget only ever decodes this.
struct BriefingSnapshot: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var summary: String
    var lastRunAt: Date?

    init(id: String, title: String, summary: String, lastRunAt: Date?) {
        self.id = id
        self.title = title
        self.summary = summary
        self.lastRunAt = lastRunAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, summary, lastRunAt
    }

    // Forgiving decode so a snapshot file written by an older/newer build still
    // loads rather than blanking the widget.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString,
            title: (try? c.decode(String.self, forKey: .title)) ?? "Briefing",
            summary: (try? c.decode(String.self, forKey: .summary)) ?? "",
            lastRunAt: try? c.decode(Date.self, forKey: .lastRunAt)
        )
    }
}

extension BriefingSnapshot {
    /// The snapshot the widget shows: the most recently run briefing, else the
    /// first available. `nil` when there are none (widget shows a placeholder).
    static func mostRecent(in snapshots: [BriefingSnapshot]) -> BriefingSnapshot? {
        snapshots.sorted { lhs, rhs in
            switch (lhs.lastRunAt, rhs.lastRunAt) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return false
            }
        }.first
    }
}

/// Nudges WidgetKit to rebuild the widget's timeline after the app writes a new
/// snapshot. No-op on platforms without WidgetKit.
enum BriefingWidgetRefresher {
    static let kind = "BriefingWidget"

    static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        #endif
    }
}

extension JSONEncoder {
    static var briefingSnapshot: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var briefingSnapshot: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
