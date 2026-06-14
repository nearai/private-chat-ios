import Foundation

protocol ConversationAPI: AnyObject {
    func fetchConversations() async throws -> [ConversationSummary]
    func createConversation(title: String) async throws -> ConversationSummary
    func createConversation(title: String, metadata: [String: String]) async throws -> ConversationSummary
    func addItemsToConversation(_ conversationID: String, items: [ConversationImportItem]) async throws
    func updateConversationTitle(_ conversationID: String, title: String) async throws
    func fetchConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse
    func fetchReadableConversation(_ conversationID: String) async throws -> ConversationSummary
    func fetchReadableConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse
    func deleteConversation(_ conversationID: String) async throws
    func cloneConversation(_ conversationID: String) async throws -> ConversationSummary
    func archiveConversation(_ conversationID: String) async throws
    func unarchiveConversation(_ conversationID: String) async throws
    func pinConversation(_ conversationID: String) async throws
    func unpinConversation(_ conversationID: String) async throws
}

final class PrivateChatConversationAPI: ConversationAPI {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchConversations() async throws -> [ConversationSummary] {
        // `/v1/conversations` currently returns a bare JSON array, but tolerate
        // the OpenAI-style `{ "object": "list", "data": [...] }` envelope too so
        // a server-side shape change can't silently break the conversation list
        // (the same drift class that broke the reborn run-state route).
        let response: ConversationListEnvelope = try await client.request(
            "/v1/conversations",
            method: "GET",
            authenticated: true
        )
        return response.conversations
    }

    func createConversation(title: String) async throws -> ConversationSummary {
        let payload = ConversationCreatePayload(metadata: ["title": title])
        return try await client.request("/v1/conversations", method: "POST", body: payload, authenticated: true)
    }

    func createConversation(title: String, metadata: [String: String]) async throws -> ConversationSummary {
        var payloadMetadata = metadata
        payloadMetadata["title"] = title
        let payload = ConversationCreatePayload(metadata: payloadMetadata)
        return try await client.request("/v1/conversations", method: "POST", body: payload, authenticated: true)
    }

    func addItemsToConversation(_ conversationID: String, items: [ConversationImportItem]) async throws {
        let payload = ConversationItemsCreatePayload(items: items)
        let bodyData = try client.encoder.encode(payload)
        let request = try client.makeRequest(
            path: APIClient.conversationPath(conversationID, suffix: ["items"]),
            method: "POST",
            body: bodyData,
            authenticated: true
        )
        _ = try await client.performRaw(request)
    }

    func updateConversationTitle(_ conversationID: String, title: String) async throws {
        let payload = ConversationCreatePayload(metadata: ["title": title])
        let _: ConversationSummary = try await client.request(
            APIClient.conversationPath(conversationID),
            method: "POST",
            body: payload,
            authenticated: true
        )
    }

    func fetchConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse {
        try await client.request(APIClient.conversationPath(conversationID, suffix: ["items"]), method: "GET", authenticated: true)
    }

    func fetchReadableConversation(_ conversationID: String) async throws -> ConversationSummary {
        try await client.readableRequest(APIClient.conversationPath(conversationID))
    }

    func fetchReadableConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse {
        try await client.readableRequest(APIClient.conversationPath(conversationID, suffix: ["items"]))
    }

    func deleteConversation(_ conversationID: String) async throws {
        let _: EmptyResponse = try await client.request(
            APIClient.conversationPath(conversationID),
            method: "DELETE",
            authenticated: true
        )
    }

    func cloneConversation(_ conversationID: String) async throws -> ConversationSummary {
        try await client.request(
            APIClient.conversationPath(conversationID, suffix: ["clone"]),
            method: "POST",
            body: EmptyPayload(),
            authenticated: true
        )
    }

    func archiveConversation(_ conversationID: String) async throws {
        let request = try client.makeRequest(
            path: APIClient.conversationPath(conversationID, suffix: ["archive"]),
            method: "POST",
            body: nil,
            authenticated: true
        )
        _ = try await client.performRaw(request)
    }

    func unarchiveConversation(_ conversationID: String) async throws {
        let request = try client.makeRequest(
            path: APIClient.conversationPath(conversationID, suffix: ["archive"]),
            method: "DELETE",
            body: nil,
            authenticated: true
        )
        _ = try await client.performRaw(request)
    }

    func pinConversation(_ conversationID: String) async throws {
        let request = try client.makeRequest(
            path: APIClient.conversationPath(conversationID, suffix: ["pin"]),
            method: "POST",
            body: nil,
            authenticated: true
        )
        _ = try await client.performRaw(request)
    }

    func unpinConversation(_ conversationID: String) async throws {
        let request = try client.makeRequest(
            path: APIClient.conversationPath(conversationID, suffix: ["pin"]),
            method: "DELETE",
            body: nil,
            authenticated: true
        )
        _ = try await client.performRaw(request)
    }
}

/// Tolerates both the bare `[ConversationSummary]` array the conversations
/// endpoint returns today and an OpenAI-style `{ "object": "list", "data": [...] }`
/// envelope, so a server-side response-shape change can't silently break the
/// conversation list.
private struct ConversationListEnvelope: Decodable {
    let conversations: [ConversationSummary]

    private enum CodingKeys: String, CodingKey {
        case data
    }

    init(from decoder: Decoder) throws {
        if let array = try? [ConversationSummary](from: decoder) {
            conversations = array
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversations = try container.decode([ConversationSummary].self, forKey: .data)
    }
}

private struct ConversationCreatePayload: Encodable {
    let metadata: [String: String]
}

private struct ConversationItemsCreatePayload: Encodable {
    let items: [ConversationImportItem]
}
