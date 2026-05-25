import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct AppConfiguration {
    var baseURL: URL
    var callbackScheme: String
    var callbackURL: URL

    static let production = AppConfiguration(
        baseURL: URL(string: "https://private.near.ai")!,
        callbackScheme: "nearprivatechat",
        callbackURL: URL(string: "nearprivatechat://auth")!
    )
}

struct AppDeepLinkAction: Equatable {
    static let maxDraftCharacters = 2_000

    enum Route: String, Equatable {
        case ask
        case agent
        case verified
    }

    var route: Route
    var sourceMode: ChatSourceMode?
    var researchMode: Bool
    var draft: String?

    static func parse(_ url: URL, callbackScheme: String = AppConfiguration.production.callbackScheme) -> AppDeepLinkAction? {
        guard url.scheme == callbackScheme,
              url.host?.lowercased() != "auth" else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") }
        )
        let command = normalizedCommand(from: url)
        let route = route(from: query["route"] ?? query["mode"] ?? command)

        guard command == "new" ||
              command == "ask" ||
              command == "agent" ||
              command == "ironclaw" ||
              command == "verified" ||
              command == "private" ||
              command == "chat" ||
              route != nil else {
            return nil
        }

        return AppDeepLinkAction(
            route: route ?? .ask,
            sourceMode: query["source"].flatMap(ChatSourceMode.init(rawValue:)),
            researchMode: boolValue(query["research"]),
            draft: cappedDraft(query["prompt"] ?? query["draft"])
        )
    }

    private static func normalizedCommand(from url: URL) -> String {
        let host = url.host?.lowercased()
        let firstPathComponent = url.pathComponents
            .first(where: { $0 != "/" })?
            .lowercased()

        if host == "chat", firstPathComponent == "new" {
            return "new"
        }
        return host ?? firstPathComponent ?? ""
    }

    private static func route(from value: String?) -> Route? {
        switch value?.lowercased() {
        case "agent", "ironclaw", "mobile", "workstation":
            return .agent
        case "verified", "private", "tee", "near-private":
            return .verified
        case "ask", "chat", "new":
            return .ask
        default:
            return nil
        }
    }

    private static func boolValue(_ value: String?) -> Bool {
        switch value?.lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cappedDraft(_ value: String?) -> String? {
        guard let draft = nonEmpty(value) else { return nil }
        return String(draft.prefix(maxDraftCharacters))
    }
}

enum OAuthProvider: String, CaseIterable, Identifiable {
    case near
    case google
    case github

    var id: String { rawValue }

    var title: String {
        switch self {
        case .near: "Continue with NEAR"
        case .google: "Continue with Google"
        case .github: "Continue with GitHub"
        }
    }

    var symbolName: String {
        switch self {
        case .near: "hexagon"
        case .google: "g.circle"
        case .github: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct AuthSession: Codable, Equatable {
    var token: String
    var sessionID: String
    var expiresAt: String?
    var isNewUser: Bool
}

struct UserProfile: Decodable, Identifiable, Hashable {
    struct User: Decodable, Hashable {
        let id: String
        let email: String?
        let name: String?
        let avatarURL: String?

        enum CodingKeys: String, CodingKey {
            case id
            case email
            case name
            case avatarURL = "avatar_url"
        }
    }

    struct LinkedAccount: Decodable, Hashable {
        let provider: String
        let linkedAt: String?

        enum CodingKeys: String, CodingKey {
            case provider
            case linkedAt = "linked_at"
        }
    }

    let user: User
    let linkedAccounts: [LinkedAccount]

    var id: String { user.id }

    enum CodingKeys: String, CodingKey {
        case user
        case linkedAccounts = "linked_accounts"
    }
}

struct UserSettingsResponse: Decodable, Hashable {
    let userID: String?
    let settings: RemoteUserSettings

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case settings
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        settings = try container.decodeIfPresent(RemoteUserSettings.self, forKey: .settings) ??
            container.decodeIfPresent(RemoteUserSettings.self, forKey: .content) ??
            RemoteUserSettings()
    }
}

struct RemoteUserSettings: Codable, Hashable {
    var notification: Bool? = nil
    var systemPrompt: String? = nil
    var webSearch: Bool? = nil
    var appearance: String? = nil
    var largeTextAsFile: Bool? = nil
    var temperature: Double? = nil
    var topP: Double? = nil
    var maxTokens: Int? = nil

    enum CodingKeys: String, CodingKey {
        case notification
        case systemPrompt = "system_prompt"
        case webSearch = "web_search"
        case appearance
        case largeTextAsFile
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
    }
}

enum ModelReasoningEffort: String, CaseIterable, Codable, Identifiable, Hashable {
    case automatic
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Auto"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Let the provider choose the reasoning budget."
        case .low:
            return "Favor speed and lower token spend."
        case .medium:
            return "Balance quality, latency, and token spend."
        case .high:
            return "Spend more reasoning for harder prompts."
        }
    }

    var apiValue: String? {
        switch self {
        case .automatic: nil
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        }
    }
}

struct AdvancedModelParams: Codable, Hashable {
    var temperature: Double?
    var topP: Double?
    var maxTokens: Int?
    var reasoningEffort: ModelReasoningEffort

    static let defaults = AdvancedModelParams()

    init(
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        reasoningEffort: ModelReasoningEffort = .automatic
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.reasoningEffort = reasoningEffort
    }

    enum CodingKeys: String, CodingKey {
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case reasoningEffort = "reasoning_effort"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        topP = try container.decodeIfPresent(Double.self, forKey: .topP)
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
        reasoningEffort = try container.decodeIfPresent(ModelReasoningEffort.self, forKey: .reasoningEffort) ?? .automatic
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        if reasoningEffort != .automatic {
            try container.encode(reasoningEffort, forKey: .reasoningEffort)
        }
    }

    var isDefault: Bool {
        temperature == nil && topP == nil && maxTokens == nil && reasoningEffort == .automatic
    }

    var sanitized: AdvancedModelParams {
        AdvancedModelParams(
            temperature: temperature.map { min(max($0, 0), 2) },
            topP: topP.map { min(max($0, 0), 1) },
            maxTokens: maxTokens.map { min(max($0, 1), 200_000) },
            reasoningEffort: reasoningEffort
        )
    }

    var summary: String {
        var parts: [String] = []
        if let temperature {
            parts.append("temp \(Self.format(temperature))")
        }
        if let topP {
            parts.append("top-p \(Self.format(topP))")
        }
        if let maxTokens {
            parts.append("\(maxTokens) max")
        }
        if reasoningEffort != .automatic {
            parts.append("reasoning \(reasoningEffort.title.lowercased())")
        }
        return parts.isEmpty ? "Defaults" : parts.joined(separator: " · ")
    }

    private static func format(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        return formatted
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

enum ChatSourceMode: String, CaseIterable, Codable, Identifiable, Hashable {
    case auto
    case web
    case links
    case files
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .web: "Web"
        case .links: "Links"
        case .files: "Files"
        case .all: "Project"
        }
    }

    var shortTitle: String {
        switch self {
        case .auto: "Auto"
        case .web: "Web"
        case .links: "Links"
        case .files: "Files"
        case .all: "Project"
        }
    }

    var symbolName: String {
        switch self {
        case .auto: "sparkles"
        case .web: "globe"
        case .links: "link"
        case .files: "folder"
        case .all: "rectangle.3.group"
        }
    }

    var detail: String {
        switch self {
        case .auto: "Use files and web when helpful."
        case .web: "Use live web first."
        case .links: "Use saved source links."
        case .files: "Use project and prompt files."
        case .all: "Use live sources, project files, and saved links."
        }
    }
}

enum ChatRouteKind: String, Hashable {
    case nearPrivate
    case nearCloud
    case ironclawMobile
    case ironclawHosted
}

enum ChatFocusState: String, Hashable {
    case auto
    case web
    case links
    case files
    case project
    case research
}

enum ChatWebUsePolicy: String, Hashable {
    case never
    case always
    case whenHelpful
    case whenFreshRequested

    var isEnabledByDefault: Bool {
        switch self {
        case .always, .whenHelpful:
            return true
        case .never, .whenFreshRequested:
            return false
        }
    }

    func resolves(benefitsFromSearch: Bool, needsFreshFacts: Bool) -> Bool {
        switch self {
        case .never:
            return false
        case .always:
            return true
        case .whenHelpful:
            return benefitsFromSearch || needsFreshFacts
        case .whenFreshRequested:
            return needsFreshFacts
        }
    }
}

struct ChatSourceRoutingSemantics: Hashable {
    let route: ChatRouteKind
    let focus: ChatFocusState
    let modelNativeWebToolPolicy: ChatWebUsePolicy
    let appWebGroundingPolicy: ChatWebUsePolicy
    let attachesSavedLinkSourcePack: Bool
    let attachesProjectFileSourcePack: Bool
    let attachesPromptFiles: Bool

    var isResearch: Bool {
        focus == .research
    }

    var modelNativeWebToolEnabledByDefault: Bool {
        modelNativeWebToolPolicy.isEnabledByDefault
    }

    static func evaluate(
        sourceMode: ChatSourceMode,
        researchModeEnabled: Bool,
        webSearchEnabled: Bool,
        route: ChatRouteKind
    ) -> ChatSourceRoutingSemantics {
        let focus: ChatFocusState = if researchModeEnabled {
            .research
        } else {
            switch sourceMode {
            case .auto: .auto
            case .web: .web
            case .links: .links
            case .files: .files
            case .all: .project
            }
        }
        let sourceWebPolicy = webPolicy(for: focus, webSearchEnabled: webSearchEnabled)
        let appGroundingPolicy = appGroundingPolicy(for: focus, webSearchEnabled: webSearchEnabled)
        let supportsNativeWebTool = route == .nearPrivate || route == .ironclawMobile
        let supportsAppGrounding = route == .nearCloud || route == .ironclawMobile || route == .ironclawHosted

        return ChatSourceRoutingSemantics(
            route: route,
            focus: focus,
            modelNativeWebToolPolicy: supportsNativeWebTool ? sourceWebPolicy : .never,
            appWebGroundingPolicy: supportsAppGrounding ? appGroundingPolicy : .never,
            attachesSavedLinkSourcePack: focus == .auto || focus == .links || focus == .project || focus == .research,
            attachesProjectFileSourcePack: focus == .auto || focus == .files || focus == .project || focus == .research,
            attachesPromptFiles: true
        )
    }

    private static func webPolicy(for focus: ChatFocusState, webSearchEnabled: Bool) -> ChatWebUsePolicy {
        switch focus {
        case .auto:
            return webSearchEnabled ? .whenHelpful : .never
        case .web, .project, .research:
            return .always
        case .links:
            return .whenFreshRequested
        case .files:
            return .never
        }
    }

    private static func appGroundingPolicy(for focus: ChatFocusState, webSearchEnabled: Bool) -> ChatWebUsePolicy {
        guard webSearchEnabled else { return .never }
        switch focus {
        case .web, .research:
            return .always
        case .project:
            return .whenFreshRequested
        case .links:
            return .whenFreshRequested
        case .auto, .files:
            return .never
        }
    }
}

struct IronclawSkillProfile: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let symbolName: String
    let keywords: [String]
}

enum IronclawSkillCatalog {
    static let all: [IronclawSkillProfile] = [
        IronclawSkillProfile(
            id: "coding",
            title: "Coding",
            summary: "Edit files, inspect code, and make focused patches.",
            symbolName: "chevron.left.forwardslash.chevron.right",
            keywords: ["code", "build", "implement", "fix", "patch", "refactor", "write software", "edit"]
        ),
        IronclawSkillProfile(
            id: "local-test",
            title: "Local Test",
            summary: "Run focused tests, builds, and smoke checks.",
            symbolName: "checkmark.seal",
            keywords: ["test", "qa", "smoke", "build", "run", "verify", "regression"]
        ),
        IronclawSkillProfile(
            id: "github-workflow",
            title: "GitHub",
            summary: "Handle issues, PRs, CI failures, and repo handoff.",
            symbolName: "arrow.triangle.branch",
            keywords: ["github", "issue", "pull request", " pr ", "/pull/", "/issues/", "ci", "branch"]
        ),
        IronclawSkillProfile(
            id: "code-review",
            title: "Code Review",
            summary: "Find correctness bugs, regressions, and missing tests.",
            symbolName: "text.magnifyingglass",
            keywords: ["code review", "review this pr", "review the diff", "audit repo", "bugs", "regression"]
        ),
        IronclawSkillProfile(
            id: "security-review",
            title: "Security Review",
            summary: "Audit auth, secrets, SSRF, injection, and permissions.",
            symbolName: "lock.shield",
            keywords: ["security", "audit", "vulnerability", "secret", "auth", "ssrf", "xss", "injection"]
        ),
        IronclawSkillProfile(
            id: "qa-review",
            title: "QA Review",
            summary: "Plan and run product QA with repro-ready evidence.",
            symbolName: "checklist",
            keywords: ["qa", "quality", "manual test", "test plan", "browser test", "repro"]
        ),
        IronclawSkillProfile(
            id: "project-setup",
            title: "Project Setup",
            summary: "Turn a repo or new idea into a tracked workspace.",
            symbolName: "folder.badge.gearshape",
            keywords: ["setup", "set up", "clone", "bootstrap", "new project", "repo"]
        ),
        IronclawSkillProfile(
            id: "llm-council",
            title: "LLM Council",
            summary: "Ask multiple models and synthesize agreement.",
            symbolName: "square.grid.2x2",
            keywords: ["council", "multiple models", "compare models", "second opinion", "consensus", "vote"]
        ),
        IronclawSkillProfile(
            id: "product-prioritization",
            title: "Product Prioritization",
            summary: "Rank product work by impact, evidence, and effort.",
            symbolName: "chart.bar",
            keywords: ["prioritize", "roadmap", "product", "feature", "rank", "strategy"]
        ),
        IronclawSkillProfile(
            id: "decision-capture",
            title: "Decision Capture",
            summary: "Record decisions, rationale, alternatives, and follow-ups.",
            symbolName: "bookmark",
            keywords: ["decision", "decisions", "adr", "capture this", "record", "rationale"]
        ),
        IronclawSkillProfile(
            id: "commitment-triage",
            title: "Commitment Triage",
            summary: "Extract obligations, owners, deadlines, and next steps.",
            symbolName: "person.crop.circle.badge.checkmark",
            keywords: ["commitment", "follow up", "deadline", "owner", "delegate", "nudge"]
        ),
        IronclawSkillProfile(
            id: "portfolio",
            title: "Portfolio",
            summary: "Inspect DeFi positions and NEAR intent opportunities.",
            symbolName: "chart.pie",
            keywords: ["wallet", "portfolio", "yield", "rebalance", "defi", "near intent", "trading"]
        )
    ]

    static func suggestedSkills(for text: String, limit: Int = 4) -> [IronclawSkillProfile] {
        let lowercased = text.lowercased()
        let scored = all.map { skill -> (skill: IronclawSkillProfile, score: Int) in
            let score = skill.keywords.reduce(0) { partial, keyword in
                partial + (lowercased.contains(keyword) ? 1 : 0)
            }
            return (skill, score)
        }
        let matches = scored
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.skill.title < rhs.skill.title
                }
                return lhs.score > rhs.score
            }
            .map(\.skill)

        if !matches.isEmpty {
            return Array(matches.prefix(limit))
        }

        if lowercased.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(all.filter { ["coding", "github-workflow", "local-test"].contains($0.id) }.prefix(limit))
        }

        return Array(all.filter { ["coding", "local-test", "project-setup"].contains($0.id) }.prefix(limit))
    }

    static func promptSection(for text: String) -> String {
        let skills = suggestedSkills(for: text, limit: 5)
        guard !skills.isEmpty else { return "" }
        let lines = skills.map { "- \($0.id): \($0.summary)" }.joined(separator: "\n")
        return """
        IronClaw skills to consider:
        \(lines)

        Select the useful skills internally. Do not print the routing unless the user asks how the agent chose its approach.
        """
    }
}

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

enum UserSetupUseCase: String, CaseIterable, Codable, Identifiable, Hashable {
    case privateChat
    case research
    case buildAgents
    case teamProjects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateChat: "Private Chat"
        case .research: "Research"
        case .buildAgents: "Build Agents"
        case .teamProjects: "Projects"
        }
    }

    var subtitle: String {
        switch self {
        case .privateChat: "Fast private answers, web when useful."
        case .research: "Current sources, citations, and memos."
        case .buildAgents: "IronClaw for code, git, tests, and repo work."
        case .teamProjects: "Files, links, saved outputs, and shared context."
        }
    }

    var symbolName: String {
        switch self {
        case .privateChat: "lock.shield"
        case .research: "doc.text.magnifyingglass"
        case .buildAgents: "terminal"
        case .teamProjects: "folder.badge.gearshape"
        }
    }

    var starterProjectName: String? {
        switch self {
        case .privateChat:
            return nil
        case .research:
            return "Research Room"
        case .buildAgents:
            return "Agent Workspace"
        case .teamProjects:
            return "Project Workspace"
        }
    }

    var starterInstructions: String {
        switch self {
        case .privateChat:
            return "Keep answers direct, private, and practical. Use live web only when the question depends on current facts."
        case .research:
            return "Prioritize dated sources, citations, contradictions, and a concise recommendation. Save strong outputs as project notes."
        case .buildAgents:
            return "Use IronClaw skill behavior for coding, project setup, local tests, GitHub work, code review, security review, QA, LLM Council, decision capture, commitments, and product prioritization. Do not commit or push unless explicitly requested."
        case .teamProjects:
            return "Use project files, saved source links, memory, and saved outputs before broad web. Keep context tidy and ask only when a missing source blocks progress."
        }
    }

    var starterPrompt: String {
        switch self {
        case .privateChat:
            return "Help me think through the most important question I should ask first."
        case .research:
            return "Create a sourced research brief on the latest important AI developments, with dates, citations, and a short recommendation."
        case .buildAgents:
            return "Plan a first IronClaw agent mission that can inspect a repo, make a small safe code change, and run focused tests."
        case .teamProjects:
            return "Help me set up this project workspace: what files, links, instructions, and first chat should I add?"
        }
    }
}

extension Array where Element == UserSetupUseCase {
    var setupOrderedUnique: [UserSetupUseCase] {
        let selected = Set(self)
        let ordered = UserSetupUseCase.allCases.filter { selected.contains($0) }
        return ordered.isEmpty ? [.privateChat] : ordered
    }

    var setupPrimaryUseCase: UserSetupUseCase {
        let selected = Set(setupOrderedUnique)
        if selected.contains(.buildAgents) {
            return .buildAgents
        }
        if selected.contains(.research) {
            return .research
        }
        if selected.contains(.teamProjects) {
            return .teamProjects
        }
        return .privateChat
    }
}

enum UserSetupContextStyle: String, CaseIterable, Codable, Identifiable, Hashable {
    case simple
    case project
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: "Automatic"
        case .project: "Project Memory"
        case .files: "Files First"
        }
    }

    var subtitle: String {
        switch self {
        case .simple: "Use the chat, web, and saved context only when it helps."
        case .project: "Keep links, notes, instructions, and files together."
        case .files: "Prioritize attached and project files before anything else."
        }
    }

    var symbolName: String {
        switch self {
        case .simple: "sparkles"
        case .project: "folder"
        case .files: "paperclip"
        }
    }

    var sourceMode: ChatSourceMode {
        switch self {
        case .simple: .auto
        case .project: .all
        case .files: .files
        }
    }

    init(sourceMode: ChatSourceMode) {
        switch sourceMode {
        case .files:
            self = .files
        case .all, .links:
            self = .project
        case .auto, .web:
            self = .simple
        }
    }
}

enum UserSetupExperienceMode: String, CaseIterable, Codable, Identifiable, Hashable {
    case beginner
    case power

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner: "Beginner"
        case .power: "Power"
        }
    }

    var subtitle: String {
        switch self {
        case .beginner: "Start with private chat, sources, and proof. Advanced routes stay available later."
        case .power: "Show agents, Council, Cloud models, and developer controls from day one."
        }
    }

    var symbolName: String {
        switch self {
        case .beginner: "sparkles"
        case .power: "bolt"
        }
    }
}

enum UserSetupStarterPreset: String, CaseIterable, Codable, Identifiable, Hashable {
    case privateQuestion
    case researchBrief
    case agentMission

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateQuestion: "Private question"
        case .researchBrief: "Research brief"
        case .agentMission: "Agent mission"
        }
    }

    var prompt: String {
        switch self {
        case .privateQuestion: "Help me think through a private question."
        case .researchBrief: "Create a sourced brief on the latest developments in AI."
        case .agentMission: "Plan a phone-launched agent task for a repo or research project."
        }
    }

    var symbolName: String {
        switch self {
        case .privateQuestion: "lock.shield"
        case .researchBrief: "text.magnifyingglass"
        case .agentMission: "terminal"
        }
    }

    var useCase: UserSetupUseCase {
        switch self {
        case .privateQuestion: .privateChat
        case .researchBrief: .research
        case .agentMission: .buildAgents
        }
    }

    var contextStyle: UserSetupContextStyle {
        switch self {
        case .privateQuestion: .simple
        case .researchBrief, .agentMission: .project
        }
    }

    var wantsIronclaw: Bool {
        self == .agentMission
    }

    var wantsCouncil: Bool {
        self == .researchBrief
    }
}

struct UserSetupProfile: Codable, Hashable {
    var useCase: UserSetupUseCase {
        didSet {
            guard oldValue != useCase, !useCases.contains(useCase) else { return }
            useCases = [useCase]
        }
    }
    var useCases: [UserSetupUseCase]
    var goalText: String
    var contextStyle: UserSetupContextStyle
    var wantsWeb: Bool
    var wantsIronclaw: Bool
    var wantsCouncil: Bool
    var experienceMode: UserSetupExperienceMode

    init(
        useCase: UserSetupUseCase,
        contextStyle: UserSetupContextStyle,
        wantsWeb: Bool,
        wantsIronclaw: Bool,
        wantsCouncil: Bool,
        useCases: [UserSetupUseCase]? = nil,
        goalText: String = "",
        experienceMode: UserSetupExperienceMode = .beginner
    ) {
        let normalizedUseCases = (useCases ?? [useCase]).setupOrderedUnique
        self.useCases = normalizedUseCases
        self.useCase = normalizedUseCases.setupPrimaryUseCase
        self.goalText = String(goalText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
        self.contextStyle = contextStyle
        self.wantsWeb = wantsWeb
        self.wantsIronclaw = wantsIronclaw
        self.wantsCouncil = wantsCouncil
        self.experienceMode = experienceMode
    }

    enum CodingKeys: String, CodingKey {
        case useCase
        case useCases
        case goalText
        case contextStyle
        case wantsWeb
        case wantsIronclaw
        case wantsCouncil
        case experienceMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedUseCase = try container.decodeIfPresent(UserSetupUseCase.self, forKey: .useCase) ?? .privateChat
        let storedUseCases = try container.decodeIfPresent([UserSetupUseCase].self, forKey: .useCases)
        let normalizedUseCases = (storedUseCases ?? [storedUseCase]).setupOrderedUnique
        useCases = normalizedUseCases
        useCase = normalizedUseCases.setupPrimaryUseCase
        goalText = try container.decodeIfPresent(String.self, forKey: .goalText) ?? ""
        contextStyle = try container.decodeIfPresent(UserSetupContextStyle.self, forKey: .contextStyle) ?? .simple
        wantsWeb = try container.decodeIfPresent(Bool.self, forKey: .wantsWeb) ?? false
        wantsIronclaw = try container.decodeIfPresent(Bool.self, forKey: .wantsIronclaw) ?? false
        wantsCouncil = try container.decodeIfPresent(Bool.self, forKey: .wantsCouncil) ?? false
        experienceMode = try container.decodeIfPresent(UserSetupExperienceMode.self, forKey: .experienceMode) ?? .beginner
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(useCase, forKey: .useCase)
        try container.encode(useCases.setupOrderedUnique, forKey: .useCases)
        try container.encode(goalText, forKey: .goalText)
        try container.encode(contextStyle, forKey: .contextStyle)
        try container.encode(wantsWeb, forKey: .wantsWeb)
        try container.encode(wantsIronclaw, forKey: .wantsIronclaw)
        try container.encode(wantsCouncil, forKey: .wantsCouncil)
        try container.encode(experienceMode, forKey: .experienceMode)
    }

    var normalizedForDefaults: UserSetupProfile {
        var profile = self
        profile.useCases = useCases.setupOrderedUnique
        profile.useCase = profile.useCases.setupPrimaryUseCase
        profile.goalText = normalizedGoalText
        return profile
    }

    var normalizedGoalText: String {
        String(goalText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
    }

    var setupStarterProjectName: String? {
        if useCases.contains(.buildAgents) {
            return UserSetupUseCase.buildAgents.starterProjectName
        }
        if useCases.contains(.research) {
            return UserSetupUseCase.research.starterProjectName
        }
        if useCases.contains(.teamProjects) {
            return UserSetupUseCase.teamProjects.starterProjectName
        }
        return contextStyle == .project ? "Project Workspace" : nil
    }

    var setupProjectInstructions: String {
        let primaryInstructions = useCases.setupPrimaryUseCase.starterInstructions
        let goal = normalizedGoalText
        guard !goal.isEmpty else { return primaryInstructions }
        return """
        \(primaryInstructions)

        Setup goal: \(goal)
        """
    }

    var firstRunDraft: String? {
        let goal = normalizedGoalText
        if !goal.isEmpty, wantsIronclaw {
            return "Plan the first IronClaw agent mission for this goal: \(goal)"
        }
        if !goal.isEmpty, useCases.contains(.research) {
            return "Create a sourced research brief for this goal: \(goal)"
        }
        if !goal.isEmpty, useCases.contains(.buildAgents) {
            return "Plan the first build or repo task for this goal: \(goal)"
        }
        if !goal.isEmpty, useCases.contains(.teamProjects) || contextStyle != .simple {
            return "Help me organize this project and next actions for this goal: \(goal)"
        }
        if !goal.isEmpty {
            return "Help me with this goal: \(goal)"
        }
        return useCases.setupPrimaryUseCase.starterPrompt
    }

    mutating func toggleUseCase(_ useCase: UserSetupUseCase) {
        var next = useCases.setupOrderedUnique
        if next.contains(useCase) {
            guard next.count > 1 else { return }
            next.removeAll { $0 == useCase }
        } else {
            next.append(useCase)
        }
        useCases = next.setupOrderedUnique
        self.useCase = useCases.setupPrimaryUseCase
    }

    mutating func applyStarterPreset(_ preset: UserSetupStarterPreset) {
        useCase = preset.useCase
        useCases = [preset.useCase]
        goalText = preset.prompt
        contextStyle = preset.contextStyle
        wantsIronclaw = preset.wantsIronclaw
        wantsCouncil = preset.wantsCouncil
    }

    static let defaults = UserSetupProfile(
        useCase: .privateChat,
        contextStyle: .simple,
        wantsWeb: false,
        wantsIronclaw: false,
        wantsCouncil: false,
        useCases: [.privateChat],
        goalText: "",
        experienceMode: .beginner
    )
}

enum AppSetupModelRoute: String, Codable, Hashable {
    case privateModel
    case council
    case ironclaw

    var title: String {
        switch self {
        case .privateModel: "Private model"
        case .council: "LLM Council"
        case .ironclaw: "IronClaw agent"
        }
    }

    var symbolName: String {
        switch self {
        case .privateModel: "lock.shield"
        case .council: "square.grid.2x2"
        case .ironclaw: "terminal"
        }
    }
}

struct AppSetupReadinessSnapshot: Codable, Hashable {
    var modelCatalogLoaded: Bool
    var privateModelAvailable: Bool
    var defaultCouncilModelCount: Int
    var ironclawMobileAvailable: Bool
    var hostedIronclawAvailable: Bool
    var nearCloudKeyConfigured: Bool

    var councilReady: Bool {
        modelCatalogLoaded && defaultCouncilModelCount > 1
    }

    static let optimistic = AppSetupReadinessSnapshot(
        modelCatalogLoaded: true,
        privateModelAvailable: true,
        defaultCouncilModelCount: 3,
        ironclawMobileAvailable: true,
        hostedIronclawAvailable: true,
        nearCloudKeyConfigured: true
    )
}

struct AppSetupPlan: Codable, Hashable, Identifiable {
    var id: String
    var modelRoute: AppSetupModelRoute
    var focusMode: ChatSourceMode
    var focusBehavior: String
    var starterProjectName: String?
    var agentEnabled: Bool
    var councilEnabled: Bool
    var expectedFirstAction: String
    var goalText: String
    var firstRunDraft: String?
    var readinessStatus: String
    var experienceSummary: String

    init(profile: UserSetupProfile, readiness: AppSetupReadinessSnapshot = .optimistic) {
        let profile = profile.normalizedForDefaults
        let usesIronclaw = profile.wantsIronclaw && readiness.ironclawMobileAvailable
        let usesCouncil = !usesIronclaw && profile.wantsCouncil && readiness.councilReady
        modelRoute = usesIronclaw ? .ironclaw : (usesCouncil ? .council : .privateModel)
        focusMode = profile.contextStyle.sourceMode
        focusBehavior = Self.focusBehavior(for: profile)
        starterProjectName = profile.setupStarterProjectName
        agentEnabled = profile.wantsIronclaw
        councilEnabled = profile.wantsCouncil
        expectedFirstAction = Self.expectedFirstAction(for: profile, readiness: readiness, modelRoute: modelRoute)
        goalText = profile.goalText
        firstRunDraft = profile.firstRunDraft
        readinessStatus = Self.readinessStatus(for: profile, readiness: readiness, modelRoute: modelRoute)
        experienceSummary = profile.experienceMode == .power
            ? "Power mode keeps advanced routes visible."
            : "Beginner mode starts simple; power routes remain available later."
        id = [
            profile.useCases.map(\.rawValue).joined(separator: "+"),
            profile.experienceMode.rawValue,
            profile.contextStyle.rawValue,
            profile.wantsWeb ? "web" : "noweb",
            profile.wantsIronclaw ? "agent" : "noagent",
            profile.wantsCouncil ? "council" : "nocouncil",
            modelRoute.rawValue
        ].joined(separator: "-")
    }

    static let previews: [AppSetupPlan] = UserSetupUseCase.allCases.map { useCase in
        var profile = UserSetupProfile.defaults
        profile.useCase = useCase
        profile.useCases = [useCase]
        switch useCase {
        case .privateChat:
            profile.contextStyle = .simple
            profile.wantsCouncil = false
            profile.wantsIronclaw = false
        case .research:
            profile.contextStyle = .project
            profile.wantsCouncil = true
            profile.wantsIronclaw = false
        case .buildAgents:
            profile.contextStyle = .project
            profile.wantsCouncil = false
            profile.wantsIronclaw = true
        case .teamProjects:
            profile.contextStyle = .project
            profile.wantsCouncil = false
            profile.wantsIronclaw = false
        }
        return AppSetupPlan(profile: profile)
    }

    private static func focusBehavior(for profile: UserSetupProfile) -> String {
        let goal = profile.goalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !goal.isEmpty {
            return "Starts from your goal, then routes model, context, and web as needed."
        }
        switch profile.contextStyle {
        case .simple:
            return profile.wantsWeb ? "Auto routes private chat and live web when useful." : "Keeps answers private and avoids live web by default."
        case .project:
            return profile.wantsWeb ? "Uses project sources, saved links, files, and live web." : "Uses project sources and files before broader context."
        case .files:
            return "Prioritizes attached and project files before broader sources."
        }
    }

    private static func expectedFirstAction(
        for profile: UserSetupProfile,
        readiness: AppSetupReadinessSnapshot,
        modelRoute: AppSetupModelRoute
    ) -> String {
        let goal = profile.goalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !goal.isEmpty {
            return "Start from your goal"
        }
        if profile.wantsIronclaw, !readiness.ironclawMobileAvailable {
            return "Review agent setup"
        }
        if profile.wantsCouncil, !readiness.councilReady {
            return readiness.modelCatalogLoaded
                ? "Start private chat; Council needs models"
                : "Start private chat while models load"
        }
        switch profile.useCase {
        case .privateChat:
            return "Ask a private question"
        case .research:
            return "Start a research brief"
        case .buildAgents:
            return "Launch an agent mission"
        case .teamProjects:
            return "Create a project workspace"
        }
    }

    private static func readinessStatus(
        for profile: UserSetupProfile,
        readiness: AppSetupReadinessSnapshot,
        modelRoute: AppSetupModelRoute
    ) -> String {
        if profile.wantsIronclaw, !readiness.ironclawMobileAvailable {
            return "Agent route needs IronClaw Mobile before setup can open it."
        }
        if profile.wantsCouncil {
            if !readiness.modelCatalogLoaded {
                return "Council lineup will be checked after models load."
            }
            if !readiness.councilReady {
                return "Council needs at least two available models; private chat is ready first."
            }
        }
        if !readiness.privateModelAvailable {
            return "Private model catalog is still loading."
        }
        if profile.wantsIronclaw, !readiness.hostedIronclawAvailable {
            return "Phone agent is ready; hosted workstation can be connected later."
        }
        return "Ready: \(modelRoute.title)"
    }
}

enum UserSetupStorage {
    static let completedKey = "userSetupProfileV1Completed"
    static let profileKey = "userSetupProfileV1Data"
    private static let scopedVersion = "v2"
    private static let protectedStoreDirectoryName = "SetupProfiles"
    private static let protectedProfileFilename = "profile.json"
    private static let protectedCompletionFilename = "completed.txt"

    static func accountID(userID: String?, sessionID: String?, token: String?) -> String? {
        if let userID = userID?.trimmingCharacters(in: .whitespacesAndNewlines), !userID.isEmpty {
            return "user:\(userID)"
        }
        if let sessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines), !sessionID.isEmpty {
            return "session:\(sessionID)"
        }
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return "token:\(stableTokenDigest(token))"
        }
        return nil
    }

    static func isFallbackAccountID(_ accountID: String) -> Bool {
        accountID.hasPrefix("session:") || accountID.hasPrefix("token:")
    }

    static func isCompleted(for accountID: String, defaults: UserDefaults = .standard) -> Bool {
        if usesProtectedStorage(defaults) {
            if let data = readProtectedData(for: accountID, filename: protectedCompletionFilename),
               let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return value == "true"
            }
            return defaults.bool(forKey: scopedCompletedKey(for: accountID))
        }
        return defaults.bool(forKey: scopedCompletedKey(for: accountID))
    }

    static func load(for accountID: String, defaults: UserDefaults = .standard) -> UserSetupProfile? {
        if usesProtectedStorage(defaults),
           let data = readProtectedData(for: accountID, filename: protectedProfileFilename),
           let profile = try? JSONDecoder().decode(UserSetupProfile.self, from: data) {
            return profile
        }
        guard let data = defaults.data(forKey: scopedProfileKey(for: accountID)) else { return nil }
        return try? JSONDecoder().decode(UserSetupProfile.self, from: data)
    }

    static func save(_ profile: UserSetupProfile, for accountID: String, defaults: UserDefaults = .standard) {
        if usesProtectedStorage(defaults) {
            if let data = try? JSONEncoder().encode(profile.normalizedForDefaults) {
                writeProtectedData(data, for: accountID, filename: protectedProfileFilename)
            }
            writeProtectedData(Data("true".utf8), for: accountID, filename: protectedCompletionFilename)
            defaults.removeObject(forKey: scopedProfileKey(for: accountID))
            defaults.removeObject(forKey: scopedCompletedKey(for: accountID))
            return
        }
        if let data = try? JSONEncoder().encode(profile.normalizedForDefaults) {
            defaults.set(data, forKey: scopedProfileKey(for: accountID))
        }
        defaults.set(true, forKey: scopedCompletedKey(for: accountID))
    }

    static func clearCompletion(for accountID: String, defaults: UserDefaults = .standard) {
        if usesProtectedStorage(defaults) {
            writeProtectedData(Data("false".utf8), for: accountID, filename: protectedCompletionFilename)
            defaults.removeObject(forKey: scopedCompletedKey(for: accountID))
            return
        }
        defaults.set(false, forKey: scopedCompletedKey(for: accountID))
    }

    static func migrate(from oldAccountID: String, to newAccountID: String, defaults: UserDefaults = .standard) {
        guard oldAccountID != newAccountID,
              isFallbackAccountID(oldAccountID),
              !isCompleted(for: newAccountID, defaults: defaults) else { return }
        if let profile = load(for: oldAccountID, defaults: defaults) {
            save(profile, for: newAccountID, defaults: defaults)
        } else if isCompleted(for: oldAccountID, defaults: defaults) {
            if usesProtectedStorage(defaults) {
                writeProtectedData(Data("true".utf8), for: newAccountID, filename: protectedCompletionFilename)
            } else {
                defaults.set(true, forKey: scopedCompletedKey(for: newAccountID))
            }
        }
        if usesProtectedStorage(defaults) {
            removeProtectedData(for: oldAccountID, filename: protectedProfileFilename)
            removeProtectedData(for: oldAccountID, filename: protectedCompletionFilename)
            defaults.removeObject(forKey: scopedProfileKey(for: oldAccountID))
            defaults.removeObject(forKey: scopedCompletedKey(for: oldAccountID))
        }
    }

    @available(*, deprecated, message: "Use account-scoped save(_:for:) instead.")
    static func save(_ profile: UserSetupProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    @available(*, deprecated, message: "Use account-scoped clearCompletion(for:) instead.")
    static func clearCompletion() {
        UserDefaults.standard.set(false, forKey: completedKey)
    }

    private static func scopedCompletedKey(for accountID: String) -> String {
        "\(completedKey).\(scopedVersion).\(normalizedAccountID(accountID))"
    }

    private static func scopedProfileKey(for accountID: String) -> String {
        "\(profileKey).\(scopedVersion).\(normalizedAccountID(accountID))"
    }

    private static func usesProtectedStorage(_ defaults: UserDefaults) -> Bool {
        defaults === UserDefaults.standard
    }

    private static func protectedDirectoryURL(for accountID: String) -> URL? {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return baseURL
            .appendingPathComponent("NEARPrivateChat", isDirectory: true)
            .appendingPathComponent(protectedStoreDirectoryName, isDirectory: true)
            .appendingPathComponent(normalizedAccountID(accountID), isDirectory: true)
    }

    private static func protectedFileURL(for accountID: String, filename: String) -> URL? {
        protectedDirectoryURL(for: accountID)?.appendingPathComponent(filename, isDirectory: false)
    }

    private static func readProtectedData(for accountID: String, filename: String) -> Data? {
        guard let url = protectedFileURL(for: accountID, filename: filename) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func writeProtectedData(_ data: Data, for accountID: String, filename: String) {
        guard let directoryURL = protectedDirectoryURL(for: accountID),
              let fileURL = protectedFileURL(for: accountID, filename: filename) else { return }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            var mutableDirectoryURL = directoryURL
            try? mutableDirectoryURL.setResourceValues(directoryValues)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            var fileValues = URLResourceValues()
            fileValues.isExcludedFromBackup = true
            var mutableFileURL = fileURL
            try? mutableFileURL.setResourceValues(fileValues)
        } catch {
            return
        }
    }

    private static func removeProtectedData(for accountID: String, filename: String) {
        guard let url = protectedFileURL(for: accountID, filename: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func normalizedAccountID(_ accountID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = accountID.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar).description : "_"
        }
        return String(scalars.joined()).prefix(96).description
    }

    private static func stableTokenDigest(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
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
        case previousResponseID = "previous_response_id"
        case action
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
        previousResponseID = try container.decodeIfPresent(String.self, forKey: .previousResponseID)
        action = try container.decodeIfPresent(SearchAction.self, forKey: .action)

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

    var id: String { url }

    var safeURL: URL? {
        Self.safeURL(from: url)
    }

    var host: String {
        guard let host = safeURL?.host(percentEncoded: false) else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    init(type: String? = nil, url: String, title: String? = nil, publishedAt: String? = nil) {
        self.type = type
        self.url = Self.sanitizedURLString(url) ?? ""
        self.title = title
        self.publishedAt = publishedAt
    }

    static func sanitizedURLString(_ value: String) -> String? {
        guard let url = safeURL(from: value) else { return nil }
        return url.absoluteString
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
        case url
        case title
        case publishedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        let rawURL = try container.decode(String.self, forKey: .url)
        guard let safeURL = Self.sanitizedURLString(rawURL) else {
            throw DecodingError.dataCorruptedError(
                forKey: .url,
                in: container,
                debugDescription: "Search source URL must be http or https."
            )
        }
        url = safeURL
        title = try container.decodeIfPresent(String.self, forKey: .title)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
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

struct SubscriptionPlan: Decodable, Identifiable, Hashable {
    struct Limit: Decodable, Hashable {
        let max: Int?
    }

    let name: String
    let price: Double?
    let trialPeriodDays: Int?
    let monthlyTokens: Limit?
    let allowedModels: [String]?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case price
        case trialPeriodDays = "trial_period_days"
        case monthlyTokens = "monthly_tokens"
        case allowedModels = "allowed_models"
    }
}

struct SubscriptionInfo: Decodable, Identifiable, Hashable {
    let subscriptionID: String
    let plan: String
    let provider: String
    let status: String
    let currentPeriodEnd: String?
    let cancelAtPeriodEnd: Bool?

    var id: String { subscriptionID }

    enum CodingKeys: String, CodingKey {
        case subscriptionID = "subscription_id"
        case plan
        case provider
        case status
        case currentPeriodEnd = "current_period_end"
        case cancelAtPeriodEnd = "cancel_at_period_end"
    }
}

struct SubscriptionPlansResponse: Decodable {
    let plans: [SubscriptionPlan]
}

struct SubscriptionsResponse: Decodable {
    let subscriptions: [SubscriptionInfo]
}

struct BillingSnapshot: Hashable {
    var plans: [SubscriptionPlan]
    var subscriptions: [SubscriptionInfo]
    var fetchedAt: Date

    var activeSubscription: SubscriptionInfo? {
        subscriptions.first { $0.status.localizedCaseInsensitiveContains("active") } ?? subscriptions.first
    }

    var summary: String {
        if let activeSubscription {
            return "\(activeSubscription.plan) · \(activeSubscription.status)"
        }
        if plans.isEmpty {
            return "No plan data"
        }
        return "\(plans.count) available plans"
    }
}

struct ChatAttachment: Identifiable, Codable, Hashable {
    static let pendingTextKind = "pending_text"

    var id: String
    var name: String
    var kind: String
    var bytes: Int?

    var isLocalPendingText: Bool {
        kind == Self.pendingTextKind || id.hasPrefix("local-paste-")
    }

    var displaySize: String? {
        guard let bytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var displayKind: String {
        if isLocalPendingText {
            return "Text paste"
        }
        if kind == "pdf_text" {
            return "PDF text"
        }
        let fileExtension = (name as NSString).pathExtension.lowercased()
        switch fileExtension {
        case "pdf":
            return "PDF"
        case "md", "markdown":
            return "Markdown"
        case "csv":
            return "CSV"
        case "json":
            return "JSON"
        case "txt", "text":
            return "Text"
        default:
            return kind
        }
    }

    var systemImageName: String {
        if isLocalPendingText {
            return "doc.text"
        }
        let fileExtension = (name as NSString).pathExtension.lowercased()
        switch fileExtension {
        case "pdf":
            return "doc.richtext"
        case "csv":
            return "tablecells"
        case "json":
            return "curlybraces"
        case "md", "markdown", "txt", "text":
            return "doc.text"
        default:
            return "paperclip"
        }
    }
}

struct RemoteFileInfo: Identifiable, Decodable, Hashable {
    var id: String
    var object: String?
    var bytes: Int?
    var createdAt: TimeInterval?
    var expiresAt: TimeInterval?
    var filename: String?
    var purpose: String?

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case bytes
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case filename
        case purpose
    }

    init(
        id: String,
        object: String? = nil,
        bytes: Int? = nil,
        createdAt: TimeInterval? = nil,
        expiresAt: TimeInterval? = nil,
        filename: String? = nil,
        purpose: String? = nil
    ) {
        self.id = id
        self.object = object
        self.bytes = bytes
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.filename = filename
        self.purpose = purpose
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        bytes = try container.decodeIfPresent(Int.self, forKey: .bytes)
        createdAt = Self.decodeTimeInterval(from: container, forKey: .createdAt)
        expiresAt = Self.decodeTimeInterval(from: container, forKey: .expiresAt)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        purpose = try container.decodeIfPresent(String.self, forKey: .purpose)
    }

    var name: String {
        let trimmed = (filename ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
    }

    var displaySize: String? {
        guard let bytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var displayKind: String {
        attachment.displayKind
    }

    var systemImageName: String {
        attachment.systemImageName
    }

    var createdAtDisplay: String? {
        guard let createdAt else { return nil }
        return Date(timeIntervalSince1970: createdAt).formatted(date: .abbreviated, time: .shortened)
    }

    var attachment: ChatAttachment {
        ChatAttachment(id: id, name: name, kind: purpose ?? "user_data", bytes: bytes)
    }

    private static func decodeTimeInterval(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> TimeInterval? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return TimeInterval(value)
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return TimeInterval(value)
        }
        return nil
    }
}

struct RemoteFilesResponse: Decodable, Hashable {
    var object: String?
    var data: [RemoteFileInfo]
    var firstID: String?
    var lastID: String?
    var hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case object
        case data
        case firstID = "first_id"
        case lastID = "last_id"
        case hasMore = "has_more"
    }

    init(from decoder: Decoder) throws {
        if var unkeyedContainer = try? decoder.unkeyedContainer() {
            object = nil
            firstID = nil
            lastID = nil
            hasMore = nil
            var files: [RemoteFileInfo] = []
            while !unkeyedContainer.isAtEnd {
                files.append(try unkeyedContainer.decode(RemoteFileInfo.self))
            }
            data = files
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        data = try container.decodeIfPresent([RemoteFileInfo].self, forKey: .data) ?? []
        firstID = try container.decodeIfPresent(String.self, forKey: .firstID)
        lastID = try container.decodeIfPresent(String.self, forKey: .lastID)
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore)
    }
}

struct RemoteFilePreview: Identifiable, Hashable {
    var id: String { file.id }
    var file: RemoteFileInfo
    var text: String
    var byteCount: Int
    var isText: Bool
    var isTruncated: Bool

    init(file: RemoteFileInfo, data: Data, maxPreviewBytes: Int = 96 * 1024) {
        self.file = file
        byteCount = data.count
        let previewData = Data(data.prefix(maxPreviewBytes))
        isTruncated = data.count > maxPreviewBytes

        if let decoded = String(data: previewData, encoding: .utf8) {
            isText = true
            text = decoded
        } else if data.prefix(4).elementsEqual([0x25, 0x50, 0x44, 0x46]) {
            isText = false
            text = "PDF binary loaded. Add it to a prompt or project so the model can use it as file context."
        } else {
            isText = false
            text = "Binary preview unavailable. Add it to a prompt or project so the model can use it as file context."
        }
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

    var tint: Color {
        switch role {
        case .user: .brandBlue
        case .assistant: .primary
        case .system: .secondary
        }
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

struct AppDiagnosticCheck: Identifiable, Hashable {
    enum State: String, Hashable {
        case running
        case passed
        case warning
        case failed

        var symbolName: String {
            switch self {
            case .running: "arrow.triangle.2.circlepath"
            case .passed: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .failed: "xmark.circle.fill"
            }
        }
    }

    var id = UUID().uuidString
    var title: String
    var detail: String
    var state: State
}

enum IronclawApprovalAction: String, Codable, Hashable {
    case approve
    case always
    case deny
}

enum IronclawGateKind: String, Codable, Hashable {
    case approval
    case authentication
    case external
}

struct HostedIronclawHandoffPreflight: Identifiable, Hashable {
    var id: String { fingerprint }
    var fingerprint: String
    var destinationHost: String
    var promptPreview: String
    var disclosedItems: [String]
}

struct IronclawPendingGate: Codable, Hashable, Identifiable {
    var requestID: String
    var threadID: String
    var gateName: String
    var toolName: String
    var description: String
    var parameters: String?
    var allowsAlways: Bool
    var gateKind: IronclawGateKind
    var credentialName: String?
    var authURL: String?
    var setupURL: String?
    var instructions: String?
    var displayName: String?
    var extensionName: String?

    var id: String { requestID }

    var isAuthenticationGate: Bool {
        gateKind == .authentication ||
            gateName.localizedCaseInsensitiveContains("auth") ||
            description.localizedCaseInsensitiveContains("requires authentication") ||
            description.localizedCaseInsensitiveContains("authentication required")
    }

    var authenticationDisplayName: String {
        let rawName = displayName ??
            extensionName ??
            credentialName ??
            parameterValue(for: "name") ??
            parameterValue(for: "credential") ??
            toolName
        return Self.displayName(for: rawName)
    }

    var authenticationHelpText: String {
        if let instructions, !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return instructions
        }
        if description.localizedCaseInsensitiveContains("gate: authentication") ||
            description.localizedCaseInsensitiveContains("requires authentication") {
            return "Add a credential for \(authenticationDisplayName) so the hosted IronClaw workstation can continue this tool call."
        }
        return description
    }

    var parameterPreview: String? {
        guard let parameters, !parameters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return Self.redactedParameterPreview(parameters)
    }

    var locallyAllowsAlways: Bool {
        allowsAlways && !isHighRiskAlwaysApproval
    }

    var isHighRiskAlwaysApproval: Bool {
        let lowerTool = toolName.lowercased()
        let lowerDescription = description.lowercased()
        let lowerParameters = (parameters ?? "").lowercased()
        let highRiskTerms = [
            "shell", "terminal", "command", "exec", "bash", "zsh", "ssh",
            "git", "github", "write", "file", "patch", "apply_patch",
            "delete", "credential", "token", "secret", "http", "browser",
            "network", "package", "install", "npm", "pip", "curl"
        ]
        return highRiskTerms.contains { term in
            lowerTool.contains(term) || lowerDescription.contains(term) || lowerParameters.contains(term)
        }
    }

    var alwaysUnavailableReason: String? {
        guard allowsAlways, isHighRiskAlwaysApproval else { return nil }
        return "Always is disabled on phone for powerful workstation tools. Approve each run so command, network, file, and credential access stays scoped."
    }

    private static func redactedParameterPreview(_ parameters: String) -> String {
        guard let data = parameters.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return redactSecrets(in: parameters)
        }
        if let command = object["command"] as? String {
            return redactSecrets(in: command)
        }
        if let url = object["url"] as? String {
            return redactSecrets(in: url)
        }
        if let name = object["name"] as? String {
            return redactSecrets(in: name)
        }
        if let credential = object["credential"] as? String {
            return redactSecrets(in: credential)
        }
        let sanitized = sanitizedJSONObject(object)
        guard JSONSerialization.isValidJSONObject(sanitized),
              let sanitizedData = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted]),
              let sanitizedString = String(data: sanitizedData, encoding: .utf8) else {
            return redactSecrets(in: parameters)
        }
        return sanitizedString
    }

    var authURLValue: URL? {
        Self.safeGateURL(authURL)
    }

    var authURLHost: String? {
        authURLValue?.host
    }

    var setupURLValue: URL? {
        Self.safeGateURL(setupURL)
    }

    var setupURLHost: String? {
        setupURLValue?.host
    }

    func parameterValue(for key: String) -> String? {
        guard let parameters,
              let data = parameters.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private static func safeGateURL(_ rawValue: String?) -> URL? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: rawValue),
              url.scheme?.lowercased() == "https",
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty,
              URLSecurity.isPublicHost(host) else {
            return nil
        }
        return url
    }

    private static func sanitizedJSONObject(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var sanitized: [String: Any] = [:]
            for (key, childValue) in dictionary {
                if isSensitiveKey(key) {
                    sanitized[key] = "[redacted]"
                } else {
                    sanitized[key] = sanitizedJSONObject(childValue)
                }
            }
            return sanitized
        }
        if let array = value as? [Any] {
            return array.map(sanitizedJSONObject)
        }
        if let string = value as? String {
            return redactSecrets(in: string)
        }
        return value
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        let fragments = [
            "token", "secret", "password", "credential", "authorization",
            "api_key", "apikey", "private_key", "session", "bearer",
            "ssh_key", "access_key", "refresh"
        ]
        return fragments.contains { normalized.contains($0) }
    }

    private static func redactSecrets(in value: String) -> String {
        let patterns = [
            #"(?i)\bBearer\s+[A-Za-z0-9._~+/\-=]{12,}"#,
            #"(?i)\b(token|api_key|key|secret|password|credential|session)=([^&\s]+)"#,
            #"(?i)\b(sk|pk|ghp|github_pat|napi|near)[-_][A-Za-z0-9._~+/\-=]{12,}"#,
            #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#,
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#
        ]
        return patterns.reduce(value) { partial, pattern in
            partial.replacingOccurrences(
                of: pattern,
                with: "[redacted]",
                options: .regularExpression
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case threadID = "thread_id"
        case gateName = "gate_name"
        case toolName = "tool_name"
        case description
        case parameters
        case allowsAlways = "allows_always"
        case resumeKind = "resume_kind"
        case gateKind = "gate_kind"
        case credentialName = "credential_name"
        case authURL = "auth_url"
        case setupURL = "setup_url"
        case instructions
        case displayName = "display_name"
        case extensionName = "extension_name"
    }

    enum ResumeKindKeys: String, CodingKey {
        case approval = "Approval"
        case authentication = "Authentication"
        case external = "External"
    }

    enum ApprovalKeys: String, CodingKey {
        case allowAlways = "allow_always"
    }

    enum AuthenticationKeys: String, CodingKey {
        case credentialName = "credential_name"
        case authURL = "auth_url"
        case setupURL = "setup_url"
        case instructions
    }

    enum ExternalKeys: String, CodingKey {
        case authURL = "auth_url"
        case setupURL = "setup_url"
        case instructions
        case url
    }

    init(
        requestID: String,
        threadID: String,
        gateName: String,
        toolName: String,
        description: String,
        parameters: String?,
        allowsAlways: Bool,
        gateKind: IronclawGateKind = .approval,
        credentialName: String? = nil,
        authURL: String? = nil,
        setupURL: String? = nil,
        instructions: String? = nil,
        displayName: String? = nil,
        extensionName: String? = nil
    ) {
        self.requestID = requestID
        self.threadID = threadID
        self.gateName = gateName
        self.toolName = toolName
        self.description = description
        self.parameters = parameters
        self.allowsAlways = allowsAlways
        self.gateKind = gateKind
        self.credentialName = credentialName
        self.authURL = authURL
        self.setupURL = setupURL
        self.instructions = instructions
        self.displayName = displayName
        self.extensionName = extensionName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(String.self, forKey: .requestID)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID) ?? ""
        gateName = try container.decodeIfPresent(String.self, forKey: .gateName) ?? "approval"
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName) ?? "tool"
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? "Tool approval required."
        parameters = try container.decodeIfPresent(String.self, forKey: .parameters)
        gateKind = try container.decodeIfPresent(IronclawGateKind.self, forKey: .gateKind) ?? .approval
        credentialName = try container.decodeIfPresent(String.self, forKey: .credentialName)
        authURL = try container.decodeIfPresent(String.self, forKey: .authURL)
        setupURL = try container.decodeIfPresent(String.self, forKey: .setupURL)
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        extensionName = try container.decodeIfPresent(String.self, forKey: .extensionName)
        if let flatAllowsAlways = try container.decodeIfPresent(Bool.self, forKey: .allowsAlways) {
            allowsAlways = flatAllowsAlways
        } else if let resumeKind = try? container.nestedContainer(keyedBy: ResumeKindKeys.self, forKey: .resumeKind),
                  let approval = try? resumeKind.nestedContainer(keyedBy: ApprovalKeys.self, forKey: .approval) {
            allowsAlways = (try? approval.decode(Bool.self, forKey: .allowAlways)) ?? false
        } else {
            allowsAlways = false
        }

        if let resumeKind = try? container.nestedContainer(keyedBy: ResumeKindKeys.self, forKey: .resumeKind) {
            if resumeKind.contains(.authentication) {
                gateKind = .authentication
                if let auth = try? resumeKind.nestedContainer(keyedBy: AuthenticationKeys.self, forKey: .authentication) {
                    credentialName = credentialName ?? (try? auth.decode(String.self, forKey: .credentialName))
                    authURL = authURL ?? (try? auth.decode(String.self, forKey: .authURL))
                    setupURL = setupURL ?? (try? auth.decode(String.self, forKey: .setupURL))
                    instructions = instructions ?? (try? auth.decode(String.self, forKey: .instructions))
                }
            } else if resumeKind.contains(.external) {
                gateKind = .external
                if let external = try? resumeKind.nestedContainer(keyedBy: ExternalKeys.self, forKey: .external) {
                    authURL = authURL ??
                        (try? external.decode(String.self, forKey: .authURL)) ??
                        (try? external.decode(String.self, forKey: .url))
                    setupURL = setupURL ?? (try? external.decode(String.self, forKey: .setupURL))
                    instructions = instructions ?? (try? external.decode(String.self, forKey: .instructions))
                }
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(gateName, forKey: .gateName)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(parameters, forKey: .parameters)
        try container.encode(allowsAlways, forKey: .allowsAlways)
        try container.encode(gateKind, forKey: .gateKind)
        try container.encodeIfPresent(credentialName, forKey: .credentialName)
        try container.encodeIfPresent(authURL, forKey: .authURL)
        try container.encodeIfPresent(setupURL, forKey: .setupURL)
        try container.encodeIfPresent(instructions, forKey: .instructions)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(extensionName, forKey: .extensionName)
    }

    private static func displayName(for rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Credential" }
        switch trimmed.lowercased() {
        case "github", "github_token", "github-token", "github pat":
            return "GitHub"
        default:
            return trimmed
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }
}

struct ProjectLink: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var urlString: String
    var createdAt: Date

    init(
        id: String = "link-\(UUID().uuidString)",
        title: String,
        urlString: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
    }

    var url: URL? {
        URL(string: urlString)
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return host ?? urlString
    }

    var host: String? {
        url?.host()
    }
}

struct ProjectNote: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var text: String
    var createdAt: Date
    var sourceMessageID: String?

    init(
        id: String = "note-\(UUID().uuidString)",
        title: String,
        text: String,
        createdAt: Date = Date(),
        sourceMessageID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
        self.sourceMessageID = sourceMessageID
    }
}

enum ProjectPalette: String, CaseIterable, Codable, Identifiable {
    case sky
    case mint
    case teal
    case violet
    case indigo
    case rose
    case amber
    case slate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sky: "Sky"
        case .mint: "Mint"
        case .teal: "Teal"
        case .violet: "Violet"
        case .indigo: "Indigo"
        case .rose: "Rose"
        case .amber: "Amber"
        case .slate: "Slate"
        }
    }

    var tintColor: Color {
        switch self {
        case .sky: Color.primaryAction
        case .mint: Color(red: 0.0, green: 0.56, blue: 0.42)
        case .teal: Color(red: 0.0, green: 0.48, blue: 0.62)
        case .violet: Color(red: 0.42, green: 0.34, blue: 0.90)
        case .indigo: Color(red: 0.24, green: 0.31, blue: 0.82)
        case .rose: Color(red: 0.82, green: 0.24, blue: 0.42)
        case .amber: Color(red: 0.78, green: 0.45, blue: 0.02)
        case .slate: Color(red: 0.28, green: 0.33, blue: 0.38)
        }
    }

    var backgroundColor: Color {
        tintColor.opacity(0.13)
    }
}

enum ProjectIcon: String, CaseIterable, Codable, Identifiable {
    case folder
    case code
    case research
    case agent
    case memo
    case chart
    case launch
    case briefcase
    case globe
    case link
    case lock
    case shield
    case sparkles
    case bolt
    case book
    case database
    case server
    case cloud
    case terminalWindow
    case pullRequest
    case branch
    case hammer
    case wrench
    case flask
    case brain
    case eye
    case people
    case calendar
    case pin
    case archive

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .folder: "folder"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .research: "text.magnifyingglass"
        case .agent: "terminal"
        case .memo: "doc.text"
        case .chart: "chart.bar"
        case .launch: "paperplane"
        case .briefcase: "briefcase"
        case .globe: "globe"
        case .link: "link"
        case .lock: "lock.shield"
        case .shield: "checkmark.shield"
        case .sparkles: "sparkles"
        case .bolt: "bolt"
        case .book: "book.closed"
        case .database: "externaldrive"
        case .server: "server.rack"
        case .cloud: "cloud"
        case .terminalWindow: "terminal"
        case .pullRequest: "arrow.triangle.pull"
        case .branch: "arrow.triangle.branch"
        case .hammer: "hammer"
        case .wrench: "wrench.and.screwdriver"
        case .flask: "flask"
        case .brain: "brain.head.profile"
        case .eye: "eye"
        case .people: "person.2"
        case .calendar: "calendar"
        case .pin: "pin"
        case .archive: "archivebox"
        }
    }

    var label: String {
        switch self {
        case .folder: "Folder"
        case .code: "Code"
        case .research: "Research"
        case .agent: "Agent"
        case .memo: "Memo"
        case .chart: "Chart"
        case .launch: "Launch"
        case .briefcase: "Business"
        case .globe: "Web"
        case .link: "Links"
        case .lock: "Private"
        case .shield: "Proof"
        case .sparkles: "AI"
        case .bolt: "Fast"
        case .book: "Knowledge"
        case .database: "Data"
        case .server: "Server"
        case .cloud: "Cloud"
        case .terminalWindow: "Terminal"
        case .pullRequest: "Pull Request"
        case .branch: "Branch"
        case .hammer: "Build"
        case .wrench: "Tools"
        case .flask: "Experiment"
        case .brain: "Thinking"
        case .eye: "Review"
        case .people: "Team"
        case .calendar: "Plan"
        case .pin: "Pinned"
        case .archive: "Archive"
        }
    }

    func matches(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }
        return ([
            rawValue,
            label,
            symbolName
        ] + searchAliases)
            .contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
    }

    private var searchAliases: [String] {
        switch self {
        case .shield:
            return ["verified", "attested", "trust"]
        default:
            return []
        }
    }
}

struct ChatProject: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var createdAt: Date
    var conversationIDs: [String]
    var attachments: [ChatAttachment]
    var instructions: String
    var memorySummary: String
    var links: [ProjectLink]
    var notes: [ProjectNote]
    var iconName: String
    var paletteName: String

    init(
        id: String,
        name: String,
        createdAt: Date,
        conversationIDs: [String],
        attachments: [ChatAttachment] = [],
        instructions: String = "",
        memorySummary: String = "",
        links: [ProjectLink] = [],
        notes: [ProjectNote] = [],
        iconName: String = ProjectIcon.folder.symbolName,
        paletteName: String = ProjectPalette.sky.rawValue
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.conversationIDs = conversationIDs
        self.attachments = attachments
        self.instructions = instructions
        self.memorySummary = memorySummary
        self.links = links
        self.notes = notes
        self.iconName = iconName
        self.paletteName = paletteName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case conversationIDs
        case attachments
        case instructions
        case memorySummary
        case links
        case notes
        case iconName
        case paletteName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        conversationIDs = try container.decode([String].self, forKey: .conversationIDs)
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        memorySummary = try container.decodeIfPresent(String.self, forKey: .memorySummary) ?? ""
        links = try container.decodeIfPresent([ProjectLink].self, forKey: .links) ?? []
        notes = try container.decodeIfPresent([ProjectNote].self, forKey: .notes) ?? []
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? ProjectIcon.folder.symbolName
        paletteName = try container.decodeIfPresent(String.self, forKey: .paletteName) ?? ProjectPalette.sky.rawValue
    }

    var projectIconName: String {
        if ProjectIcon.allCases.contains(where: { $0.symbolName == iconName }) {
            return iconName
        }
        if let icon = ProjectIcon(rawValue: iconName) {
            return icon.symbolName
        }
        return ProjectIcon.folder.symbolName
    }

    var projectPalette: ProjectPalette {
        ProjectPalette(rawValue: paletteName) ?? .sky
    }

    var tintColor: Color {
        projectPalette.tintColor
    }

    var tintBackgroundColor: Color {
        projectPalette.backgroundColor
    }
}

struct IronclawSettings: Codable, Hashable {
    var isEnabled: Bool
    var baseURL: String
    var threadID: String

    static let `default` = IronclawSettings(
        isEnabled: false,
        baseURL: "",
        threadID: ""
    )

    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasEndpoint: Bool {
        !normalizedBaseURL.isEmpty
    }

    var hasUsableHostedEndpoint: Bool {
        endpointValidationMessage == nil
    }

    var endpointValidationMessage: String? {
        let trimmed = normalizedBaseURL
        guard !trimmed.isEmpty else {
            return "Add a hosted HTTPS IronClaw endpoint first."
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return "Enter a valid hosted HTTPS IronClaw endpoint."
        }
        if Self.retiredLocalDefaults.contains(trimmed) || !URLSecurity.isPublicHost(host) {
            return "Use a hosted HTTPS IronClaw endpoint. LAN gateways are local development only."
        }
        guard scheme == "https" else {
            return "IronClaw on iPhone requires HTTPS, not a local HTTP gateway."
        }
        return nil
    }

    var standalonePhoneSanitized: IronclawSettings {
        var copy = self
        copy.baseURL = normalizedBaseURL
        copy.threadID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.retiredLocalDefaults.contains(copy.baseURL) {
            copy.baseURL = ""
        }
        if !copy.hasUsableHostedEndpoint {
            copy.isEnabled = false
        }
        return copy
    }

    private static let retiredLocalDefaults = [
        "http://192.168.2.67:3000"
    ]

}

struct SharedConversationSnapshot: Identifiable, Hashable {
    var conversation: ConversationSummary
    var messages: [ChatMessage]
    var source: String
    var canWrite: Bool
    var loadedAt: Date

    var id: String { conversation.id }
}

struct ModelListResponse: Decodable {
    let models: [ModelOption]
}

struct ModelOption: Decodable, Identifiable, Hashable {
    struct Metadata: Decodable, Hashable {
        let verifiable: Bool?
        let contextLength: Int?
        let modelDisplayName: String?
        let modelDescription: String?
        let modelIcon: String?
        let aliases: [String]?

        enum CodingKeys: String, CodingKey {
            case verifiable
            case contextLength
            case modelDisplayName
            case modelDescription
            case modelIcon
            case aliases
        }
    }

    let modelID: String
    let publicModel: Bool?
    let metadata: Metadata?
    static let ironclawModelID = "ironclaw/agent"
    static let ironclawMobileModelID = "ironclaw/mobile-runtime"
    static let nearCloudModelPrefix = "near-cloud/"
    static let nearCloudQwenMaxModelID = "near-cloud/qwen3.7-max"
    static let llmCouncilSynthesisModelID = "llm-council/synthesis"

    var id: String { modelID }

    var displayName: String {
        if isIronclawMobileRuntime {
            return "IronClaw Mobile"
        }
        if isIronclawHostedModel {
            return "IronClaw Agent"
        }
        if isNearCloudModel {
            if metadata?.modelDisplayName?.isEmpty == false {
                return metadata!.modelDisplayName!
            }
            if isNearCloudQwenMaxModel {
                return "Qwen 3.7 Max"
            }
        }
        if modelID == Self.llmCouncilSynthesisModelID {
            return "Council Synthesis"
        }
        return metadata?.modelDisplayName?.isEmpty == false ? metadata!.modelDisplayName! : modelID
    }

    var isVerifiable: Bool {
        guard !isExternalModel else { return false }
        return metadata?.verifiable ?? true
    }

    var isIronclawHostedModel: Bool {
        modelID == Self.ironclawModelID
    }

    var isIronclawMobileRuntime: Bool {
        modelID == Self.ironclawMobileModelID
    }

    var isIronclawModel: Bool {
        isIronclawHostedModel || isIronclawMobileRuntime
    }

    var isNearCloudQwenMaxModel: Bool {
        modelID == Self.nearCloudQwenMaxModelID ||
            nearCloudUnderlyingModelID?.localizedCaseInsensitiveCompare("qwen/qwen3.7-max") == .orderedSame
    }

    var isNearCloudModel: Bool {
        modelID == Self.nearCloudQwenMaxModelID || modelID.hasPrefix(Self.nearCloudModelPrefix)
    }

    var isExternalModel: Bool {
        isIronclawModel || isNearCloudModel
    }

    var nearCloudUnderlyingModelID: String? {
        if modelID == Self.nearCloudQwenMaxModelID {
            return "qwen/qwen3.7-max"
        }
        guard modelID.hasPrefix(Self.nearCloudModelPrefix) else { return nil }
        let underlying = String(modelID.dropFirst(Self.nearCloudModelPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return underlying.isEmpty ? nil : underlying
    }

    static func nearCloudModelID(for cloudModelID: String) -> String {
        "\(nearCloudModelPrefix)\(cloudModelID.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    var isUtilityModel: Bool {
        if isExternalModel { return false }
        let lowercased = searchText.lowercased()
        return lowercased.contains("embedding") ||
            lowercased.contains("reranker") ||
            lowercased.contains("whisper") ||
            lowercased.contains("flux")
    }

    var isAnthropicModel: Bool {
        modelID.hasPrefix("anthropic/")
    }

    var isClosedProviderModel: Bool {
        let lowercased = modelID.lowercased()
        if lowercased.hasPrefix("openai/gpt-oss") {
            return false
        }
        return lowercased.hasPrefix("openai/") ||
            lowercased.hasPrefix("anthropic/") ||
            lowercased.hasPrefix("google/") ||
            lowercased.hasPrefix("x-ai/") ||
            lowercased.hasPrefix("mistral/")
    }

    var isOpenWeightCandidate: Bool {
        guard !isExternalModel, !isUtilityModel, !isClosedProviderModel else { return false }
        let lowercased = searchText.lowercased()
        return lowercased.contains("glm") ||
            lowercased.contains("qwen") ||
            lowercased.contains("deepseek") ||
            lowercased.contains("kimi") ||
            lowercased.contains("moonshot") ||
            lowercased.contains("zai") ||
            lowercased.contains("llama") ||
            lowercased.contains("gpt-oss") ||
            lowercased.contains("oss")
    }

    var isEliteModel: Bool {
        let ids = [
            "openai/gpt-5.5",
            "anthropic/claude-opus-4-7",
            "anthropic/claude-sonnet-4-6",
            "openai/gpt-5.4",
            "google/gemini-3-pro",
            "openai/gpt-5.2",
            "openai/gpt-5.1",
            "openai/gpt-5",
            "google/gemini-2.5-pro",
            "anthropic/claude-opus-4-6",
            "anthropic/claude-sonnet-4-5",
            "zai-org/GLM-5.1-FP8",
            "Qwen/Qwen3.5-122B-A10B",
            "Qwen/Qwen3.6-35B-A3B-FP8"
        ]
        return ids.contains(modelID) ||
            modelID.localizedCaseInsensitiveContains("claude-opus") ||
            modelID.localizedCaseInsensitiveContains("claude-sonnet") ||
            modelID.localizedCaseInsensitiveContains("claude-sonnet-4") ||
            modelID.localizedCaseInsensitiveContains("gemini-pro") ||
            modelID.localizedCaseInsensitiveContains("kimi") ||
            modelID.localizedCaseInsensitiveContains("deepseek")
    }

    var isPrivateVerifiableChatModel: Bool {
        !isExternalModel && isVerifiable && !isUtilityModel && !isLowerPriorityModel
    }

    var isLowerPriorityModel: Bool {
        let lowercased = searchText.lowercased()
        return lowercased.contains("o3") ||
            lowercased.contains("o4-mini") ||
            lowercased.contains("haiku") ||
            lowercased.contains("mini") ||
            lowercased.contains("nano") ||
            lowercased.contains("lite") ||
            lowercased.contains("flash") ||
            lowercased.contains("gpt-oss") ||
            lowercased.contains("gemma")
    }

    var isDeprecatedPickerModel: Bool {
        guard !isExternalModel else { return false }
        let lowercasedID = modelID.lowercased()
        let lowercased = searchText.lowercased()

        if [
            "openai/gpt-5",
            "openai/gpt-5.1",
            "openai/gpt-4.1",
            "google/gemini-2.5-pro",
            "anthropic/claude-opus-4-5",
            "anthropic/claude-sonnet-4-5",
            "qwen/qwen3.7-max",
            "qwen/qwen3-30b-a3b-instruct-2507",
            "qwen/qwen3-vl-30b-a3b-instruct"
        ].contains(lowercasedID) {
            return true
        }

        if lowercased.contains("gpt-5.4-mini") ||
            lowercased.contains("gpt-oss") ||
            lowercased.contains("gpt-4.1") ||
            lowercased.contains("o3") ||
            lowercased.contains("o4-mini") ||
            lowercased.contains("haiku") ||
            lowercasedID.contains("-mini") ||
            lowercasedID.contains("/mini") ||
            lowercased.contains("nano") ||
            lowercased.contains("lite") ||
            lowercased.contains("flash") ||
            lowercased.contains("gemma") {
            return true
        }

        return false
    }

    var isRecommendedReasoningModel: Bool {
        let lowercased = searchText.lowercased()
        return isEliteModel ||
            lowercased.contains("reasoning") ||
            lowercased.contains("thinking") ||
            lowercased.contains("deepseek") ||
            lowercased.contains("gpt-5") ||
            lowercased.contains("gemini-3") ||
            lowercased.contains("gemini-2.5-pro") ||
            lowercased.contains("qwen3.5") ||
            lowercased.contains("qwen3.6") ||
            lowercased.contains("glm-5")
    }

    var isCodeModel: Bool {
        let lowercased = searchText.lowercased()
        return isIronclawModel ||
            lowercased.contains("code") ||
            lowercased.contains("coder") ||
            lowercased.contains("coding") ||
            lowercased.contains("software") ||
            lowercased.contains("repo") ||
            lowercased.contains("devstral")
    }

    var isVisionModel: Bool {
        let lowercased = searchText.lowercased()
        return lowercased.contains("vision") ||
            lowercased.contains("multimodal") ||
            lowercased.contains("image") ||
            lowercased.contains("-vl") ||
            lowercased.contains("/vl") ||
            lowercased.contains(" qwen-vl")
    }

    var isLongContextModel: Bool {
        if (metadata?.contextLength ?? 0) >= 128_000 {
            return true
        }
        let lowercased = searchText.lowercased()
        return lowercased.contains("long context") ||
            lowercased.contains("1m ctx") ||
            lowercased.contains("1m context") ||
            lowercased.contains("million token")
    }

    var capabilityBadges: [String] {
        var badges: [String] = []
        if isIronclawMobileRuntime {
            badges.append("Agent")
            badges.append("Mobile")
        } else if isIronclawHostedModel {
            badges.append("Agent")
            badges.append("Hosted")
        } else if isNearCloudModel {
            badges.append("NEAR Cloud")
            badges.append("External")
        }
        if isRecommendedReasoningModel {
            badges.append("Reasoning")
        }
        if isEliteModel {
            badges.append("Frontier")
        }
        if isCodeModel {
            badges.append("Code")
        }
        if isVisionModel {
            badges.append("Vision")
        }
        if (metadata?.aliases ?? []).contains(where: { $0.localizedCaseInsensitiveContains("deepseek") }) {
            badges.append("DeepSeek alias")
        }
        if isLongContextModel {
            badges.append((metadata?.contextLength ?? 0) >= 1_000_000 ? "1M ctx" : "Long ctx")
        }
        if isVerifiable {
            badges.append("TEE")
        }
        return Array(badges.prefix(3))
    }

    private var searchText: String {
        ([modelID, displayName, metadata?.modelDescription] + (metadata?.aliases ?? []))
            .compactMap { $0 }
            .joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case modelID = "modelId"
        case publicModel = "public"
        case metadata
    }
}

struct CouncilPresetOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let models: [ModelOption]

    var isAvailable: Bool {
        models.count > 1
    }

    var modelIDs: [String] {
        models.map(\.id)
    }

    var previewNames: String {
        models.prefix(3).map(\.displayName).joined(separator: " + ") +
            (models.count > 3 ? " +\(models.count - 3)" : "")
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

struct AttestationSnapshot: Hashable {
    let nonce: String
    let signingAlgorithm: String
    let model: String?
    let coveredModelIDs: [String]
    let fetchedAt: Date
    let chatGatewayAddress: String?
    let cloudGatewayAddress: String?
    let modelAttestationCount: Int
    let prettyJSON: String

    init(
        nonce: String,
        signingAlgorithm: String,
        model: String?,
        coveredModelIDs: [String] = [],
        fetchedAt: Date,
        chatGatewayAddress: String?,
        cloudGatewayAddress: String?,
        modelAttestationCount: Int,
        prettyJSON: String
    ) {
        self.nonce = nonce
        self.signingAlgorithm = signingAlgorithm
        self.model = model
        self.coveredModelIDs = coveredModelIDs
        self.fetchedAt = fetchedAt
        self.chatGatewayAddress = chatGatewayAddress
        self.cloudGatewayAddress = cloudGatewayAddress
        self.modelAttestationCount = modelAttestationCount
        self.prettyJSON = prettyJSON
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case unauthenticated
    case invalidCallback
    case status(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The API URL is invalid."
        case .unauthenticated: "Sign in again to continue."
        case .invalidCallback: "The sign-in callback did not include a session token."
        case let .status(code, message): Self.displayStatusMessage(code: code, rawMessage: message)
        case .emptyResponse: "The server returned an empty response."
        }
    }

    private static func displayStatusMessage(code: Int, rawMessage: String) -> String {
        let fallback = code == 0 ? "The request failed." : "Request failed with status \(code)."
        let normalized = rawMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty else { return fallback }

        let lowercased = normalized.lowercased()
        let looksRaw = normalized.count > 240 ||
            lowercased.hasPrefix("<!doctype") ||
            lowercased.hasPrefix("<html") ||
            (normalized.hasPrefix("{") && normalized.hasSuffix("}")) ||
            lowercased.contains("traceback") ||
            lowercased.contains("stack trace")
        return looksRaw ? fallback : normalized
    }
}

enum ResponseStreamEvent: Equatable {
    case created(responseID: String)
    case reasoningStarted
    case approvalNeeded(IronclawPendingGate)
    case webSearchStarted(query: String?)
    case webSearchCompleted(query: String?, sources: [WebSearchSource])
    case textDelta(String)
    case itemDone(text: String?)
    case titleUpdated(String)
    case completed(responseID: String?)
    case failed(String)

    var hasVisibleOutput: Bool {
        switch self {
        case let .textDelta(delta):
            return !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .itemDone(text):
            return text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        default:
            return false
        }
    }
}

enum URLSecurity {
    static func isPublicHTTPSURL(_ url: URL) -> Bool {
        isPublicWebURL(url, allowHTTP: false)
    }

    static func isPublicWebURL(_ url: URL, allowHTTP: Bool = true) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              (scheme == "https" || (allowHTTP && scheme == "http")),
              components.user == nil,
              components.password == nil,
              let host = components.host,
              isPublicHost(host) else {
            return false
        }
        return true
    }

    static func isPublicHost(_ rawHost: String) -> Bool {
        let host = normalizedHost(rawHost)
        guard !host.isEmpty else { return false }
        if host == "localhost" ||
            host == "metadata" ||
            host == "metadata.google.internal" ||
            host.hasSuffix(".localhost") ||
            host.hasSuffix(".local") {
            return false
        }
        if let octets = parsedIPv4Octets(host) {
            return !isReservedIPv4(octets)
        }
        if isReservedIPv6Literal(host) {
            return false
        }
        if host.contains(":") {
            return true
        }
        if !host.contains(".") {
            return false
        }
        return true
    }

    static func normalizedPublicHTTPSURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let host = components.host,
              isPublicHost(host) else {
            return nil
        }
        components.scheme = "https"
        return components.url.flatMap { isPublicHTTPSURL($0) ? $0 : nil }
    }

    private static func normalizedHost(_ rawHost: String) -> String {
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host
    }

    private static func parsedIPv4Octets(_ host: String) -> [UInt32]? {
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count),
              pieces.allSatisfy({ !$0.isEmpty }),
              let values = optionalSequence(pieces.map { parseIPv4Component(String($0)) }) else {
            return nil
        }
        switch values.count {
        case 1:
            guard values[0] <= UInt32.max else { return nil }
            return [
                (values[0] >> 24) & 0xff,
                (values[0] >> 16) & 0xff,
                (values[0] >> 8) & 0xff,
                values[0] & 0xff
            ]
        case 2:
            guard values[0] <= 0xff, values[1] <= 0x00ff_ffff else { return nil }
            return [values[0], (values[1] >> 16) & 0xff, (values[1] >> 8) & 0xff, values[1] & 0xff]
        case 3:
            guard values[0] <= 0xff, values[1] <= 0xff, values[2] <= 0xffff else { return nil }
            return [values[0], values[1], (values[2] >> 8) & 0xff, values[2] & 0xff]
        case 4:
            guard values.allSatisfy({ $0 <= 0xff }) else { return nil }
            return values
        default:
            return nil
        }
    }

    private static func parseIPv4Component(_ value: String) -> UInt32? {
        let lowercased = value.lowercased()
        if lowercased.hasPrefix("0x") {
            return UInt32(lowercased.dropFirst(2), radix: 16)
        }
        if lowercased.count > 1, lowercased.hasPrefix("0") {
            return UInt32(lowercased.dropFirst(), radix: 8)
        }
        return UInt32(lowercased, radix: 10)
    }

    private static func optionalSequence<T>(_ values: [T?]) -> [T]? {
        var unwrapped: [T] = []
        for value in values {
            guard let value else { return nil }
            unwrapped.append(value)
        }
        return unwrapped
    }

    private static func isReservedIPv4(_ octets: [UInt32]) -> Bool {
        guard octets.count == 4 else { return true }
        let first = octets[0]
        let second = octets[1]
        switch first {
        case 0, 10, 127:
            return true
        case 100:
            return (64...127).contains(second)
        case 169:
            return second == 254
        case 172:
            return (16...31).contains(second)
        case 192:
            return second == 0 || second == 168
        case 198:
            return second == 18 || second == 19 || (second == 51 && octets[2] == 100)
        case 203:
            return second == 0 && octets[2] == 113
        case 224...255:
            return true
        default:
            return false
        }
    }

    private static func isReservedIPv6Literal(_ host: String) -> Bool {
        guard host.contains(":") else { return false }
        if host == "::" || host == "::1" {
            return true
        }
        if let mappedIPv4 = host.split(separator: ":").last,
           mappedIPv4.contains("."),
           let octets = parsedIPv4Octets(String(mappedIPv4)) {
            return isReservedIPv4(octets)
        }
        let firstHextet = host.split(separator: ":").first.map(String.init) ?? ""
        guard let firstValue = UInt32(firstHextet, radix: 16) else {
            return true
        }
        return (0xfc00...0xfdff).contains(firstValue) ||
            (0xfe80...0xfebf).contains(firstValue) ||
            firstValue == 0
    }
}

extension Color {
    static let brandBlack = Color(red: 0.0, green: 0.0, blue: 0.0)
    static let brandDarkGrey = Color(red: 0.153, green: 0.153, blue: 0.153)
    static let brandGrey = Color(red: 0.655, green: 0.655, blue: 0.655)
    static let brandOffWhite = Color(red: 0.933, green: 0.933, blue: 0.922)
    static let brandSky = Color(red: 0.514, green: 0.863, blue: 1.0)
    static let brandBlue = Color(red: 0.0, green: 0.569, blue: 0.992)
    static let appSelection = Color(red: 0.86, green: 0.94, blue: 1.0)
    static let appBlueTint = Color(red: 0.92, green: 0.97, blue: 1.0)
    static let appSymbolBlueBackground = Color(red: 0.78, green: 0.91, blue: 1.0)
    static let actionPrimary = Color.brandBlue
    static let primaryAction = Color.actionPrimary
    static let proofVerified = Color(red: 0.082, green: 0.745, blue: 0.325)
    static let proofStale = Color(red: 0.961, green: 0.651, blue: 0.137)
    static let proofMismatch = Color(red: 0.898, green: 0.282, blue: 0.302)
    static let routeCloud = Color.textSecondary
    static let routePrivate = Color.proofVerified
    static let selectionSubtle = Color.appSelection
    static let intensitySurfaceBase = Color.appBackground
    static let intensityRowPlain = Color.clear
    static let intensityPanelSoft = Color.appPanelBackground
    static let intensityRowSelected = Color.selectionSubtle
    static let intensityCommandPrimary = Color.actionPrimary
    static let intensityProofArtifact = Color.proofVerified
    static let intensityDanger = Color.proofMismatch
    static let trustVerified = Color.proofVerified
    static let trustFreshAccent = Color.brandSky
    static let warningState = Color.proofStale
    static let destructiveState = Color.proofMismatch
    static let textPrimary = Color.primary

    #if canImport(UIKit)
    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let appBackground = dynamicColor(
        light: UIColor(red: 0.972, green: 0.974, blue: 0.966, alpha: 1.0),
        dark: UIColor(red: 0.055, green: 0.060, blue: 0.063, alpha: 1.0)
    )
    static let appSecondaryBackground = dynamicColor(
        light: UIColor(red: 0.944, green: 0.949, blue: 0.944, alpha: 1.0),
        dark: UIColor(red: 0.098, green: 0.106, blue: 0.112, alpha: 1.0)
    )
    static let appPanelBackground = dynamicColor(
        light: .white,
        dark: UIColor(red: 0.075, green: 0.082, blue: 0.088, alpha: 1.0)
    )
    static let appBorder = dynamicColor(
        light: UIColor.black.withAlphaComponent(0.08),
        dark: UIColor.white.withAlphaComponent(0.11)
    )
    static let appHairline = dynamicColor(
        light: UIColor.black.withAlphaComponent(0.05),
        dark: UIColor.white.withAlphaComponent(0.07)
    )
    static let textSecondary = dynamicColor(
        light: UIColor(red: 0.153, green: 0.153, blue: 0.153, alpha: 0.72),
        dark: UIColor.white.withAlphaComponent(0.68)
    )
    #elseif canImport(AppKit)
    static let appBackground = Color(red: 0.972, green: 0.974, blue: 0.966)
    static let appSecondaryBackground = Color(red: 0.944, green: 0.949, blue: 0.944)
    static let appPanelBackground = Color.white
    static let appBorder = Color.brandBlack.opacity(0.08)
    static let appHairline = Color.brandBlack.opacity(0.05)
    static let textSecondary = Color.brandDarkGrey.opacity(0.72)
    #else
    static let appBackground = Color(red: 0.972, green: 0.974, blue: 0.966)
    static let appSecondaryBackground = Color(red: 0.944, green: 0.949, blue: 0.944)
    static let appPanelBackground = Color.white
    static let appBorder = Color.brandBlack.opacity(0.08)
    static let appHairline = Color.brandBlack.opacity(0.05)
    static let textSecondary = Color.brandDarkGrey.opacity(0.72)
    #endif

    static let surface = Color.appBackground
    static let panel = Color.appPanelBackground
    static let secondarySurface = Color.appSecondaryBackground
    static let border = Color.appBorder
}

extension View {
    @ViewBuilder
    func platformInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformMediumDetent() -> some View {
        #if os(iOS)
        presentationDetents([.medium])
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformLargeDetent() -> some View {
        #if os(iOS)
        presentationDetents([.large])
        #else
        self
        #endif
    }

    @ViewBuilder
    func tokenInputTraits() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }
}

enum Clipboard {
    static func copy(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: string]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(10 * 60)
            ]
        )
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

struct ProductWordmark: View {
    var alignment: HorizontalAlignment = .leading
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: alignment, spacing: -2 * scale) {
            Text("NEAR AI")
                .font(.system(size: 44 * scale, weight: .heavy, design: .default))
                .foregroundStyle(Color.brandBlack)
            Text("private chat")
                .font(.system(size: 30 * scale, weight: .heavy, design: .default))
                .foregroundStyle(Color.brandBlue)
        }
        .accessibilityLabel("NEAR AI Private Chat")
    }
}

struct PrivacySeal: View {
    var size: CGFloat = 72

    var body: some View {
        Image("PrivateChatIcon")
            .resizable()
            .scaledToFit()
        .frame(width: size, height: size)
        .shadow(color: Color.brandBlue.opacity(0.22), radius: 22, y: 10)
    }
}
