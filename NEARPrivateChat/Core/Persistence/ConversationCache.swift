import Foundation

struct ConversationCache {
    static let legacyDefaultsKey = "cachedConversations"
    static let cacheFilename = "cached-conversations.json"

    let accountID: String
    var defaults: UserDefaults = .standard
    var fileManager: FileManager = .default

    init(accountID: String, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.accountID = accountID
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func load() -> [ConversationSummary] {
        guard let data = fileCache.data(filename: Self.cacheFilename, legacyDefaultsKey: Self.legacyDefaultsKey),
              let conversations = try? JSONDecoder().decode([ConversationSummary].self, from: data) else {
            return []
        }
        return conversations
    }

    @discardableResult
    func save(_ conversations: [ConversationSummary]) -> Bool {
        guard let data = try? JSONEncoder().encode(conversations) else { return false }
        return fileCache.write(data, filename: Self.cacheFilename, legacyDefaultsKey: Self.legacyDefaultsKey)
    }

    private var fileCache: FileCache {
        FileCache(accountID: accountID, defaults: defaults, fileManager: fileManager)
    }
}
