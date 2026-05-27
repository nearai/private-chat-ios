import Foundation
import SwiftUI

struct SharedConversationSnapshot: Identifiable, Hashable {
    var conversation: ConversationSummary
    var messages: [ChatMessage]
    var source: String
    var canWrite: Bool
    var loadedAt: Date

    var id: String { conversation.id }

    var accessBadgeTitle: String {
        canWrite ? "Can edit" : "Read-only"
    }

    var accessDescription: String {
        canWrite ? "You can continue this chat in place or fork it into your own copy." : "Read-only chats cannot be edited. Copy and Continue starts your own draft."
    }

    var sourceBadgeTitle: String {
        SharedConversationPresentation.sourceBadgeTitle(for: source)
    }

    var sourceDescription: String {
        SharedConversationPresentation.sourceDescription(for: source)
    }
}

enum SharedConversationPresentation {
    static let accountShareLabel = "Shared to your NEAR account"

    static func sourceBadgeTitle(for rawSource: String) -> String {
        let source = normalizedSource(rawSource)
        if source == accountShareLabel {
            return "NEAR account"
        }
        if let host = host(from: source) {
            return host
        }
        if source.contains(" ") {
            return source
        }
        return "Conversation ID"
    }

    static func sourceDescription(for rawSource: String) -> String {
        let source = normalizedSource(rawSource)
        if source == accountShareLabel {
            return accountShareLabel
        }
        if let host = host(from: source) {
            return "Opened from \(host)"
        }
        if source.contains(" ") {
            return source
        }
        return "Opened from a conversation ID"
    }

    private static func normalizedSource(_ rawSource: String) -> String {
        let trimmed = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? accountShareLabel : trimmed
    }

    private static func host(from source: String) -> String? {
        guard let url = URL(string: source),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        return host.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
    }
}

struct ConversationShareInfo: Decodable, Identifiable, Hashable {
    let id: String
    let conversationID: String
    let permission: String
    let shareType: String
    let recipient: ShareRecipient?
    let groupID: String?
    let orgEmailPattern: String?
    let publicToken: String?
    let createdAt: String?
    let updatedAt: String?

    var isPublic: Bool { shareType == "public" }

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case permission
        case shareType = "share_type"
        case recipient
        case groupID = "group_id"
        case orgEmailPattern = "org_email_pattern"
        case publicToken = "public_token"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ShareRecipient: Decodable, Hashable {
    let kind: String
    let value: String
}

struct ShareInviteRecipient: Codable, Hashable {
    let kind: String
    let value: String
}

struct ShareGroupInfo: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let members: [ShareInviteRecipient]
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case members
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ConversationSharesListResponse: Decodable, Hashable {
    let isOwner: Bool
    let canShare: Bool
    let canWrite: Bool
    let shares: [ConversationShareInfo]
    let owner: ShareOwner?

    var publicShare: ConversationShareInfo? {
        shares.first(where: \.isPublic)
    }

    enum CodingKeys: String, CodingKey {
        case isOwner = "is_owner"
        case canShare = "can_share"
        case canWrite = "can_write"
        case shares
        case owner
    }
}

struct SharedConversationInfo: Decodable, Identifiable, Hashable {
    var id: String { conversationID }

    let conversationID: String
    let permission: String
    let title: String?
    let createdAt: TimeInterval?
    let error: String?

    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed! : "Shared conversation"
    }

    var canWrite: Bool {
        permission == "write"
    }

    var accessBadgeTitle: String {
        canWrite ? "Can edit" : "Read-only"
    }

    var sourceLabel: String {
        SharedConversationPresentation.accountShareLabel
    }

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case permission
        case title
        case createdAt = "created_at"
        case error
    }
}

struct ShareOwner: Decodable, Hashable {
    let userID: String
    let name: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case name
    }
}
