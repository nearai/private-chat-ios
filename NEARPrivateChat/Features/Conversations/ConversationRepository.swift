import Foundation

struct ConversationRepository {
    private let api: ConversationAPI
    private var cache: ConversationCache?

    init(api: ConversationAPI, cache: ConversationCache? = nil) {
        self.api = api
        self.cache = cache
    }

    mutating func configure(accountID: String) {
        cache = ConversationCache(accountID: accountID)
    }

    func fetchConversations() async throws -> [ConversationSummary] {
        try await api.fetchConversations()
    }

    func createConversation(title: String) async throws -> ConversationSummary {
        try await api.createConversation(title: title)
    }

    func createConversation(title: String, metadata: [String: String]) async throws -> ConversationSummary {
        try await api.createConversation(title: title, metadata: metadata)
    }

    func updateConversationTitle(_ conversationID: String, title: String) async throws {
        try await api.updateConversationTitle(conversationID, title: title)
    }

    func deleteConversation(_ conversationID: String) async throws {
        try await api.deleteConversation(conversationID)
    }

    func cloneConversation(_ conversationID: String) async throws -> ConversationSummary {
        try await api.cloneConversation(conversationID)
    }

    func archiveConversation(_ conversationID: String) async throws {
        try await api.archiveConversation(conversationID)
    }

    func unarchiveConversation(_ conversationID: String) async throws {
        try await api.unarchiveConversation(conversationID)
    }

    func pinConversation(_ conversationID: String) async throws {
        try await api.pinConversation(conversationID)
    }

    func unpinConversation(_ conversationID: String) async throws {
        try await api.unpinConversation(conversationID)
    }

    func loadCachedConversations() -> [ConversationSummary] {
        cache?.load() ?? []
    }

    @discardableResult
    func saveCachedConversations(_ conversations: [ConversationSummary]) -> Bool {
        cache?.save(conversations) ?? true
    }
}
