import Foundation
import SwiftUI

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
