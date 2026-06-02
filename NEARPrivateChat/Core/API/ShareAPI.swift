import Foundation

protocol ShareAPI: AnyObject {
    func fetchConversationShares(_ conversationID: String) async throws -> ConversationSharesListResponse
    func fetchSharedWithMe() async throws -> [SharedConversationInfo]
    func createPublicShare(_ conversationID: String) async throws -> [ConversationShareInfo]
    func createDirectShare(_ conversationID: String, recipients: [ShareInviteRecipient], permission: String) async throws -> [ConversationShareInfo]
    func createOrganizationShare(_ conversationID: String, emailPattern: String, permission: String) async throws -> [ConversationShareInfo]
    func createGroupShare(_ conversationID: String, groupID: String, permission: String) async throws -> [ConversationShareInfo]
    func fetchShareGroups() async throws -> [ShareGroupInfo]
    func createShareGroup(name: String, members: [ShareInviteRecipient]) async throws -> ShareGroupInfo
    func updateShareGroup(_ groupID: String, name: String, members: [ShareInviteRecipient]) async throws -> ShareGroupInfo
    func deleteShareGroup(_ groupID: String) async throws
    func deleteConversationShare(_ conversationID: String, shareID: String) async throws
}

final class PrivateChatShareAPI: ShareAPI {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchConversationShares(_ conversationID: String) async throws -> ConversationSharesListResponse {
        try await client.request(APIClient.conversationPath(conversationID, suffix: ["shares"]), method: "GET", authenticated: true)
    }

    func fetchSharedWithMe() async throws -> [SharedConversationInfo] {
        try await client.request("/v1/shared-with-me", method: "GET", authenticated: true)
    }

    func createPublicShare(_ conversationID: String) async throws -> [ConversationShareInfo] {
        let payload = CreateConversationSharePayload(permission: SharePermission.read.rawValue, target: .public)
        return try await client.request(
            APIClient.conversationPath(conversationID, suffix: ["shares"]),
            method: "POST",
            body: payload,
            authenticated: true
        )
    }

    func createDirectShare(
        _ conversationID: String,
        recipients: [ShareInviteRecipient],
        permission: String
    ) async throws -> [ConversationShareInfo] {
        let payload = CreateConversationSharePayload(
            permission: SharePermission.sanitized(permission).rawValue,
            target: .direct(recipients)
        )
        return try await client.request(
            APIClient.conversationPath(conversationID, suffix: ["shares"]),
            method: "POST",
            body: payload,
            authenticated: true
        )
    }

    func createOrganizationShare(
        _ conversationID: String,
        emailPattern: String,
        permission: String
    ) async throws -> [ConversationShareInfo] {
        let payload = CreateConversationSharePayload(
            permission: SharePermission.sanitized(permission).rawValue,
            target: .organization(emailPattern)
        )
        return try await client.request(
            APIClient.conversationPath(conversationID, suffix: ["shares"]),
            method: "POST",
            body: payload,
            authenticated: true
        )
    }

    func createGroupShare(
        _ conversationID: String,
        groupID: String,
        permission: String
    ) async throws -> [ConversationShareInfo] {
        let payload = CreateConversationSharePayload(
            permission: SharePermission.sanitized(permission).rawValue,
            target: .group(groupID)
        )
        return try await client.request(
            APIClient.conversationPath(conversationID, suffix: ["shares"]),
            method: "POST",
            body: payload,
            authenticated: true
        )
    }

    func fetchShareGroups() async throws -> [ShareGroupInfo] {
        try await client.request("/v1/share-groups", method: "GET", authenticated: true)
    }

    func createShareGroup(name: String, members: [ShareInviteRecipient]) async throws -> ShareGroupInfo {
        let payload = ShareGroupPayload(name: name, members: members)
        return try await client.request("/v1/share-groups", method: "POST", body: payload, authenticated: true)
    }

    func updateShareGroup(_ groupID: String, name: String, members: [ShareInviteRecipient]) async throws -> ShareGroupInfo {
        let payload = ShareGroupPayload(name: name, members: members)
        return try await client.request("/v1/share-groups/\(try APIClient.safePathSegment(groupID))", method: "PATCH", body: payload, authenticated: true)
    }

    func deleteShareGroup(_ groupID: String) async throws {
        let _: EmptyResponse = try await client.request(
            "/v1/share-groups/\(try APIClient.safePathSegment(groupID))",
            method: "DELETE",
            authenticated: true
        )
    }

    func deleteConversationShare(_ conversationID: String, shareID: String) async throws {
        let _: EmptyResponse = try await client.request(
            APIClient.conversationPath(conversationID, suffix: ["shares", try APIClient.safePathSegment(shareID)]),
            method: "DELETE",
            authenticated: true
        )
    }
}

private enum SharePermission: String {
    case read
    case write

    static func sanitized(_ value: String) -> SharePermission {
        value.lowercased() == SharePermission.write.rawValue ? .write : .read
    }
}

private struct CreateConversationSharePayload: Encodable {
    let permission: String
    let target: ShareTargetPayload
}

private struct ShareGroupPayload: Encodable {
    let name: String
    let members: [ShareInviteRecipient]
}

private enum ShareTargetPayload: Encodable {
    case `public`
    case direct([ShareInviteRecipient])
    case group(String)
    case organization(String)

    private enum CodingKeys: String, CodingKey {
        case mode
        case recipients
        case groupID = "group_id"
        case emailPattern = "email_pattern"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .public:
            try container.encode("public", forKey: .mode)
        case let .direct(recipients):
            try container.encode("direct", forKey: .mode)
            try container.encode(recipients, forKey: .recipients)
        case let .group(groupID):
            try container.encode("group", forKey: .mode)
            try container.encode(groupID, forKey: .groupID)
        case let .organization(emailPattern):
            try container.encode("organization", forKey: .mode)
            try container.encode(emailPattern, forKey: .emailPattern)
        }
    }
}
