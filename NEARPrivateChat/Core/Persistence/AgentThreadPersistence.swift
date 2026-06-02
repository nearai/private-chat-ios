import Foundation

struct AgentThreadPersistence {
    static let legacyDefaultsKey = "ironclawConversationThreadIDs"
    static let cacheFilename = "ironclaw-thread-ids.json"
    private static let mappingMigrationDefaultsKey = "ironclawThreadMappingMigrationV1"

    let accountID: String
    var defaults: UserDefaults = .standard
    var fileManager: FileManager = .default

    init(accountID: String, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.accountID = accountID
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func ensureMappingMigrationFlagSet() {
        guard !defaults.bool(forKey: Self.mappingMigrationDefaultsKey) else { return }
        defaults.set(true, forKey: Self.mappingMigrationDefaultsKey)
    }

    func loadThreadID(for conversationID: String) -> String? {
        let trimmed = loadCache()[conversationID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func loadCache() -> [String: String] {
        guard let data = fileCache.data(filename: Self.cacheFilename, legacyDefaultsKey: Self.legacyDefaultsKey),
              let cache = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return cache
    }

    @discardableResult
    func saveCache(_ cache: [String: String]) -> Bool {
        guard let data = try? JSONEncoder().encode(cache) else { return false }
        return fileCache.write(data, filename: Self.cacheFilename, legacyDefaultsKey: Self.legacyDefaultsKey)
    }

    @discardableResult
    func rememberThreadID(_ threadID: String, for conversationID: String) -> Bool {
        let trimmed = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var cache = loadCache()
        cache[conversationID] = trimmed
        return saveCache(cache)
    }

    @discardableResult
    func removeThreadID(for conversationID: String) -> Bool {
        var cache = loadCache()
        cache.removeValue(forKey: conversationID)
        return saveCache(cache)
    }

    private var fileCache: FileCache {
        FileCache(accountID: accountID, defaults: defaults, fileManager: fileManager)
    }
}
