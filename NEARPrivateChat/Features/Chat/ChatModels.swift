import Foundation
import SwiftUI

struct ConversationMetadata: Codable, Hashable {
    var title: String? = nil
    var pinnedAt: String? = nil
    var archivedAt: String? = nil
    var importedAt: String? = nil
    var rootResponseID: String? = nil

    enum CodingKeys: String, CodingKey {
        case title
        case pinnedAt = "pinned_at"
        case archivedAt = "archived_at"
        case importedAt = "imported_at"
        case rootResponseID = "root_response_id"
    }
}

struct ConversationSummary: Codable, Identifiable, Hashable {
    let id: String
    let createdAt: TimeInterval?
    var metadata: ConversationMetadata?

    var title: String {
        let trimmed = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed! : "New conversation"
    }

    var isPinned: Bool { metadata?.pinnedAt != nil }
    var isArchived: Bool { metadata?.archivedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case metadata
    }
}

enum ChatRole: String, Codable, Hashable {
    case user
    case assistant
    case system

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self).lowercased()
        switch value {
        case "user":
            self = .user
        case "system", "developer":
            self = .system
        case "assistant", "tool":
            self = .assistant
        default:
            self = .assistant
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct ContentPart: Codable, Hashable {
    let type: String
    let text: String?
    let fileID: String?
    let audioFileID: String?
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case fileID = "file_id"
        case audioFileID = "audio_file_id"
        case imageURL = "image_url"
    }
}

struct MessageMetadata: Codable, Hashable {
    let authorID: String?
    let authorName: String?

    enum CodingKeys: String, CodingKey {
        case authorID = "author_id"
        case authorName = "author_name"
    }

    var trimmedAuthorName: String? {
        let trimmed = authorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedAuthorID: String? {
        let trimmed = authorID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ConversationItem: Decodable, Identifiable, Hashable {
    let type: String
    let id: String
    let responseID: String
    let nextResponseIDs: [String]
    let createdAt: TimeInterval?
    let status: String?
    let role: ChatRole?
    let content: [ContentPart]?
    let model: String?
    let previousResponseID: String?
    let action: SearchAction?
    let metadata: MessageMetadata?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case responseID = "response_id"
        case nextResponseIDs = "next_response_ids"
        case createdAt = "created_at"
        case status
        case role
        case content
        case model
        case modelID = "model_id"
        case modelId = "modelId"
        case previousResponseID = "previous_response_id"
        case action
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decode(String.self, forKey: .id)
        responseID = try container.decodeIfPresent(String.self, forKey: .responseID) ?? id
        nextResponseIDs = try container.decodeIfPresent([String].self, forKey: .nextResponseIDs) ?? []
        createdAt = try container.decodeIfPresent(TimeInterval.self, forKey: .createdAt)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        role = try container.decodeIfPresent(ChatRole.self, forKey: .role)
        model = try container.decodeIfPresent(String.self, forKey: .model)
            ?? container.decodeIfPresent(String.self, forKey: .modelID)
            ?? container.decodeIfPresent(String.self, forKey: .modelId)
        previousResponseID = try container.decodeIfPresent(String.self, forKey: .previousResponseID)
        action = try container.decodeIfPresent(SearchAction.self, forKey: .action)
        metadata = try container.decodeIfPresent(MessageMetadata.self, forKey: .metadata)

        if let arrayContent = try? container.decodeIfPresent([ContentPart].self, forKey: .content) {
            content = arrayContent
        } else if let stringContent = try? container.decodeIfPresent(String.self, forKey: .content) {
            content = [ContentPart(type: "reasoning_text", text: stringContent, fileID: nil, audioFileID: nil, imageURL: nil)]
        } else {
            content = nil
        }
    }

    var displayText: String {
        guard let content else { return "" }
        let text = content.compactMap(\.text).joined()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SearchAction: Codable, Hashable {
    let query: String?
    let type: String?
    let sources: [WebSearchSource]?

    init(query: String?, type: String?, sources: [WebSearchSource]?) {
        self.query = query
        self.type = type
        self.sources = sources?.filter { $0.safeURL != nil }
    }

    enum CodingKeys: String, CodingKey {
        case query
        case type
        case sources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try container.decodeIfPresent(String.self, forKey: .query)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        let decodedSources = try container.decodeIfPresent([LossyDecodable<WebSearchSource>].self, forKey: .sources) ?? []
        let safeSources = decodedSources.compactMap(\.value)
        sources = safeSources.isEmpty ? nil : safeSources
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(query, forKey: .query)
        try container.encodeIfPresent(type, forKey: .type)
        let safeSources = sources?.filter { $0.safeURL != nil }
        if let safeSources, !safeSources.isEmpty {
            try container.encode(safeSources, forKey: .sources)
        }
    }
}

struct WebSearchSource: Codable, Hashable, Identifiable {
    let type: String?
    let url: String
    let title: String?
    let publishedAt: String?
    let snippet: String?

    var id: String { url }

    var safeURL: URL? {
        Self.safeURL(from: url)
    }

    var host: String {
        guard let host = safeURL?.host(percentEncoded: false) else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var displayTitle: String {
        let cleanedTitle = Self.cleanedMetadata(title, maxLength: 160)
        if let cleanedTitle, !cleanedTitle.isEmpty {
            return cleanedTitle
        }
        return host
    }

    var displaySubtitle: String {
        var parts = [host]
        if let publishedAt = publishedAt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !publishedAt.isEmpty {
            parts.append(publishedAt)
        }
        if let typeLabel,
           !Self.subtitleHiddenSourceTypes.contains(normalizedType ?? "") {
            parts.append(typeLabel)
        }
        return parts.joined(separator: " · ")
    }

    var snippetPreview: String? {
        snippet
    }

    var isWebSearchLike: Bool {
        guard let normalizedType else { return safeURL != nil }
        return Self.webSearchLikeTypes.contains(normalizedType)
    }

    var allowsNetworkFavicon: Bool {
        isWebSearchLike && safeURL != nil
    }

    var sourceBadgeLabel: String? {
        guard let normalizedType else { return safeURL == nil ? nil : "Web" }
        switch normalizedType {
        case "news", "newsarticle":
            return "News"
        case "web", "webpage", "website", "websearch", "search", "searchresult", "organic", "inferred", "citation", "urlcitation":
            return "Web"
        default:
            return nil
        }
    }

    var citationCopyText: String {
        var parts = [displayTitle, url]
        if let publishedAt = publishedAt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !publishedAt.isEmpty {
            parts.insert(publishedAt, at: 1)
        }
        return parts.joined(separator: "\n")
    }

    var sourceInitials: String {
        // "www." prefixes and punycode hosts produced "#" / "WW" chips that
        // read as broken icons. Fall back through host → title → "W".
        let hostParts = host.split(separator: ".").map(String.init)
        let base = hostParts.first(where: { $0.lowercased() != "www" && !$0.lowercased().hasPrefix("xn--") })
            ?? hostParts.first
            ?? host
        let letters = base.uppercased().filter { $0.isLetter || $0.isNumber }
        if let initials = letters.isEmpty ? nil : String(letters.prefix(2)), !initials.isEmpty {
            return initials
        }
        let titleLetters = (title ?? "").uppercased().filter { $0.isLetter || $0.isNumber }
        return titleLetters.isEmpty ? "W" : String(titleLetters.prefix(2))
    }

    init(type: String? = nil, url: String, title: String? = nil, publishedAt: String? = nil, snippet: String? = nil) {
        self.type = Self.cleanedMetadata(type, maxLength: 64)
        self.url = Self.sanitizedURLString(url) ?? ""
        self.title = Self.cleanedMetadata(title, maxLength: 160)
        self.publishedAt = Self.cleanedMetadata(publishedAt, maxLength: 80)
        self.snippet = Self.cleanedMetadata(snippet, maxLength: 600)
    }

    static func sanitizedURLString(_ value: String) -> String? {
        guard let url = safeURL(from: value) else { return nil }
        return url.absoluteString
    }

    private var typeLabel: String? {
        guard let rawType = type?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawType.isEmpty,
              rawType.caseInsensitiveCompare("web") != .orderedSame else {
            return nil
        }
        return rawType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var normalizedType: String? {
        guard let rawType = type?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawType.isEmpty else { return nil }
        return rawType
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static let webSearchLikeTypes: Set<String> = [
        "web",
        "webpage",
        "website",
        "websearch",
        "search",
        "searchresult",
        "organic",
        "news",
        "newsarticle",
        "inferred",
        "citation",
        "urlcitation"
    ]

    private static let subtitleHiddenSourceTypes: Set<String> = [
        "web",
        "webpage",
        "website",
        "websearch",
        "search",
        "searchresult",
        "organic",
        "inferred",
        "news",
        "citation",
        "urlcitation"
    ]

    static func cleanedMetadata(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.count <= maxLength {
            return cleaned
        }
        let cutoff = cleaned.index(cleaned.startIndex, offsetBy: maxLength - 3)
        return "\(cleaned[..<cutoff])..."
    }

    private static func safeURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 4_096,
              trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              let url = components.url,
              URLSecurity.isPublicHTTPSURL(url) else {
            return nil
        }
        return url
    }

    enum CodingKeys: String, CodingKey {
        case type
        case sourceType = "source_type"
        case url
        case title
        case name
        case publishedAt
        case publishedAtSnake = "published_at"
        case date
        case snippet
        case description
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decodeFirst(_ keys: [CodingKeys]) throws -> String? {
            for key in keys {
                if let value = try container.decodeIfPresent(String.self, forKey: key) {
                    return value
                }
            }
            return nil
        }

        type = Self.cleanedMetadata(try decodeFirst([.type, .sourceType]), maxLength: 64)
        let rawURL = try container.decode(String.self, forKey: .url)
        guard let safeURL = Self.sanitizedURLString(rawURL) else {
            throw DecodingError.dataCorruptedError(
                forKey: .url,
                in: container,
                debugDescription: "Search source URL must be http or https."
            )
        }
        url = safeURL
        title = Self.cleanedMetadata(try decodeFirst([.title, .name]), maxLength: 160)
        publishedAt = Self.cleanedMetadata(try decodeFirst([.publishedAt, .publishedAtSnake, .date]), maxLength: 80)
        snippet = Self.cleanedMetadata(try decodeFirst([.snippet, .description, .text]), maxLength: 600)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(publishedAt, forKey: .publishedAt)
        try container.encodeIfPresent(snippet, forKey: .snippet)
    }
}

private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

struct ConversationItemsResponse: Decodable {
    let data: [ConversationItem]
    let firstID: String?
    let hasMore: Bool?
    let lastID: String?

    enum CodingKeys: String, CodingKey {
        case data
        case firstID = "first_id"
        case hasMore = "has_more"
        case lastID = "last_id"
    }
}

struct ChatMessage: Identifiable, Hashable, Codable {
    var id: String
    var role: ChatRole
    var text: String
    var model: String?
    var createdAt: Date
    var firstTokenAt: Date? = nil
    var status: String
    var responseID: String?
    var previousResponseID: String? = nil
    var councilBatchID: String? = nil
    var isStreaming: Bool
    var searchQuery: String? = nil
    var sources: [WebSearchSource] = []
    var attachments: [ChatAttachment] = []
    var pendingApproval: IronclawPendingGate? = nil
    var projectFiles: [IronclawProjectFile] = []
    var branchVariant: MessageBranchVariant? = nil
    var metadata: MessageMetadata? = nil
    var widget: MessageWidget? = nil
    var trustMetadata: MessageTrustMetadata? = nil

    var tint: Color {
        switch role {
        case .user: .actionPrimary
        case .assistant: .primary
        case .system: .secondary
        }
    }

    var authorName: String? {
        metadata?.trimmedAuthorName
    }

    var authorID: String? {
        metadata?.trimmedAuthorID
    }

    var compactAuthorID: String? {
        guard let authorID else { return nil }
        if authorID.count <= 24 {
            return authorID
        }
        return "\(authorID.prefix(10))...\(authorID.suffix(6))"
    }

    var authorDisplayLabel: String? {
        authorName ?? compactAuthorID
    }

    var firstTokenLatency: TimeInterval? {
        guard let firstTokenAt else { return nil }
        return max(0, firstTokenAt.timeIntervalSince(createdAt))
    }

    var hasUsableCouncilAnswer: Bool {
        role == .assistant &&
            councilBatchID?.isEmpty == false &&
            !isStreaming &&
            status.lowercased() != "failed" &&
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct MessageTrustMetadata: Codable, Hashable {
    var route: MessageRouteMetadata
    var proof: MessageProofMetadata?
    var capturedAt: Date
}

struct MessageRouteMetadata: Codable, Hashable {
    var modelID: String?
    var routeKind: String
    var provider: String
    var privacyRoute: String
    var sourceMode: String
    var sourceModeTitle: String
    var webSearchEnabled: Bool
    var researchModeEnabled: Bool
    var projectContextIncluded: Bool
    var capturedAt: Date

    init(
        modelID: String?,
        routeKind: ChatRouteKind,
        sourceMode: ChatSourceMode,
        webSearchEnabled: Bool,
        researchModeEnabled: Bool,
        projectContextIncluded: Bool,
        capturedAt: Date = Date()
    ) {
        let trimmedModelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelID = trimmedModelID?.isEmpty == false ? trimmedModelID : nil
        self.routeKind = routeKind.rawValue
        provider = Self.provider(for: routeKind, modelID: trimmedModelID)
        privacyRoute = Self.privacyRoute(for: routeKind, modelID: trimmedModelID)
        self.sourceMode = sourceMode.rawValue
        sourceModeTitle = sourceMode.title
        self.webSearchEnabled = webSearchEnabled
        self.researchModeEnabled = researchModeEnabled
        self.projectContextIncluded = projectContextIncluded
        self.capturedAt = capturedAt
    }

    static func provider(for routeKind: ChatRouteKind, modelID: String?) -> String {
        if modelID == ModelOption.llmCouncilSynthesisModelID {
            return "llm-council"
        }
        switch routeKind {
        case .nearPrivate:
            return "near-private"
        case .nearCloud:
            return "near-cloud"
        case .ironclawMobile:
            return "ironclaw-mobile"
        case .ironclawHosted:
            return "ironclaw-hosted"
        }
    }

    static func privacyRoute(for routeKind: ChatRouteKind, modelID: String?) -> String {
        if modelID == ModelOption.llmCouncilSynthesisModelID {
            return "multi-model-synthesis"
        }
        switch routeKind {
        case .nearPrivate:
            return "tee-private"
        case .nearCloud:
            return "external-cloud"
        case .ironclawMobile:
            return "phone-agent"
        case .ironclawHosted:
            return "hosted-agent"
        }
    }
}

struct MessageProofMetadata: Codable, Hashable {
    var state: ProofState
    var title: String
    var detail: String
    var badge: String
    var symbolName: String
    var freshness: String?
    var reportHash: String?
    var coveredModelCount: Int
    var coversSelectedModel: Bool?
    var capturedAt: Date
}

struct MessageBranchVariant: Hashable, Codable {
    var responseIDs: [String]
    var currentResponseID: String
    var parentResponseID: String?

    var count: Int { responseIDs.count }

    var currentIndex: Int {
        responseIDs.firstIndex(of: currentResponseID) ?? 0
    }

    var displayIndex: Int {
        currentIndex + 1
    }

    var previousResponseID: String? {
        guard currentIndex > 0 else { return nil }
        return responseIDs[currentIndex - 1]
    }

    var nextResponseID: String? {
        guard currentIndex + 1 < responseIDs.count else { return nil }
        return responseIDs[currentIndex + 1]
    }
}
