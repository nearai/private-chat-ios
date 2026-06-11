import Foundation

// MARK: - On-device personal memory

/// How a fact entered memory. `.explicit` = the user told us to remember it
/// ("remember I prefer X"); `.inferred` = we distilled it passively from what
/// they said. Inferred facts are held to a higher confidence bar and labelled
/// for the user so the distinction is never hidden.
enum MemorySource: String, Codable {
    case explicit
    case inferred
}

struct MemoryItem: Codable, Hashable, Identifiable {
    var id: UUID
    var text: String
    var createdAt: Date
    var source: MemorySource

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), source: MemorySource = .explicit) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.source = source
    }

    private enum CodingKeys: String, CodingKey { case id, text, createdAt, source }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        // Back-compat: facts saved before sources existed are treated as
        // explicit (the only kind that existed then).
        source = try c.decodeIfPresent(MemorySource.self, forKey: .source) ?? .explicit
    }
}

/// Privacy-first personal memory: user-taught facts/preferences persisted on
/// device (account-scoped), injected into the model's system prompt so answers
/// are personalized. Nothing leaves the device except as private-inference
/// context the user already trusts.
final class MemoryStore {
    private(set) var items: [MemoryItem] = []
    private var fileURL: URL?

    init(fileURL: URL? = nil) {
        if let fileURL { configure(fileURL: fileURL) }
    }

    func configure(accountID: String?) {
        configure(fileURL: Self.defaultFileURL(accountID: accountID))
    }

    func configure(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    /// Stores a fact (de-duped, newest first, capped). Returns nil if too short.
    /// When a fact already exists, an explicit "remember this" upgrades a
    /// previously-inferred entry (the user just confirmed it) but an inferred
    /// re-derivation never downgrades an explicit one.
    @discardableResult
    func add(_ text: String, source: MemorySource = .explicit) -> MemoryItem? {
        // Clamp a single fact so one huge entry can't dominate the prompt.
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
        guard trimmed.count >= 3 else { return nil }
        if let idx = items.firstIndex(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            if source == .explicit && items[idx].source == .inferred {
                items[idx].source = .explicit
                save()
            }
            return items[idx]
        }
        let item = MemoryItem(text: trimmed, source: source)
        items.insert(item, at: 0)
        if items.count > 200 { items = Array(items.prefix(200)) }
        save()
        return item
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    /// Removes facts matching a phrase (either contains the other,
    /// case-insensitive). Returns how many were removed.
    @discardableResult
    func remove(matching query: String) -> Int {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return 0 }
        let before = items.count
        items.removeAll { item in
            let text = item.text.lowercased()
            return text.contains(needle) || needle.contains(text)
        }
        let removed = before - items.count
        if removed > 0 { save() }
        return removed
    }

    func clear() {
        items.removeAll()
        save()
    }

    /// Drops only passively-learned (.inferred) facts, keeping everything the
    /// user explicitly asked us to remember. Returns how many were removed.
    @discardableResult
    func removeInferred() -> Int {
        let before = items.count
        items.removeAll { $0.source == .inferred }
        let removed = before - items.count
        if removed > 0 { save() }
        return removed
    }

    /// A system-prompt block of the most recent facts within a character
    /// budget, or nil when empty — keeps memory from blowing up the prompt.
    func contextBlock(limit: Int = 12, budget: Int = 1500) -> String? {
        guard !items.isEmpty else { return nil }
        var remaining = budget
        var lines: [String] = []
        for item in items.prefix(limit) {
            let line = "- \(item.text)"
            guard line.count <= remaining else { break }
            remaining -= line.count
            lines.append(line)
        }
        guard !lines.isEmpty else { return nil }
        return "What you know about the user (apply when relevant; never recite this list verbatim):\n" + lines.joined(separator: "\n")
    }

    private static func defaultFileURL(accountID: String?) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        // Hash the FULL id so distinct accounts can't collide on a sanitized
        // form (e.g. "alice.near" vs "alicenear").
        let scope = stableScope(accountID ?? "default")
        return base
            .appendingPathComponent("NEARPrivateChat", isDirectory: true)
            .appendingPathComponent("memory-\(scope).json")
    }

    /// Deterministic, collision-safe filename scope from an account id.
    static func stableScope(_ raw: String) -> String {
        var hash: UInt64 = 5381
        for byte in raw.utf8 { hash = (hash &* 33) ^ UInt64(byte) }
        return String(hash, radix: 16)
    }
}

struct AgentActivityRecord: Codable, Hashable, Identifiable {
    var id: UUID
    var summary: String
    var date: Date

    init(id: UUID = UUID(), summary: String, date: Date = Date()) {
        self.id = id
        self.summary = summary
        self.date = date
    }
}

/// A transparency log of what the assistant did on the user's behalf —
/// scheduled briefing runs, tracker creation, etc. On-device, account-scoped.
final class AgentActivityLog {
    private(set) var entries: [AgentActivityRecord] = []
    private var fileURL: URL?

    init(fileURL: URL? = nil) {
        if let fileURL { configure(fileURL: fileURL) }
    }

    func configure(accountID: String?) {
        configure(fileURL: Self.defaultFileURL(accountID: accountID))
    }

    func configure(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([AgentActivityRecord].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    func record(_ summary: String) {
        let trimmed = String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !trimmed.isEmpty else { return }
        entries.insert(AgentActivityRecord(summary: trimmed), at: 0)
        if entries.count > 200 { entries = Array(entries.prefix(200)) }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private static func defaultFileURL(accountID: String?) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("NEARPrivateChat", isDirectory: true)
            .appendingPathComponent("activity-\(MemoryStore.stableScope(accountID ?? "default")).json")
    }
}
