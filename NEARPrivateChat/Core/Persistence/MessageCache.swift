import Foundation

struct MessageCache {
    static let legacyDefaultsKey = "localConversationMessages"
    static let cacheFilename = "local-conversation-messages.json"

    let accountID: String
    var defaults: UserDefaults = .standard
    var fileManager: FileManager = .default

    init(accountID: String, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.accountID = accountID
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func loadCache() -> [String: [ChatMessage]] {
        guard let data = fileCache.data(filename: Self.cacheFilename, legacyDefaultsKey: Self.legacyDefaultsKey),
              let cache = try? JSONDecoder().decode([String: [ChatMessage]].self, from: data) else {
            return [:]
        }
        return cache
    }

    func loadMessages(for conversationID: String) -> [ChatMessage]? {
        loadCache()[conversationID]
    }

    @discardableResult
    func save(_ messages: [ChatMessage], for conversationID: String) -> Bool {
        var cache = loadCache()
        cache[conversationID] = messages
        return saveCache(cache)
    }

    @discardableResult
    func removeMessages(for conversationID: String) -> Bool {
        var cache = loadCache()
        cache.removeValue(forKey: conversationID)
        return saveCache(cache)
    }

    @discardableResult
    private func saveCache(_ cache: [String: [ChatMessage]]) -> Bool {
        guard let data = try? JSONEncoder().encode(cache) else { return false }
        return fileCache.write(data, filename: Self.cacheFilename, legacyDefaultsKey: Self.legacyDefaultsKey)
    }

    private var fileCache: FileCache {
        FileCache(accountID: accountID, defaults: defaults, fileManager: fileManager)
    }
}
