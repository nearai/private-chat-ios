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
        if let typeLabel {
            parts.append(typeLabel)
        }
        return parts.joined(separator: " · ")
    }

    var snippetPreview: String? {
        Self.cleanedMetadata(snippet, maxLength: 420)
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
        let base = host
            .split(separator: ".")
            .first
            .map(String.init) ?? host
        let letters = base.uppercased().filter { $0.isLetter || $0.isNumber }
        let initials = String(letters.prefix(2))
        return initials.isEmpty ? "#" : initials
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
    var branchVariant: MessageBranchVariant? = nil
    var metadata: MessageMetadata? = nil
    var widget: MessageWidget? = nil
    var trustMetadata: MessageTrustMetadata? = nil

    var tint: Color {
        switch role {
        case .user: .brandBlue
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

// MARK: - Generative widgets
//
// A typed, render-ready payload attached to an assistant message so the answer's
// *shape* matches the question's shape: a price question returns a chart, a
// comparison returns a table, a digest returns a story list. The model emits a
// fenced ```near-widget JSON block; `MessageWidget.extract` parses it client-side
// and strips it from the displayed prose. Decoders are deliberately forgiving —
// model-emitted JSON varies, and a malformed block must degrade to plain text,
// never crash.

enum WidgetKind: String, Codable, Hashable {
    case chart
    case metric
    case comparison
    case newsBrief
    case actionPlan
    case generic

    init(from decoder: Decoder) throws {
        let raw = ((try? decoder.singleValueContainer().decode(String.self)) ?? "")
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch raw {
        case "chart", "sparkline", "price", "trend", "line": self = .chart
        case "metric", "stat", "number", "kpi", "gauge": self = .metric
        case "comparison", "compare", "table", "matrix", "versus", "vs": self = .comparison
        case "newsbrief", "news", "brief", "digest", "headlines", "stories": self = .newsBrief
        case "actionplan", "actions", "action", "tasks", "nextactions", "nextsteps": self = .actionPlan
        default: self = .generic
        }
    }
}

enum WidgetTrend: String, Codable, Hashable {
    case up, down, flat

    init(from decoder: Decoder) throws {
        let raw = ((try? decoder.singleValueContainer().decode(String.self)) ?? "").lowercased()
        switch raw {
        case "up", "rise", "rising", "positive", "gain", "bull": self = .up
        case "down", "fall", "falling", "negative", "loss", "drop", "bear": self = .down
        default: self = .flat
        }
    }
}

enum WidgetTone: String, Codable, Hashable {
    case neutral, good, warn, bad, off

    init(from decoder: Decoder) throws {
        let raw = ((try? decoder.singleValueContainer().decode(String.self)) ?? "").lowercased()
        switch raw {
        case "good", "ok", "yes", "pass", "positive", "up", "supported": self = .good
        case "warn", "warning", "preview", "partial", "caution": self = .warn
        case "bad", "negative", "down", "error", "fail", "danger": self = .bad
        case "off", "no", "none", "na", "n/a", "missing", "unsupported": self = .off
        default: self = .neutral
        }
    }
}

enum WidgetFreshness: String, Codable, Hashable {
    case fresh, stale

    init(from decoder: Decoder) throws {
        let raw = ((try? decoder.singleValueContainer().decode(String.self)) ?? "").lowercased()
        self = (raw == "stale" || raw == "old" || raw == "cached") ? .stale : .fresh
    }
}

struct WidgetChart: Codable, Hashable {
    var label: String? = nil       // "ETH / USD"
    var value: String? = nil       // "$3,124"
    var delta: String? = nil       // "−$74.20 (−2.3%)"
    var trend: WidgetTrend? = nil
    var points: [Double] = []      // sparkline samples, oldest → newest
    var caption: String? = nil     // "Threshold $3,180 broken at 9:47am"
    var timeframe: String? = nil   // "past 1h"
}

extension WidgetChart {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try? c.decode(String.self, forKey: .label),
            value: try? c.decode(String.self, forKey: .value),
            delta: try? c.decode(String.self, forKey: .delta),
            trend: try? c.decode(WidgetTrend.self, forKey: .trend),
            points: (try? c.decode([Double].self, forKey: .points)) ?? [],
            caption: try? c.decode(String.self, forKey: .caption),
            timeframe: try? c.decode(String.self, forKey: .timeframe)
        )
    }
}

struct WidgetMetric: Codable, Hashable {
    var label: String? = nil
    var value: String = ""
    var delta: String? = nil
    var trend: WidgetTrend? = nil
    var caption: String? = nil
}

extension WidgetMetric {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try? c.decode(String.self, forKey: .label),
            value: (try? c.decode(String.self, forKey: .value)) ?? "",
            delta: try? c.decode(String.self, forKey: .delta),
            trend: try? c.decode(WidgetTrend.self, forKey: .trend),
            caption: try? c.decode(String.self, forKey: .caption)
        )
    }
}

struct WidgetComparisonCell: Codable, Hashable {
    var text: String = ""
    var tone: WidgetTone? = nil
}

extension WidgetComparisonCell {
    init(from decoder: Decoder) throws {
        // Accept a bare string ("AES-128 XEX") or an object ({text, tone}).
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self) {
            self.init(text: s, tone: nil)
            return
        }
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        self.init(
            text: (try? c?.decode(String.self, forKey: .text)) ?? "",
            tone: try? c?.decode(WidgetTone.self, forKey: .tone)
        )
    }
}

struct WidgetComparisonRow: Codable, Hashable {
    var label: String = ""
    var cells: [WidgetComparisonCell] = []
}

extension WidgetComparisonRow {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: (try? c.decode(String.self, forKey: .label)) ?? "",
            cells: (try? c.decode([WidgetComparisonCell].self, forKey: .cells)) ?? []
        )
    }
}

struct WidgetComparison: Codable, Hashable {
    var subtitle: String? = nil    // "SEV-SNP vs TDX"
    var columns: [String] = []
    var rows: [WidgetComparisonRow] = []
}

extension WidgetComparison {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            subtitle: try? c.decode(String.self, forKey: .subtitle),
            columns: (try? c.decode([String].self, forKey: .columns)) ?? [],
            rows: (try? c.decode([WidgetComparisonRow].self, forKey: .rows)) ?? []
        )
    }
}

struct WidgetNewsSource: Codable, Hashable {
    var label: String = ""         // favicon initial, e.g. "W"
    var color: String? = nil       // hex, e.g. "#ff7e1c"
    var domain: String? = nil
}

extension WidgetNewsSource {
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self) {
            self.init(label: String(s.prefix(1)).uppercased(), color: nil, domain: s)
            return
        }
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: (try? c?.decode(String.self, forKey: .label)) ?? "",
            color: try? c?.decode(String.self, forKey: .color),
            domain: try? c?.decode(String.self, forKey: .domain)
        )
    }
}

struct WidgetNewsStory: Codable, Hashable {
    var title: String = ""
    var tag: String? = nil
    var sources: [WidgetNewsSource] = []
    var url: String? = nil
}

extension WidgetNewsStory {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            title: (try? c.decode(String.self, forKey: .title)) ?? "",
            tag: try? c.decode(String.self, forKey: .tag),
            sources: (try? c.decode([WidgetNewsSource].self, forKey: .sources)) ?? [],
            url: try? c.decode(String.self, forKey: .url)
        )
    }
}

struct WidgetNewsBrief: Codable, Hashable {
    var heading: String? = nil     // "Today · 3 stories"
    var stories: [WidgetNewsStory] = []
}

extension WidgetNewsBrief {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            heading: try? c.decode(String.self, forKey: .heading),
            stories: (try? c.decode([WidgetNewsStory].self, forKey: .stories)) ?? []
        )
    }
}

struct WidgetActionItem: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var title: String = ""
    var type: String? = nil        // tracker, reminder, calendar, task, decision, question
    var detail: String? = nil
    var schedule: String? = nil
    var command: String? = nil     // composer-safe command to stage, never auto-run
    var source: String? = nil      // filename, row, thread, or project note provenance
    var date: String? = nil
    var time: String? = nil
    var duration: String? = nil
    var recurrence: String? = nil
    var timezone: String? = nil
    var location: String? = nil
    var attendees: [String] = []
    var missingFields: [String] = []
    var confidence: Double? = nil
    var tone: WidgetTone? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, type, detail, schedule, command
        case source, date, time, duration, recurrence, timezone, location, attendees, confidence, tone
        case missingFields = "missing_fields"
    }
}

extension WidgetActionItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString,
            title: (try? c.decode(String.self, forKey: .title)) ?? "",
            type: try? c.decode(String.self, forKey: .type),
            detail: try? c.decode(String.self, forKey: .detail),
            schedule: try? c.decode(String.self, forKey: .schedule),
            command: try? c.decode(String.self, forKey: .command),
            source: try? c.decode(String.self, forKey: .source),
            date: try? c.decode(String.self, forKey: .date),
            time: try? c.decode(String.self, forKey: .time),
            duration: try? c.decode(String.self, forKey: .duration),
            recurrence: try? c.decode(String.self, forKey: .recurrence),
            timezone: try? c.decode(String.self, forKey: .timezone),
            location: try? c.decode(String.self, forKey: .location),
            attendees: (try? c.decode([String].self, forKey: .attendees)) ?? [],
            missingFields: (try? c.decode([String].self, forKey: .missingFields)) ?? [],
            confidence: try? c.decode(Double.self, forKey: .confidence),
            tone: try? c.decode(WidgetTone.self, forKey: .tone)
        )
    }
}

enum WidgetSystemActionKind: String, Equatable {
    case calendarEvent
    case reminder

    var label: String {
        switch self {
        case .calendarEvent:
            return "Calendar Event"
        case .reminder:
            return "Reminder"
        }
    }
}

struct WidgetSystemActionDraft: Equatable {
    var kind: WidgetSystemActionKind
    var title: String
    var startDate: Date
    var endDate: Date?
    var notes: String?
    var location: String?
    var recurrence: String?
    var timezone: String?
    var attendees: [String] = []
}

enum WidgetAppActionKind: String, Equatable {
    case tracker

    var label: String {
        switch self {
        case .tracker:
            return "Tracker"
        }
    }
}

struct WidgetAppActionDraft: Equatable {
    var kind: WidgetAppActionKind
    var title: String
    var prompt: String
    var schedule: BriefingSchedule
    var source: String?
    var command: String?
    var missingFields: [String] = []

    var isReady: Bool { missingFields.isEmpty }
    var confirmation: String { "\(title) · \(schedule.scheduleLabel)" }
}

extension WidgetActionItem {
    var systemActionKind: WidgetSystemActionKind? {
        let normalized = (type ?? "").lowercased()
        if normalized.contains("calendar") || normalized.contains("invite") || normalized.contains("event") {
            return .calendarEvent
        }
        if normalized.contains("reminder") || normalized.contains("remind") {
            return .reminder
        }
        let commandText = (command ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if commandText.hasPrefix("remind me") ||
            commandText.hasPrefix("set a reminder") ||
            commandText.hasPrefix("reminder to") {
            return .reminder
        }
        if commandText.contains("add to calendar") ||
            commandText.contains("calendar invite") ||
            commandText.contains("create a calendar") ||
            commandText.contains("schedule a meeting") {
            return .calendarEvent
        }
        return nil
    }

    func systemActionDraft(now: Date = Date(), calendar: Calendar = .current) -> WidgetSystemActionDraft? {
        guard let kind = systemActionKind else { return nil }
        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        var parsingCalendar = calendar
        if let timeZone = Self.actionTimeZone(from: timezone) {
            parsingCalendar.timeZone = timeZone
        }
        let parsedDate = Self.parsedActionDate(
            date: date,
            time: time,
            schedule: schedule,
            command: command,
            now: now,
            calendar: parsingCalendar
        )
        guard let startDate = parsedDate else { return nil }
        guard Self.hasConcreteTime(date: date, time: time, schedule: schedule, command: command) else {
            return nil
        }
        if kind == .calendarEvent, !Self.hasConcreteDate(date: date, time: time, schedule: schedule, command: command) {
            return nil
        }

        let durationSeconds = Self.durationSeconds(from: duration) ?? 30 * 60
        let endDate = kind == .calendarEvent ? startDate.addingTimeInterval(durationSeconds) : nil
        return WidgetSystemActionDraft(
            kind: kind,
            title: title,
            startDate: startDate,
            endDate: endDate,
            notes: Self.notes(for: self),
            location: widgetActionNonBlank(location),
            recurrence: widgetActionNonBlank(recurrence),
            timezone: widgetActionNonBlank(timezone),
            attendees: attendees
        )
    }

    private static func parsedActionDate(
        date: String?,
        time: String?,
        schedule: String?,
        command: String?,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let pieces = [
            [date, time].compactMap { widgetActionNonBlank($0) }.joined(separator: " "),
            schedule,
            command
        ]
        .compactMap { widgetActionNonBlank($0) }

        for piece in pieces {
            if let parsed = parsedExplicitDate(piece, now: now, calendar: calendar) {
                return parsed
            }
        }
        return nil
    }

    private static func actionTimeZone(from rawValue: String?) -> TimeZone? {
        guard let value = widgetActionNonBlank(rawValue) else { return nil }
        return TimeZone(identifier: value) ?? TimeZone(abbreviation: value)
    }

    private static func parsedExplicitDate(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: text), date > now {
            return date
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: text), date > now {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        for format in ["yyyy-MM-dd h:mm a", "yyyy-MM-dd HH:mm", "yyyy/MM/dd h:mm a", "yyyy/MM/dd HH:mm", "MMM d yyyy h:mm a", "MMMM d yyyy h:mm a"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date > now ? date : nil
            }
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        guard let date = matches.compactMap(\.date).first else { return nil }
        if date > now {
            return date
        }
        if containsAbsoluteDate(text) {
            return nil
        }
        return nextFutureDate(from: date, now: now, calendar: calendar)
    }

    private static func containsAbsoluteDate(_ text: String) -> Bool {
        text.range(of: #"\b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b"#, options: .regularExpression) != nil ||
            text.range(of: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:,?\s+\d{4})?\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func nextFutureDate(from date: Date, now: Date, calendar: Calendar) -> Date? {
        var candidate = date
        for _ in 0..<370 where candidate <= now {
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = next
        }
        return candidate > now ? candidate : nil
    }

    private static func hasConcreteDate(date: String?, time: String?, schedule: String?, command: String?) -> Bool {
        [date, time, schedule, command]
            .compactMap { widgetActionNonBlank($0)?.lowercased() }
            .contains { value in
                value.range(of: #"\b(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#, options: .regularExpression) != nil ||
                    value.range(of: #"\b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b"#, options: .regularExpression) != nil ||
                    value.range(of: #"\b\d{4}-\d{2}-\d{2}t\d{2}:\d{2}"#, options: .regularExpression) != nil ||
                    value.range(of: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2}\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            }
    }

    private static func hasConcreteTime(date: String?, time: String?, schedule: String?, command: String?) -> Bool {
        [date, time, schedule, command]
            .compactMap { widgetActionNonBlank($0)?.lowercased() }
            .contains { value in
                value.range(of: #"\b\d{1,2}(:\d{2})?\s*(am|pm)\b"#, options: .regularExpression) != nil ||
                    value.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil ||
                    value.range(of: #"t\d{2}:\d{2}"#, options: .regularExpression) != nil ||
                    value.range(of: #"\b(noon|midday|midnight)\b"#, options: .regularExpression) != nil
            }
    }

    private static func durationSeconds(from rawValue: String?) -> TimeInterval? {
        guard let rawValue = widgetActionNonBlank(rawValue)?.lowercased() else { return nil }
        let pattern = #"(\d+(?:\.\d+)?)\s*(minutes?|mins?|m|hours?|hrs?|h)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: rawValue, range: NSRange(rawValue.startIndex..<rawValue.endIndex, in: rawValue)),
              match.numberOfRanges >= 3,
              let amountRange = Range(match.range(at: 1), in: rawValue),
              let unitRange = Range(match.range(at: 2), in: rawValue),
              let amount = Double(rawValue[amountRange]) else {
            return nil
        }
        let unit = rawValue[unitRange]
        return unit.hasPrefix("h") ? amount * 3_600 : amount * 60
    }

    private static func notes(for action: WidgetActionItem) -> String? {
        let value = [
            widgetActionNonBlank(action.detail),
            widgetActionNonBlank(action.source).map { "Source: \($0)" },
            widgetActionNonBlank(action.timezone).map { "Timezone: \($0)" },
            action.attendees.isEmpty ? nil : "Attendees: \(action.attendees.joined(separator: ", "))",
            widgetActionNonBlank(action.command).map { "Command: \($0)" },
            action.missingFields.isEmpty ? nil : "Missing fields: \(action.missingFields.joined(separator: ", "))"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

extension WidgetActionItem {
    var appActionKind: WidgetAppActionKind? {
        let normalized = (type ?? "").lowercased()
        if normalized.contains("tracker") ||
            normalized.contains("watcher") ||
            normalized.contains("watch") ||
            normalized.contains("briefing") ||
            normalized.contains("brief") ||
            normalized.contains("digest") ||
            normalized.contains("cron") ||
            normalized.contains("recurring") ||
            normalized.contains("scheduled") ||
            normalized.contains("workflow") ||
            normalized.contains("automation") {
            return .tracker
        }
        if systemActionKind == nil {
            let scheduleText = [
                recurrence,
                schedule,
                time,
                command
            ]
                .compactMap { widgetActionNonBlank($0) }
                .joined(separator: " ")
            if Self.hasTrackerCadence(scheduleText) {
                return .tracker
            }
        }
        return nil
    }

    func appActionDraft() -> WidgetAppActionDraft? {
        guard appActionKind == .tracker else { return nil }
        let title = Self.trackerTitle(from: self)
        guard !title.isEmpty else { return nil }

        let scheduleText = [
            recurrence,
            schedule,
            time,
            command
        ]
            .compactMap { widgetActionNonBlank($0) }
            .joined(separator: " ")

        var missing = missingFields
        if !Self.hasTrackerCadence(scheduleText) &&
            !missing.contains(where: { $0.localizedCaseInsensitiveContains("schedule") || $0.localizedCaseInsensitiveContains("recurrence") }) {
            missing.append("recurrence")
        }

        let schedule = QuickIntentParser.schedule(from: scheduleText)
        return WidgetAppActionDraft(
            kind: .tracker,
            title: title,
            prompt: Self.trackerPrompt(for: self, title: title, schedule: schedule),
            schedule: schedule,
            source: widgetActionNonBlank(source),
            command: widgetActionNonBlank(command),
            missingFields: missing.uniquedNonEmpty()
        )
    }

    private static func trackerTitle(from action: WidgetActionItem) -> String {
        let explicit = widgetActionNonBlank(action.title)
        let subject = widgetActionNonBlank(action.command)
            .map { QuickIntentParser.cleanedTrackerPrompt(from: $0) }
            .flatMap(widgetActionNonBlank)
        let title = explicit ?? subject.map(QuickIntentParser.prettyTrackerTitle(from:)) ?? "Tracker"
        return String(title.prefix(64)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trackerPrompt(for action: WidgetActionItem, title: String, schedule: BriefingSchedule) -> String {
        let commandSubject = widgetActionNonBlank(action.command)
            .map { QuickIntentParser.cleanedTrackerPrompt(from: $0) }
            .flatMap(widgetActionNonBlank)
        let task = commandSubject
            ?? widgetActionNonBlank(action.detail)
            ?? widgetActionNonBlank(action.title)
            ?? title

        var lines = [
            "Run this recurring tracker: \(task)",
            "",
            "Schedule: \(schedule.scheduleLabel).",
            "Return a concise update with what changed, why it matters, any calendar-worthy or tracker-worthy follow-ups, and the next useful action."
        ]
        if let source = widgetActionNonBlank(action.source) {
            lines.append("Source: \(source).")
        }
        if let schedule = widgetActionNonBlank(action.schedule) {
            lines.append("Original schedule cue: \(schedule).")
        }
        if let recurrence = widgetActionNonBlank(action.recurrence) {
            lines.append("Original recurrence cue: \(recurrence).")
        }
        if let time = widgetActionNonBlank(action.time) {
            lines.append("Original time cue: \(time).")
        }
        if !action.missingFields.isEmpty {
            lines.append("Known missing details: \(action.missingFields.joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }

    private static func hasTrackerCadence(_ text: String) -> Bool {
        let normalized = " \(text.lowercased()) "
        if normalized.range(of: #"\b\d{1,2}(:\d{2})?\s*(am|pm)\b"#, options: .regularExpression) != nil { return true }
        if normalized.range(of: #"\bevery\s+\d+\s*(h|hr|hrs|hour|hours|min|mins|minutes)\b"#, options: .regularExpression) != nil { return true }
        let cues = [
            " daily ", " weekday ", " weekdays ", " weekly ", " biweekly ",
            " bi-weekly ", " monthly ", " hourly ",
            " every day ", " every morning ", " every evening ", " every night ",
            " every week ", " every other week ", " every month ", " once a month ",
            " every weekday ", " every hour ", " each day ",
            " each morning ", " nightly ", " morning ", " evening ", " noon "
        ]
        return cues.contains { normalized.contains($0) }
    }
}

private extension Array where Element == String {
    func uniquedNonEmpty() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in self {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }
}

private func widgetActionNonBlank(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

struct WidgetActionPlan: Codable, Hashable {
    var heading: String? = nil
    var summary: String? = nil
    var actions: [WidgetActionItem] = []
}

extension WidgetActionPlan {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            heading: try? c.decode(String.self, forKey: .heading),
            summary: try? c.decode(String.self, forKey: .summary),
            actions: (try? c.decode([WidgetActionItem].self, forKey: .actions)) ?? []
        )
    }
}

struct MessageWidget: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var kind: WidgetKind = .generic
    var title: String? = nil       // meta-strip source label "ETH watcher · threshold alert"
    var freshness: WidgetFreshness? = nil
    var time: String? = nil        // "8:02am", "1h ago"
    var followUp: String? = nil    // micro-composer placeholder, "Why is it dropping?"
    var note: String? = nil        // generic body / fallback prose
    var chart: WidgetChart? = nil
    var metric: WidgetMetric? = nil
    var comparison: WidgetComparison? = nil
    var newsBrief: WidgetNewsBrief? = nil
    var actionPlan: WidgetActionPlan? = nil

    enum CodingKeys: String, CodingKey {
        case id, kind, title, freshness, time
        case followUp = "follow_up"
        case note, chart, metric, comparison
        case newsBrief = "news_brief"
        case actionPlan = "action_plan"
    }
}

extension MessageWidget {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let chart = try? c.decode(WidgetChart.self, forKey: .chart)
        let metric = try? c.decode(WidgetMetric.self, forKey: .metric)
        let comparison = try? c.decode(WidgetComparison.self, forKey: .comparison)
        let news = try? c.decode(WidgetNewsBrief.self, forKey: .newsBrief)
        let actionPlan = try? c.decode(WidgetActionPlan.self, forKey: .actionPlan)

        var kind = (try? c.decode(WidgetKind.self, forKey: .kind)) ?? .generic
        if kind == .generic {
            if chart != nil { kind = .chart }
            else if metric != nil { kind = .metric }
            else if comparison != nil { kind = .comparison }
            else if news != nil { kind = .newsBrief }
            else if actionPlan != nil { kind = .actionPlan }
        }

        self.init(
            id: (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString,
            kind: kind,
            title: try? c.decode(String.self, forKey: .title),
            freshness: try? c.decode(WidgetFreshness.self, forKey: .freshness),
            time: try? c.decode(String.self, forKey: .time),
            followUp: try? c.decode(String.self, forKey: .followUp),
            note: try? c.decode(String.self, forKey: .note),
            chart: chart,
            metric: metric,
            comparison: comparison,
            newsBrief: news,
            actionPlan: actionPlan
        )
    }

    /// True when the payload carries something renderable for its kind.
    var hasRenderableBody: Bool {
        switch kind {
        case .chart: return chart != nil
        case .metric: return metric != nil
        case .comparison: return (comparison?.rows.isEmpty == false)
        case .newsBrief: return (newsBrief?.stories.isEmpty == false)
        case .actionPlan: return (actionPlan?.actions.isEmpty == false)
        case .generic: return (note?.isEmpty == false)
        }
    }

    private static let fenceTokens = ["```near-widget", "```near_widget", "```widget"]

    /// Scans assistant text for the first valid fenced near-widget JSON block.
    /// Returns the parsed widget (or nil) and the text with that block removed.
    /// On any parse failure the original text is returned untouched, so a
    /// malformed block degrades to visible prose rather than being lost.
    /// Earliest fenced opener (any alias) at or after `from`.
    private static func nextFenceOpener(in text: String, from: String.Index) -> (tokenStart: String.Index, tokenEnd: String.Index)? {
        var best: (start: String.Index, end: String.Index)?
        for token in fenceTokens {
            if let r = text.range(of: token, options: .caseInsensitive, range: from..<text.endIndex) {
                if best == nil || r.lowerBound < best!.start {
                    best = (r.lowerBound, r.upperBound)
                }
            }
        }
        return best.map { ($0.start, $0.end) }
    }

    static func extract(from text: String) -> (widget: MessageWidget?, cleanedText: String) {
        var searchStart = text.startIndex
        while let opener = nextFenceOpener(in: text, from: searchStart) {
            guard let closeRange = text.range(of: "```", range: opener.tokenEnd..<text.endIndex) else {
                break // unclosed fence — nothing parseable beyond here
            }
            var jsonString = text[opener.tokenEnd..<closeRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Drop a leading info-string line (e.g. ```near-widget json) before the JSON body.
            if let firstChar = jsonString.first, firstChar != "{", firstChar != "[",
               let newline = jsonString.firstIndex(of: "\n") {
                jsonString = String(jsonString[jsonString.index(after: newline)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let data = jsonString.data(using: .utf8),
               let widget = try? JSONDecoder().decode(MessageWidget.self, from: data),
               widget.hasRenderableBody {
                var cleaned = text
                cleaned.removeSubrange(opener.tokenStart..<closeRange.upperBound)
                return (widget, cleaned.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            searchStart = closeRange.upperBound // skip this block, keep scanning for a valid one
        }
        return (nil, text)
    }

    /// During streaming, hide an as-yet-unclosed near-widget fence so the user
    /// never sees raw JSON mid-stream.
    static func strippedStreamingPreview(_ text: String) -> String {
        // Remove a fully-closed widget block if one already landed mid-stream,
        // so its raw JSON never shows.
        let withoutClosed = extract(from: text).cleanedText
        // Then hide a still-open trailing fence.
        for token in fenceTokens {
            if let openRange = withoutClosed.range(of: token, options: .caseInsensitive),
               withoutClosed.range(of: "```", range: openRange.upperBound..<withoutClosed.endIndex) == nil {
                return String(withoutClosed[withoutClosed.startIndex..<openRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return withoutClosed
    }
}

#if DEBUG
extension MessageWidget {
    static var demoChart: MessageWidget {
        MessageWidget(
            kind: .chart,
            title: "ETH watcher · threshold alert",
            freshness: .fresh,
            time: "1h ago",
            followUp: "Why is it dropping?",
            chart: WidgetChart(
                label: "ETH / USD",
                value: "$3,124",
                delta: "−$74.20 (−2.3%)",
                trend: .down,
                points: [3210, 3198, 3205, 3180, 3192, 3164, 3150, 3158, 3132, 3124],
                caption: "Threshold $3,180 broken at 9:47am",
                timeframe: "past 1h"
            )
        )
    }

    static var demoMetric: MessageWidget {
        MessageWidget(
            kind: .metric,
            title: "Portfolio",
            freshness: .fresh,
            time: "just now",
            followUp: "What changed today?",
            metric: WidgetMetric(
                label: "Total value",
                value: "$48,210",
                delta: "+1.8% today",
                trend: .up,
                caption: "3 positions · last synced 2m ago"
            )
        )
    }

    static var demoComparison: MessageWidget {
        MessageWidget(
            kind: .comparison,
            title: "Comparison · TEE hardware",
            freshness: .stale,
            time: "from yesterday's chat",
            followUp: "Which should we ship on?",
            comparison: WidgetComparison(
                subtitle: "SEV-SNP vs TDX",
                columns: ["SEV-SNP", "TDX"],
                rows: [
                    WidgetComparisonRow(label: "Memory encryption", cells: [
                        WidgetComparisonCell(text: "AES-128 XEX", tone: .good),
                        WidgetComparisonCell(text: "AES-128 XTS", tone: .good)
                    ]),
                    WidgetComparisonRow(label: "Attestation", cells: [
                        WidgetComparisonCell(text: "VCEK + report", tone: .neutral),
                        WidgetComparisonCell(text: "Quote + TDREPORT", tone: .neutral)
                    ]),
                    WidgetComparisonRow(label: "VM isolation", cells: [
                        WidgetComparisonCell(text: "RMP-based", tone: .neutral),
                        WidgetComparisonCell(text: "Stage-2 paging", tone: .neutral)
                    ]),
                    WidgetComparisonRow(label: "Live migration", cells: [
                        WidgetComparisonCell(text: "preview", tone: .warn),
                        WidgetComparisonCell(text: "—", tone: .off)
                    ])
                ]
            )
        )
    }

    static var demoNewsBrief: MessageWidget {
        MessageWidget(
            kind: .newsBrief,
            title: "Daily news brief",
            freshness: .fresh,
            time: "8:02am",
            followUp: "Drill into the ceasefire story…",
            newsBrief: WidgetNewsBrief(
                heading: "Today · 3 stories",
                stories: [
                    WidgetNewsStory(title: "US–Iran ceasefire under strain", tag: "Conflict", sources: [
                        WidgetNewsSource(label: "W", color: "#ff7e1c", domain: "wsj.com"),
                        WidgetNewsSource(label: "A", color: "#000000", domain: "apnews.com")
                    ]),
                    WidgetNewsStory(title: "Israel strikes Beirut as Lebanon conflict escalates", tag: "Conflict", sources: [
                        WidgetNewsSource(label: "B", color: "#CC0000", domain: "bbc.com")
                    ]),
                    WidgetNewsStory(title: "Oil down on talks of reopening Hormuz", tag: "Markets", sources: [
                        WidgetNewsSource(label: "R", color: "#FF6B35", domain: "reuters.com"),
                        WidgetNewsSource(label: "B", color: "#000000", domain: "bloomberg.com")
                    ])
                ]
            )
        )
    }

    static var demoAll: [MessageWidget] {
        [demoNewsBrief, demoChart, demoComparison, demoMetric]
    }
}
#endif
