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
        return Self.previewMessage(from: sourceMessages)
            .map { Self.compactPreviewText($0.text) }
    }

    func cachedConversationHeadline(
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
        return Self.headlineMessage(from: sourceMessages)
            .map { Self.compactPreviewText($0.text) }
    }

    func cachedConversationHasSourceCue(
        for conversationID: String,
        selectedConversationID: String?,
        currentMessages: [ChatMessage]
    ) -> Bool {
        let sourceMessages: [ChatMessage]
        if selectedConversationID == conversationID, !currentMessages.isEmpty {
            sourceMessages = currentMessages
        } else {
            sourceMessages = loadLocalMessages(for: conversationID) ?? []
        }
        return Self.hasSourceCue(from: sourceMessages)
    }

    func cachedConversationSourceSummary(
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
        return Self.sourceSummary(from: sourceMessages)
    }

    func cachedConversationSourceChips(
        for conversationID: String,
        selectedConversationID: String?,
        currentMessages: [ChatMessage]
    ) -> [ConversationSourceChip] {
        let sourceMessages: [ChatMessage]
        if selectedConversationID == conversationID, !currentMessages.isEmpty {
            sourceMessages = currentMessages
        } else {
            sourceMessages = loadLocalMessages(for: conversationID) ?? []
        }
        return Self.sourceChips(from: sourceMessages)
    }

    static func previewMessage(from messages: [ChatMessage]) -> ChatMessage? {
        func hasText(_ message: ChatMessage) -> Bool {
            !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if let synthesis = messages.reversed().first(where: {
            hasText($0) && $0.role == .assistant && $0.model == ModelOption.llmCouncilSynthesisModelID
        }) {
            return synthesis
        }
        if let answer = messages.reversed().first(where: { hasText($0) && $0.role == .assistant }) {
            return answer
        }
        return messages.reversed().first(where: hasText)
    }

    static func headlineMessage(from messages: [ChatMessage]) -> ChatMessage? {
        func hasText(_ message: ChatMessage) -> Bool {
            !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard let preview = previewMessage(from: messages),
              let previewIndex = messages.lastIndex(where: { $0.id == preview.id }) else {
            return messages.reversed().first { hasText($0) && $0.role == .user }
        }
        if preview.role == .assistant {
            let previousMessages = messages[..<previewIndex]
            if let userPrompt = previousMessages.reversed().first(where: { hasText($0) && $0.role == .user }) {
                return userPrompt
            }
        }
        if preview.role == .user {
            return preview
        }
        return messages.reversed().first { hasText($0) && $0.role == .user }
    }

    static func hasSourceCue(from messages: [ChatMessage]) -> Bool {
        guard let message = previewMessage(from: messages) else { return false }
        return hasSourceCue(in: message)
    }

    static func sourceSummary(from messages: [ChatMessage]) -> String? {
        guard let message = previewMessage(from: messages) else { return nil }
        return sourceSummary(in: message)
    }

    static func sourceChips(from messages: [ChatMessage]) -> [ConversationSourceChip] {
        guard let message = previewMessage(from: messages) else { return [] }
        return sourceChips(in: message)
    }

    static func sourceSummary(in message: ChatMessage) -> String? {
        var labels = orderedUnique(message.sources.map(\.host).filter { !$0.isEmpty })
        var sourceCount = labels.count

        let widgets = [
            message.widget,
            MessageWidget.extract(from: message.text).widget
        ]
        for widget in widgets.compactMap({ $0 }) {
            let evidence = widgetSourceEvidence(widget)
            labels.append(contentsOf: evidence.labels)
            sourceCount += evidence.count
        }

        labels = orderedUnique(labels)
        sourceCount = max(sourceCount, labels.count)

        if let label = labels.first {
            let displayLabel = SourceFaviconResolver.displayName(for: label, fallback: label) ?? label
            if sourceCount > 1 {
                return "\(displayLabel) + \(sourceCount - 1)"
            }
            return displayLabel
        }
        if sourceCount > 1 {
            return "\(sourceCount) sources"
        }
        return textHasSourceCue(message.text) ? "Sources" : nil
    }

    static func sourceChips(in message: ChatMessage) -> [ConversationSourceChip] {
        var chips: [ConversationSourceChip] = []
        for source in message.sources {
            let host = source.host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { continue }
            chips.append(ConversationSourceChip(
                text: SourceFaviconResolver.displayName(for: host, fallback: host) ?? host,
                faviconDomain: host,
                fallback: String(source.sourceInitials.prefix(1)),
                allowsNetworkFavicon: source.allowsNetworkFavicon
            ))
        }

        let widgets = [
            message.widget,
            MessageWidget.extract(from: message.text).widget
        ]
        for widget in widgets.compactMap({ $0 }) {
            chips.append(contentsOf: widgetSourceChips(widget))
        }

        return orderedUniqueSourceChips(chips)
    }

    static func hasSourceCue(in message: ChatMessage) -> Bool {
        if !message.sources.isEmpty { return true }
        if widgetHasSourceCue(message.widget) { return true }
        if let extraction = MessageWidget.extract(from: message.text).widget,
           widgetHasSourceCue(extraction) {
            return true
        }
        return textHasSourceCue(message.text)
    }

    static func textHasSourceCue(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("sources:") ||
            normalized.contains("source:") ||
            normalized.contains("source ") ||
            normalized.contains("citation") ||
            normalized.contains("cites ") ||
            normalized.contains("reuters") ||
            normalized.contains("apnews") ||
            normalized.contains("associated press") ||
            normalized.contains("bloomberg") ||
            normalized.contains("guardian") ||
            normalized.contains("al jazeera") ||
            normalized.contains("macrumors") ||
            normalized.contains("releasebot") ||
            normalized.contains("buildfastwithai") ||
            normalized.contains("http://") ||
            normalized.contains("https://") ||
            normalized.range(of: #"\b[a-z0-9-]+\.(?:com|org|net|ai|io|gov|edu|co)\b"#, options: .regularExpression) != nil
    }

    private static func widgetHasSourceCue(_ widget: MessageWidget?) -> Bool {
        guard let widget else { return false }
        if let newsBrief = widget.newsBrief {
            return newsBrief.stories.contains { story in
                !story.sources.isEmpty || story.url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
        }
        if let actionPlan = widget.actionPlan {
            return actionPlan.actions.contains { action in
                action.source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
        }
        return false
    }

    private static func widgetSourceEvidence(_ widget: MessageWidget) -> (labels: [String], count: Int) {
        var labels: [String] = []
        var count = 0
        if let newsBrief = widget.newsBrief {
            for story in newsBrief.stories {
                for source in story.sources {
                    count += 1
                    if let domain = source.domain?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !domain.isEmpty {
                        labels.append(normalizedSourceLabel(domain))
                    }
                }
                if let url = story.url?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !url.isEmpty {
                    count += 1
                    labels.append(normalizedSourceLabel(url))
                }
            }
        }
        if let actionPlan = widget.actionPlan {
            for action in actionPlan.actions {
                if let source = action.source?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !source.isEmpty {
                    count += 1
                }
            }
        }
        return (orderedUnique(labels), count)
    }

    private static func widgetSourceChips(_ widget: MessageWidget) -> [ConversationSourceChip] {
        var chips: [ConversationSourceChip] = []
        if let newsBrief = widget.newsBrief {
            for story in newsBrief.stories {
                for source in story.sources {
                    guard let text = source.displaySourceText.nilIfBlank else { continue }
                    chips.append(ConversationSourceChip(
                        text: text,
                        faviconDomain: source.faviconIdentity,
                        fallback: source.fallbackMark,
                        allowsNetworkFavicon: source.allowsNetworkFavicon
                    ))
                }
                if let url = story.url?.nilIfBlank,
                   let host = URL(string: url)?.host(percentEncoded: false) {
                    chips.append(ConversationSourceChip(
                        text: SourceFaviconResolver.displayName(for: host, fallback: host) ?? host,
                        faviconDomain: host,
                        fallback: SourceFaviconResolver.fallbackLetter(for: host, fallback: "S"),
                        allowsNetworkFavicon: URLSecurity.isPublicHost(host)
                    ))
                }
            }
        }
        return chips
    }

    private static func normalizedSourceLabel(_ raw: String) -> String {
        if let host = URL(string: raw)?.host(percentEncoded: false) {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return raw
            .replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    private static func orderedUniqueSourceChips(_ chips: [ConversationSourceChip]) -> [ConversationSourceChip] {
        var seen: Set<String> = []
        var result: [ConversationSourceChip] = []
        for chip in chips {
            let key = (chip.faviconDomain ?? chip.text).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(chip)
        }
        return result
    }

    static func mergedMessages(remoteMessages: [ChatMessage], localCache: [ChatMessage]?) -> [ChatMessage] {
        guard let localCache, !localCache.isEmpty else { return remoteMessages }
        let locallySourcedAssistantsByResponseID = Dictionary(
            grouping: localCache.filter { message in
                message.role == .assistant &&
                    message.responseID?.isEmpty == false &&
                    (!message.sources.isEmpty || message.searchQuery?.isEmpty == false)
            },
            by: { $0.responseID ?? "" }
        )
        let remoteMessages = remoteMessages.map { remoteMessage -> ChatMessage in
            guard remoteMessage.role == .assistant,
                  let responseID = remoteMessage.responseID,
                  let localMessage = locallySourcedAssistantsByResponseID[responseID]?.first else {
                return remoteMessage
            }
            var merged = remoteMessage
            if merged.sources.isEmpty {
                merged.sources = localMessage.sources
            }
            if merged.searchQuery?.isEmpty != false {
                merged.searchQuery = localMessage.searchQuery
            }
            if merged.trustMetadata == nil {
                merged.trustMetadata = localMessage.trustMetadata
            }
            return merged
        }
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
        let councilBatchIDsWithAssistantMessages = Set(
            localCache.compactMap { message -> String? in
                guard message.role == .assistant,
                      let batchID = message.councilBatchID,
                      !batchID.isEmpty else { return nil }
                return batchID
            }
        )
        let localOnly = localCache.filter { message in
            guard !remoteIDs.contains(message.id) else { return false }
            // If the server ever starts returning this turn (same responseID
            // under a different item ID), prefer the remote copy.
            if let responseID = message.responseID, remoteResponseIDs.contains(responseID) {
                return false
            }
            if isExternalModel(message.model ?? "") { return true }
            if let batchID = message.councilBatchID, !batchID.isEmpty {
                guard message.role == .user else { return true }
                let trimmedText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return councilBatchIDsWithAssistantMessages.contains(batchID) &&
                    !remoteUserTexts.contains(trimmedText)
            }
            if message.model == ModelOption.llmCouncilSynthesisModelID { return true }
            if ["failed", "approval", "gate_denied", "cancelled"].contains(message.status) { return true }
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
                    text: displayText(for: item),
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

    private static func displayText(for item: ConversationItem) -> String {
        let text = item.displayText
        guard item.role == .user else { return text }
        return sanitizedUserDisplayText(text)
    }

    static func sanitizedUserDisplayText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let visibleWebRequest = visibleAppWebGroundingRequest(from: trimmed) {
            return sanitizedUserDisplayText(visibleWebRequest)
        }

        let hasInjectedDocumentContext = trimmed.hasPrefix("Relevant excerpts from the attached document(s):") ||
            trimmed.hasPrefix("Relevant excerpts from the attached table(s):")
        guard hasInjectedDocumentContext else { return trimmed }

        let markers = [
            "\n\nUsing those excerpts (and the attached file or table) where relevant:\n",
            "\n\nUsing those excerpts (my attached on-device document) where relevant:\n"
        ]
        guard let match = markers
            .compactMap({ marker -> Range<String.Index>? in trimmed.range(of: marker, options: .backwards) })
            .max(by: { $0.lowerBound < $1.lowerBound }) else {
            return trimmed
        }

        let visibleQuestion = trimmed[match.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return visibleQuestion.isEmpty ? trimmed : sanitizedUserDisplayText(visibleQuestion)
    }

    private static func visibleAppWebGroundingRequest(from text: String) -> String? {
        guard text.contains("App-side web search results for"),
              let requestMarker = text.range(of: "User request:\n") else {
            return nil
        }
        let contextMarkers = [
            "\n\nApp-side web search results for",
            "\nApp-side web search results for"
        ]
        guard let contextMarker = contextMarkers
            .compactMap({ marker -> Range<String.Index>? in
                text.range(of: marker, range: requestMarker.upperBound..<text.endIndex)
            })
            .min(by: { $0.lowerBound < $1.lowerBound }) else {
            return nil
        }

        let request = text[requestMarker.upperBound..<contextMarker.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return request.isEmpty ? nil : request
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
        var collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let failurePreview = compactFailurePreview(collapsed) {
            return failurePreview
        }
        collapsed = cleanedPreviewLead(collapsed)
        guard collapsed.count > 140 else { return collapsed }
        return "\(collapsed.prefix(137))..."
    }

    private static func compactFailurePreview(_ text: String) -> String? {
        let lowercased = text.lowercased()
        if lowercased.contains("private route is rate-limited") ||
            lowercased.contains("private route is temporarily busy") ||
            lowercased.contains("access temporarily restricted") {
            return "Private route limited. Retry private or add Cloud key."
        }
        if lowercased.contains("authentication is missing or expired") ||
            lowercased.contains("sign in again") ||
            lowercased.contains("isn't authenticated") {
            return "Sign-in needed. Open Account, then retry."
        }
        return nil
    }

    private static func cleanedPreviewLead(_ text: String) -> String {
        var value = text
        if value.hasPrefix("#") {
            value = value.replacingOccurrences(
                of: #"^#{1,6}\s+"#,
                with: "",
                options: .regularExpression
            )
        }

        let boilerplates = [
            "Direct answer:",
            "Direct answer",
            "Short answer:",
            "Answer:",
            "Summary:"
        ]
        for boilerplate in boilerplates where value.localizedCaseInsensitiveCompare(boilerplate) == .orderedSame {
            return ""
        }
        for boilerplate in boilerplates {
            let prefix = boilerplate + " "
            if hasCaseInsensitivePrefix(value, prefix) {
                value = String(value.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        guard let first = value.unicodeScalars.first,
              CharacterSet.lowercaseLetters.contains(first) else {
            return value
        }
        let firstCharacter = String(Character(first)).uppercased()
        return firstCharacter + String(value.dropFirst())
    }

    private static func hasCaseInsensitivePrefix(_ value: String, _ prefix: String) -> Bool {
        value.range(of: prefix, options: [.anchored, .caseInsensitive]) != nil
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
