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

    /// File the "Send to Private Chat" share extension writes a single pending
    /// shared item to. The app drains it on activation and stages it into the
    /// composer (never auto-sent). Lives in the App Group container so the
    /// out-of-process extension and the app can both reach it.
    static let pendingShareFileName = "pending-share.json"

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

/// A single item handed off from the share extension to the app: the selected
/// text or URL the user shared, plus when it was captured. Tiny and Codable so
/// the extension (which never links the app's full model graph) can write it
/// and the app can read it. Both targets compile this file.
struct PendingSharedItem: Codable, Equatable {
    var text: String
    var createdAt: Date

    init(text: String, createdAt: Date = Date()) {
        self.text = text
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case text, createdAt
    }

    // Forgiving decode: a file written by an older/newer build still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.text = (try? c.decode(String.self, forKey: .text)) ?? ""
        self.createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
    }
}

/// Read/write/clear helpers for the share hand-off file. The share extension
/// calls `write`; the app calls `read` then `clear` on activation. A `fileURL`
/// is injectable so unit tests don't need the real App Group container.
enum PendingShareStore {
    /// Default hand-off file location inside the App Group container.
    static func defaultFileURL() -> URL? {
        BriefingSharedStore.sharedFileURL(BriefingSharedStore.pendingShareFileName)
    }

    /// Persists a pending shared item, creating the container subfolder if
    /// needed. Returns `false` if the file could not be written.
    @discardableResult
    static func write(_ item: PendingSharedItem, to fileURL: URL?) -> Bool {
        guard let fileURL else { return false }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.briefingSnapshot.encode(item)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Loads a pending shared item, or `nil` if none is staged or it is empty.
    static func read(from fileURL: URL?) -> PendingSharedItem? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let item = try? JSONDecoder.briefingSnapshot.decode(PendingSharedItem.self, from: data)
        else { return nil }
        let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return item
    }

    /// Removes the hand-off file so the same item is never staged twice.
    static func clear(_ fileURL: URL?) {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
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
