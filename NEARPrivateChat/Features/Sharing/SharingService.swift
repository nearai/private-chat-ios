import Foundation

enum SharingServiceError: LocalizedError, Equatable {
    case invalidConversationLink
    case invalidPermission
    case emptyRecipients
    case emptyGroupName
    case emptyGroupMembers
    case invalidOrganizationPattern
    case emptyGroupSelection
    case publicLinkAlreadyDisabled

    var errorDescription: String? {
        switch self {
        case .invalidConversationLink:
            return "Paste a private.near.ai conversation link or conversation ID."
        case .invalidPermission:
            return "Choose read or write access."
        case .emptyRecipients:
            return "Use valid email addresses or NEAR accounts."
        case .emptyGroupName:
            return "Name the group first."
        case .emptyGroupMembers:
            return "Add at least one group member."
        case .invalidOrganizationPattern:
            return "Use an organization pattern like *@near.org."
        case .emptyGroupSelection:
            return "Choose a share group."
        case .publicLinkAlreadyDisabled:
            return "Public link is already disabled."
        }
    }
}

final class SharingService {
    private let shareAPI: ShareAPI
    private let conversationAPI: ConversationAPI

    init(shareAPI: ShareAPI, conversationAPI: ConversationAPI) {
        self.shareAPI = shareAPI
        self.conversationAPI = conversationAPI
    }

    func loadShares(for conversationID: String) async throws -> ConversationSharesListResponse {
        try await shareAPI.fetchConversationShares(conversationID)
    }

    func refreshSharedWithMe() async throws -> [SharedConversationInfo] {
        try await shareAPI.fetchSharedWithMe()
            .sorted { lhs, rhs in
                (lhs.createdAt ?? 0) > (rhs.createdAt ?? 0)
            }
    }

    func enablePublicShare(for conversationID: String) async throws {
        _ = try await shareAPI.createPublicShare(conversationID)
    }

    func grantDirectShare(conversationID: String, rawRecipients: String, permission: String) async throws -> Int {
        let permission = try Self.validSharePermission(permission)
        let recipients = Self.shareInviteRecipients(from: rawRecipients)
        guard !recipients.isEmpty else { throw SharingServiceError.emptyRecipients }
        _ = try await shareAPI.createDirectShare(conversationID, recipients: recipients, permission: permission)
        return recipients.count
    }

    func grantOrganizationShare(conversationID: String, emailPattern: String, permission: String) async throws {
        let permission = try Self.validSharePermission(permission)
        guard let normalizedPattern = Self.normalizedOrganizationEmailPattern(emailPattern) else {
            throw SharingServiceError.invalidOrganizationPattern
        }
        _ = try await shareAPI.createOrganizationShare(
            conversationID,
            emailPattern: normalizedPattern,
            permission: permission
        )
    }

    func refreshShareGroups() async throws -> [ShareGroupInfo] {
        try await shareAPI.fetchShareGroups()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func createShareGroup(name: String, rawMembers: String) async throws -> ShareGroupInfo {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let members = Self.shareInviteRecipients(from: rawMembers)
        guard !trimmedName.isEmpty else { throw SharingServiceError.emptyGroupName }
        guard !members.isEmpty else { throw SharingServiceError.emptyGroupMembers }
        return try await shareAPI.createShareGroup(name: trimmedName, members: members)
    }

    func updateShareGroup(_ groupID: String, name: String, rawMembers: String) async throws -> ShareGroupInfo {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let members = Self.shareInviteRecipients(from: rawMembers)
        guard !trimmedName.isEmpty else { throw SharingServiceError.emptyGroupName }
        guard !members.isEmpty else { throw SharingServiceError.emptyGroupMembers }
        return try await shareAPI.updateShareGroup(groupID, name: trimmedName, members: members)
    }

    func deleteShareGroup(_ groupID: String) async throws {
        try await shareAPI.deleteShareGroup(groupID)
    }

    func grantGroupShare(conversationID: String, groupID: String, permission: String) async throws {
        let permission = try Self.validSharePermission(permission)
        let trimmedGroupID = groupID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGroupID.isEmpty else { throw SharingServiceError.emptyGroupSelection }
        _ = try await shareAPI.createGroupShare(conversationID, groupID: trimmedGroupID, permission: permission)
    }

    func removeConversationShare(conversationID: String, shareID: String) async throws {
        try await shareAPI.deleteConversationShare(conversationID, shareID: shareID)
    }

    func disablePublicShare(
        conversationID: String,
        currentShareInfo: ConversationSharesListResponse?
    ) async throws {
        let loadedInfo: ConversationSharesListResponse
        if let currentShareInfo {
            loadedInfo = currentShareInfo
        } else {
            loadedInfo = try await shareAPI.fetchConversationShares(conversationID)
        }
        guard let publicShare = loadedInfo.publicShare else {
            throw SharingServiceError.publicLinkAlreadyDisabled
        }
        try await shareAPI.deleteConversationShare(conversationID, shareID: publicShare.id)
    }

    func openSharedConversation(
        from value: String,
        knownCanWrite: Bool?,
        sourceLabel: String?
    ) async throws -> SharedConversationSnapshot {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let conversationID = Self.conversationID(from: trimmed) else {
            throw SharingServiceError.invalidConversationLink
        }

        async let conversation = conversationAPI.fetchReadableConversation(conversationID)
        async let items = conversationAPI.fetchReadableConversationItems(conversationID)
        let canWrite: Bool
        if let knownCanWrite {
            canWrite = knownCanWrite
        } else if let access = try? await shareAPI.fetchConversationShares(conversationID) {
            canWrite = access.canWrite
        } else {
            canWrite = false
        }

        return try await SharedConversationSnapshot(
            conversation: conversation,
            messages: Self.chatMessages(from: items.data),
            source: sourceLabel ?? trimmed,
            canWrite: canWrite,
            loadedAt: Date()
        )
    }

    static func publicURL(for conversationID: String) -> URL? {
        URL(string: "https://private.near.ai/c/\(conversationID)")
    }

    static func conversationID(from value: String) -> String? {
        guard !value.isEmpty else { return nil }
        if isSafeRawConversationID(value) {
            return value
        }

        let normalized = value.hasPrefix("http") ? value : "https://\(value)"
        guard let url = URL(string: normalized),
              isAllowedSharedConversationURL(url) else { return nil }
        let pathParts = url.pathComponents.filter { $0 != "/" }
        guard pathParts.allSatisfy({ $0 == "c" || isSafeRawConversationID($0) }) else {
            return nil
        }

        if let index = pathParts.firstIndex(of: "c"),
           pathParts.count == index + 2,
           isSafeRawConversationID(pathParts[index + 1]) {
            return pathParts[index + 1]
        }

        if let last = pathParts.last, isSafeRawConversationID(last) {
            return last
        }

        return nil
    }

    static func shareInviteRecipients(from value: String) -> [ShareInviteRecipient] {
        var seen = Set<String>()
        return value
            .split { character in
                character == "," || character == ";" || character == "\n" || character == "\t"
            }
            .compactMap { rawValue -> ShareInviteRecipient? in
                let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let normalized = trimmed.lowercased()
                guard seen.insert(normalized).inserted else { return nil }
                if isValidEmailAddress(trimmed) {
                    return ShareInviteRecipient(kind: "email", value: normalized)
                }
                if isValidNEARAccountID(trimmed) {
                    return ShareInviteRecipient(kind: "near_account", value: normalized)
                }
                return nil
            }
    }

    static func normalizedOrganizationEmailPattern(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let domain = trimmed.hasPrefix("*@") ? String(trimmed.dropFirst(2)) : trimmed
        guard isValidEmailDomain(domain) else { return nil }
        return "*@\(domain)"
    }

    private static func validSharePermission(_ permission: String) throws -> String {
        let normalized = permission.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["read", "write"].contains(normalized) else {
            throw SharingServiceError.invalidPermission
        }
        return normalized
    }

    private static func isAllowedSharedConversationURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "private.near.ai"
    }

    private static func isSafeRawConversationID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == value,
              trimmed.count >= 6,
              !trimmed.contains("/"),
              !trimmed.contains(":"),
              !trimmed.contains(".") else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isValidEmailAddress(_ value: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,63}$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isValidEmailDomain(_ value: String) -> Bool {
        guard value.count <= 253, value.contains(".") else { return false }
        let pattern = #"^[A-Z0-9](?:[A-Z0-9\-]{0,61}[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9\-]{0,61}[A-Z0-9])?)+$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isValidNEARAccountID(_ value: String) -> Bool {
        let normalized = value.lowercased()
        guard normalized == value.lowercased(),
              normalized.count >= 2,
              normalized.count <= 64,
              !normalized.contains("@"),
              !normalized.hasPrefix("."),
              !normalized.hasSuffix(".") else {
            return false
        }
        let pattern = #"^[a-z0-9]+(?:[._\-][a-z0-9]+)*$"#
        return normalized.range(of: pattern, options: .regularExpression) != nil
    }

    private static func chatMessages(from items: [ConversationItem]) -> [ChatMessage] {
        let sourcesByResponseID = Dictionary(
            grouping: items.filter { $0.type == "web_search_call" },
            by: \.responseID
        ).mapValues { searchItems in
            uniqueSources(searchItems.flatMap { $0.action?.sources ?? [] })
        }
        let queryByResponseID = Dictionary(
            grouping: items.filter { $0.type == "web_search_call" },
            by: \.responseID
        ).mapValues { searchItems in
            searchItems.compactMap { $0.action?.query }.first
        }
        let messageItems = items
            .filter { $0.type == "message" && ($0.role == .user || $0.role == .assistant) }
            .sorted { ($0.createdAt ?? 0) < ($1.createdAt ?? 0) }
        let branchVariants = branchVariantMetadata(from: messageItems)
        return activeConversationPathItems(from: messageItems).map { item in
            ChatMessage(
                id: item.id,
                role: item.role ?? .assistant,
                text: item.displayText,
                model: item.model,
                createdAt: Date(timeIntervalSince1970: item.createdAt ?? Date().timeIntervalSince1970),
                status: item.status ?? "completed",
                responseID: item.responseID,
                previousResponseID: item.previousResponseID,
                isStreaming: false,
                searchQuery: item.role == .assistant ? queryByResponseID[item.responseID] ?? nil : nil,
                sources: item.role == .assistant ? sourcesByResponseID[item.responseID] ?? [] : [],
                attachments: item.role == .user ? attachments(from: item.content ?? []) : [],
                branchVariant: item.role == .assistant ? branchVariants[item.responseID] : nil,
                metadata: item.metadata
            )
        }
    }

    private static func activeConversationPathItems(from items: [ConversationItem]) -> [ConversationItem] {
        guard items.contains(where: { $0.previousResponseID?.isEmpty == false }) else {
            return items
        }
        let responseIDs = Set(items.map(\.responseID))
        let groupedByResponseID = Dictionary(grouping: items, by: \.responseID)
        let responseCreatedAt = groupedByResponseID.mapValues { groupedItems in
            groupedItems.compactMap(\.createdAt).min() ?? 0
        }
        let parentByResponseID = groupedByResponseID.mapValues { groupedItems in
            groupedItems.compactMap(\.previousResponseID).first
        }
        let rootIDs = responseIDs.filter { responseID in
            guard let parent = parentByResponseID[responseID] ?? nil,
                  !parent.isEmpty else {
                return true
            }
            return !responseIDs.contains(parent)
        }
        var childrenByParent: [String: [String]] = [:]
        for responseID in responseIDs {
            guard let parent = parentByResponseID[responseID] ?? nil,
                  !parent.isEmpty else {
                continue
            }
            childrenByParent[parent, default: []].append(responseID)
        }
        guard let rootID = sortedResponseIDs(rootIDs, createdAt: responseCreatedAt).last else {
            return items
        }
        var activeIDs: [String] = []
        var cursorID = rootID
        var seen = Set<String>()
        while !seen.contains(cursorID) {
            seen.insert(cursorID)
            activeIDs.append(cursorID)
            guard let children = childrenByParent[cursorID], !children.isEmpty else {
                break
            }
            cursorID = sortedResponseIDs(children, createdAt: responseCreatedAt).last ?? children[0]
        }
        let activeIDSet = Set(activeIDs)
        let activeItems = items.filter { activeIDSet.contains($0.responseID) }
        return activeItems.isEmpty ? items : activeItems
    }

    private static func branchVariantMetadata(from items: [ConversationItem]) -> [String: MessageBranchVariant] {
        let responseIDs = Set(items.map(\.responseID).filter { !$0.isEmpty })
        guard responseIDs.count > 1 else { return [:] }
        let groupedByResponseID = Dictionary(grouping: items, by: \.responseID)
        let responseCreatedAt = groupedByResponseID.mapValues { groupedItems in
            groupedItems.compactMap(\.createdAt).min() ?? 0
        }
        let parentByResponseID = groupedByResponseID.mapValues { groupedItems in
            groupedItems.compactMap(\.previousResponseID).first
        }
        let rootParentKey = "__near_private_chat_root__"
        var childrenByParent: [String: [String]] = [:]
        for responseID in responseIDs {
            let parent = parentByResponseID[responseID] ?? nil
            let parentKey = parent?.isEmpty == false ? parent! : rootParentKey
            childrenByParent[parentKey, default: []].append(responseID)
        }
        var variants: [String: MessageBranchVariant] = [:]
        for (parentKey, siblings) in childrenByParent where siblings.count > 1 {
            let sortedSiblings = sortedResponseIDs(siblings, createdAt: responseCreatedAt)
            for responseID in sortedSiblings {
                variants[responseID] = MessageBranchVariant(
                    responseIDs: sortedSiblings,
                    currentResponseID: responseID,
                    parentResponseID: parentKey == rootParentKey ? nil : parentKey
                )
            }
        }
        return variants
    }

    private static func sortedResponseIDs(_ responseIDs: some Collection<String>, createdAt: [String: TimeInterval]) -> [String] {
        responseIDs.sorted { lhs, rhs in
            let lhsDate = createdAt[lhs] ?? 0
            let rhsDate = createdAt[rhs] ?? 0
            if lhsDate == rhsDate {
                return lhs < rhs
            }
            return lhsDate < rhsDate
        }
    }

    private static func uniqueSources(_ sources: [WebSearchSource]) -> [WebSearchSource] {
        var seen = Set<String>()
        return sources.filter { source in
            if seen.contains(source.url) {
                return false
            }
            seen.insert(source.url)
            return true
        }
    }

    private static func attachments(from content: [ContentPart]) -> [ChatAttachment] {
        content.compactMap { part in
            guard part.type == "input_file" || part.type == "input_audio" || part.type == "input_image" else {
                return nil
            }
            let id = part.fileID ?? part.audioFileID ?? part.imageURL ?? UUID().uuidString
            let suffix = id.suffix(8)
            return ChatAttachment(id: id, name: "file-\(suffix)", kind: part.type, bytes: nil)
        }
    }
}
