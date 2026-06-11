import Foundation

struct MessageLoadResult: Equatable {
    let messages: [ChatMessage]
    let cachedMessages: [ChatMessage]?
    let usedCacheOnly: Bool
    let shouldPersistLoadedMessages: Bool
    let shouldRefreshExternalLatestResponse: Bool
}

struct MessageRepository {
    private let conversationAPI: ConversationAPI
    private var cache: MessageCache?

    init(conversationAPI: ConversationAPI, cache: MessageCache? = nil) {
        self.conversationAPI = conversationAPI
        self.cache = cache
    }

    mutating func configure(accountID: String) {
        cache = MessageCache(accountID: accountID)
    }

    func loadMessages(
        for conversationID: String,
        preferredResponseID: String?,
        preferCached: Bool
    ) async throws -> MessageLoadResult {
        let cachedMessages = loadLocalMessages(for: conversationID)
        if preferCached, let cachedMessages, !cachedMessages.isEmpty {
            return MessageLoadResult(
                messages: Self.normalizedMessages(cachedMessages, assumingStreamLost: true),
                cachedMessages: cachedMessages,
                usedCacheOnly: true,
                shouldPersistLoadedMessages: false,
                shouldRefreshExternalLatestResponse: cachedMessages.contains { Self.isExternalModel($0.model ?? "") }
            )
        }

        let response = try await conversationAPI.fetchConversationItems(conversationID)
        let remoteMessages = Self.chatMessages(from: response.data, preferredResponseID: preferredResponseID)
        let loadedMessages = Self.mergedMessages(remoteMessages: remoteMessages, localCache: cachedMessages)
        return MessageLoadResult(
            messages: loadedMessages,
            cachedMessages: cachedMessages,
            usedCacheOnly: false,
            shouldPersistLoadedMessages: loadedMessages != cachedMessages,
            shouldRefreshExternalLatestResponse: false
        )
    }

    func loadRemoteMessages(for conversationID: String, preferredResponseID: String? = nil) async throws -> [ChatMessage] {
        let response = try await conversationAPI.fetchConversationItems(conversationID)
        return Self.chatMessages(from: response.data, preferredResponseID: preferredResponseID)
    }

    func loadLocalMessages(for conversationID: String) -> [ChatMessage]? {
        cache?.loadMessages(for: conversationID)
    }

    func loadLocalMessageCache() -> [String: [ChatMessage]] {
        cache?.loadCache() ?? [:]
    }

    @discardableResult
    func saveLocalMessages(_ messages: [ChatMessage], for conversationID: String) -> Bool {
        cache?.save(messages, for: conversationID) ?? true
    }

    @discardableResult
    func removeLocalMessages(for conversationID: String) -> Bool {
        cache?.removeMessages(for: conversationID) ?? true
    }

    func cachedConversationPreview(
        for conversationID: String,
        selectedConversationID: String?,
        currentMessages: [ChatMessage]
    ) -> String? {
        let sourceMessages: [ChatMessage]
        if selectedConversationID == conversationID, !currentMessages.isEmpty {
            sourceMessages = currentMessages
        } else {
            sourceMessages = loadLocalMessages(for: conversationID) ?? []
        }
        return sourceMessages
            .reversed()
            .first { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { Self.compactPreviewText($0.text) }
    }

    static func mergedMessages(remoteMessages: [ChatMessage], localCache: [ChatMessage]?) -> [ChatMessage] {
        guard let localCache, !localCache.isEmpty else { return remoteMessages }
        let remoteIDs = Set(remoteMessages.map(\.id))
        let remoteResponseIDs = Set(remoteMessages.compactMap(\.responseID))

        // Per-message preservation: council turns (members + synthesis) and
        // failed/cancelled/approval turns exist only locally — the server's
        // /items feed does not return them, so dropping them here is what made
        // council answers vanish on re-open. Plain completed private assistant
        // turns still defer to the server copy (they round-trip under server
        // IDs; preserving them would duplicate).
        let cacheHasExternalTurn = localCache.contains { isExternalModel($0.model ?? "") }
        let remoteUserTexts = Set(
            remoteMessages
                .filter { $0.role == .user }
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
        let localOnly = localCache.filter { message in
            guard !remoteIDs.contains(message.id) else { return false }
            // If the server ever starts returning this turn (same responseID
            // under a different item ID), prefer the remote copy.
            if let responseID = message.responseID, remoteResponseIDs.contains(responseID) {
                return false
            }
            if isExternalModel(message.model ?? "") { return true }
            if message.councilBatchID?.isEmpty == false { return true }
            if message.model == ModelOption.llmCouncilSynthesisModelID { return true }
            if ["failed", "approval", "cancelled"].contains(message.status) { return true }
            if message.role == .user {
                // External-route chats keep their local user turns (the server
                // never stores them). Private user turns round-trip, so only
                // keep ones the server provably doesn't have (e.g. the prompt
                // of a failed send) — matched by text to avoid duplicates.
                if cacheHasExternalTurn { return true }
                return !remoteUserTexts.contains(message.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return false
        }
        guard !localOnly.isEmpty else { return remoteMessages }
        return (remoteMessages + localOnly).sorted { lhs, rhs in
            lhs.createdAt < rhs.createdAt
        }
    }

    static func chatMessages(from items: [ConversationItem], preferredResponseID: String? = nil) -> [ChatMessage] {
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
        let visibleItems = activeConversationPathItems(from: messageItems, preferredResponseID: preferredResponseID)
        let messages = visibleItems
            .map { item in
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
        return normalizedMessages(messages, assumingStreamLost: false)
    }

    static func normalizedMessages(_ messages: [ChatMessage], assumingStreamLost: Bool) -> [ChatMessage] {
        let now = Date()
        return messages.map { message in
            guard message.role == .assistant else { return message }
            var normalized = message
            if normalized.model == ModelOption.ironclawModelID, isTransportOnlyGatewayText(normalized.text) {
                normalized.text = gatewayStatusFailureMessage
                normalized.status = "failed"
                normalized.isStreaming = false
                return normalized
            }
            if normalized.model == ModelOption.ironclawModelID, let failureMessage = localFailureMessage(from: normalized.text) {
                normalized.text = failureMessage
                normalized.status = "failed"
                normalized.isStreaming = false
                return normalized
            }

            let status = normalized.status.lowercased()
            let isActiveStatus = ["streaming", "reasoning", "searching", "thinking", "running", "queued", "in_progress"].contains(status)
            let isOld = now.timeIntervalSince(normalized.createdAt) > staleRunningMessageInterval
            if normalized.isStreaming || (isActiveStatus && (assumingStreamLost || isOld)) {
                normalized.text = normalized.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? staleRunFailureMessage
                    : normalized.text
                normalized.status = "failed"
                normalized.isStreaming = false
            }
            return normalized
        }
    }

    static func uniqueSources(_ sources: [WebSearchSource]) -> [WebSearchSource] {
        var seen = Set<String>()
        return sources.filter { source in
            if seen.contains(source.url) {
                return false
            }
            seen.insert(source.url)
            return true
        }
    }

    static func inferredSources(from text: String) -> [WebSearchSource] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s\)\]\}<>"]+"#) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        let sources = matches.compactMap { match -> WebSearchSource? in
            guard let range = Range(match.range, in: text) else { return nil }
            let rawURL = String(text[range])
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
            guard let url = WebSearchSource.sanitizedURLString(rawURL) else { return nil }
            return WebSearchSource(type: "inferred", url: url)
        }
        return Array(uniqueSources(sources).prefix(8))
    }

    static func compactPreviewText(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 140 else { return collapsed }
        return "\(collapsed.prefix(137))..."
    }

    static func isExternalModel(_ modelID: String) -> Bool {
        modelID == ModelOption.ironclawModelID ||
            modelID == ModelOption.ironclawMobileModelID ||
            modelID.hasPrefix(ModelOption.nearCloudModelPrefix)
    }

    private static let staleRunningMessageInterval: TimeInterval = 120

    private static var gatewayStatusFailureMessage: String {
        "IronClaw accepted the request, but Hosted IronClaw only returned gateway status instead of a final answer. Start or repair the Agent connection, then retry."
    }

    private static var staleRunFailureMessage: String {
        "This run was interrupted or timed out before visible output arrived. Retry the message with a reachable model or Agent connection."
    }

    private static func isTransportOnlyGatewayText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return normalized == "accepted" ||
            normalized == "running" ||
            normalized == "queued" ||
            (normalized.contains("accepted") && normalized.contains("gateway")) ||
            (normalized.contains("running") && normalized.contains("configured gateway"))
    }

    static func localFailureMessage(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawMessage: String?
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            rawMessage = (object["error"] as? String) ?? (object["message"] as? String) ?? (object["detail"] as? String)
        } else if isRawToolFailureText(trimmed) {
            rawMessage = trimmed
        } else {
            rawMessage = nil
        }

        return rawMessage.map(displayFailureMessage)
    }

    static func transportFailureMessage(_ urlError: URLError) -> String? {
        ErrorMessageMapper.transportFailureMessage(urlError)
    }

    static func displayFailureMessage(_ rawValue: String) -> String {
        ErrorMessageMapper.displayFailureMessage(rawValue)
    }

    private static func isRawToolFailureText(_ text: String) -> Bool {
        let lowercased = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.isEmpty else { return false }
        return lowercased.contains("tool error") ||
            lowercased.contains("tool '") ||
            lowercased.contains("tool \"")
    }

    private static func activeConversationPathItems(from items: [ConversationItem], preferredResponseID: String? = nil) -> [ConversationItem] {
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

        let currentID: String
        var activeIDs: [String]
        if let preferredResponseID, responseIDs.contains(preferredResponseID) {
            var ancestry: [String] = [preferredResponseID]
            var cursor = preferredResponseID
            var seen = Set([preferredResponseID])
            while let parent = parentByResponseID[cursor] ?? nil,
                  !parent.isEmpty,
                  responseIDs.contains(parent),
                  !seen.contains(parent) {
                ancestry.append(parent)
                seen.insert(parent)
                cursor = parent
            }
            currentID = preferredResponseID
            activeIDs = Array(ancestry.reversed().dropLast())
        } else {
            guard let rootID = sortedResponseIDs(rootIDs, createdAt: responseCreatedAt).last else {
                return items
            }
            currentID = rootID
            activeIDs = []
        }

        var cursorID = currentID
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
