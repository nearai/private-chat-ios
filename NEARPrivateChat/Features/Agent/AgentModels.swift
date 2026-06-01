import Foundation
import SwiftUI

struct IronclawSkillProfile: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let symbolName: String
    let keywords: [String]

    func missionPrompt(seed: String = "", projectName: String? = nil) -> String {
        let trimmedSeed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectLead: String
        if let projectName = projectName?.trimmingCharacters(in: .whitespacesAndNewlines), !projectName.isEmpty {
            projectLead = "Use the \(projectName) project context when it helps. "
        } else {
            projectLead = ""
        }

        func prompt(_ blankPrompt: String, _ seededPrefix: String, suffix: String) -> String {
            if trimmedSeed.isEmpty {
                return "\(projectLead)\(blankPrompt) \(suffix)"
            }
            return "\(projectLead)\(seededPrefix): \(trimmedSeed). \(suffix)"
        }

        switch id {
        case "coding":
            return prompt(
                "Inspect this code task.",
                "Implement this change safely",
                suffix: "Inspect the repo first, make the smallest useful patch, run focused tests, and report changed files plus remaining risks."
            )
        case "local-test":
            return prompt(
                "Run focused verification on this work.",
                "Verify this safely",
                suffix: "Choose the smallest useful build, test, or smoke checks, capture failures clearly, and summarize what still needs manual QA."
            )
        case "github-workflow":
            return prompt(
                "Triage this GitHub work.",
                "Handle this GitHub task",
                suffix: "Inspect the issue, PR, or CI context first, identify the highest-impact next action, and report the concrete follow-up."
            )
        case "github":
            return prompt(
                "Inspect the linked GitHub context.",
                "Work from this GitHub context",
                suffix: "Read the repo, issue, PR, or Actions context first, then summarize the important state, risks, and the next concrete action."
            )
        case "code-review":
            return prompt(
                "Review this code for correctness.",
                "Review this code carefully",
                suffix: "Prioritize bugs, regressions, and missing tests. Lead with findings and keep the summary brief."
            )
        case "security-review":
            return prompt(
                "Review this for security risk.",
                "Audit this for security risk",
                suffix: "Focus on auth, secrets, injection, data exposure, and permission boundaries. Call out concrete exploit paths and fixes."
            )
        case "qa-review":
            return prompt(
                "Create a focused QA pass for this workflow.",
                "Plan QA for this workflow",
                suffix: "List repro steps, edge cases, expected outcomes, and the smallest evidence set needed to validate the result."
            )
        case "web-ui-test":
            return prompt(
                "Test this web UI flow.",
                "Test this browser workflow",
                suffix: "Focus on the critical user path, run the smallest useful browser checks, capture repro-ready failures, and note what still needs manual device QA."
            )
        case "project-setup":
            return prompt(
                "Set up this Project.",
                "Turn this into a tracked Project",
                suffix: "Identify the files, links, instructions, and first task the project should contain, then suggest the cleanest next action."
            )
        case "developer-setup":
            return prompt(
                "Set up this developer environment.",
                "Prepare this repo for development",
                suffix: "Inspect the stack first, identify the exact setup and run commands, call out required credentials or services, and keep the first run path as small as possible."
            )
        case "new-project":
            return prompt(
                "Turn this idea into a new project.",
                "Turn this into a new project",
                suffix: "Define the scope, starter structure, durable notes, and the first milestone before any broad implementation plan."
            )
        case "plan-mode":
            return prompt(
                "Break this work into a verifiable plan.",
                "Plan this carefully",
                suffix: "Split the work into concrete steps, dependencies, risks, and the next smallest useful action without overbuilding."
            )
        case "review-readiness":
            return prompt(
                "Check whether this work is ready for review.",
                "Check review readiness for this",
                suffix: "Inspect the diff, validation status, and remaining risk, then call out the blockers before anyone else reviews it."
            )
        case "llm-council":
            return prompt(
                "Compare multiple model perspectives on this decision.",
                "Run a council-style comparison for this",
                suffix: "Surface strongest agreements, disagreements, and the recommended decision with tradeoffs."
            )
        case "product-prioritization":
            return prompt(
                "Prioritize this product work.",
                "Prioritize this product work",
                suffix: "Rank the options by impact, evidence, effort, and user value, then recommend the highest-leverage next move."
            )
        case "decision-capture":
            return prompt(
                "Capture this decision clearly.",
                "Capture this decision",
                suffix: "Summarize the decision, rationale, alternatives considered, open questions, and follow-up actions."
            )
        case "delegation":
            return prompt(
                "Turn this into a delegated task.",
                "Delegate this work clearly",
                suffix: "Define the assignee-ready brief, expected outcome, dependencies, risks, and the exact follow-up checkpoint."
            )
        case "idea-parking":
            return prompt(
                "Park this idea without losing it.",
                "Capture this idea for later",
                suffix: "Record the core concept, why it matters, the trigger for revisiting it, and what evidence is still missing."
            )
        case "commitment-triage":
            return prompt(
                "Extract the commitments from this work.",
                "Extract commitments from this",
                suffix: "List owners, deadlines, promised deliverables, risks, and the next follow-up checkpoint."
            )
        case "tech-debt-tracker":
            return prompt(
                "Capture the technical debt in this work.",
                "Track this technical debt",
                suffix: "List the debt item, impact, risk if deferred, suggested owner, and the smallest remediation step."
            )
        case "review-checklist":
            return prompt(
                "Create a review checklist for this change.",
                "Create a review checklist for this",
                suffix: "Call out correctness, test coverage, rollout, docs, and follow-up checks so the handoff is easy to verify."
            )
        case "portfolio":
            return prompt(
                "Review this portfolio.",
                "Review this portfolio",
                suffix: "Summarize positions, risks, rebalancing ideas, and what additional live market context is needed before acting."
            )
        default:
            return prompt(
                "Help with this task.",
                "Help with this task",
                suffix: "Inspect the available context first, choose the smallest useful path, and return concrete next actions."
            )
        }
    }
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
            keywords: ["local test", "smoke check", "run tests", "build verification", "regression suite"]
        ),
        IronclawSkillProfile(
            id: "github-workflow",
            title: "GitHub Workflow",
            summary: "Handle issues, PRs, CI failures, and repo handoff.",
            symbolName: "arrow.triangle.branch",
            keywords: ["github", "issue", "pull request", " pr ", "/pull/", "/issues/", "ci", "branch"]
        ),
        IronclawSkillProfile(
            id: "github",
            title: "GitHub",
            summary: "Inspect repo, issue, PR, and Actions context before acting.",
            symbolName: "chevron.left.forwardslash.chevron.right.circle",
            keywords: ["github repo", "repository", "repo context", "actions", "workflow run", "issue thread", "pr context"]
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
            id: "web-ui-test",
            title: "Web UI Test",
            summary: "Run browser-focused QA for critical flows and regressions.",
            symbolName: "safari",
            keywords: ["playwright", "browser flow", "ui regression", "web ui", "frontend qa", "e2e"]
        ),
        IronclawSkillProfile(
            id: "project-setup",
            title: "Project Setup",
            summary: "Turn a repo or new idea into a tracked Project.",
            symbolName: "folder.badge.gearshape",
            keywords: ["setup", "set up", "clone", "bootstrap", "new project", "repo"]
        ),
        IronclawSkillProfile(
            id: "developer-setup",
            title: "Developer Setup",
            summary: "Map the exact bootstrap, install, and run path for a repo.",
            symbolName: "hammer",
            keywords: ["developer setup", "dev environment", "bootstrap repo", "install dependencies", "run locally", "onboard repo"]
        ),
        IronclawSkillProfile(
            id: "new-project",
            title: "New Project",
            summary: "Shape a fresh Project, scope, and first milestone.",
            symbolName: "sparkles.rectangle.stack",
            keywords: ["new project", "start a project", "greenfield", "workspace", "organize project"]
        ),
        IronclawSkillProfile(
            id: "plan-mode",
            title: "Plan Mode",
            summary: "Break work into concrete, verifiable next steps.",
            symbolName: "list.bullet.clipboard",
            keywords: ["plan mode", "break this down", "step by step", "implementation plan", "work plan", "roadmap"]
        ),
        IronclawSkillProfile(
            id: "review-readiness",
            title: "Review Readiness",
            summary: "Check whether validation and context are solid before review.",
            symbolName: "checkmark.message",
            keywords: ["ready for review", "review readiness", "before merge", "pre review", "handoff"]
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
            id: "delegation",
            title: "Delegation",
            summary: "Turn work into a clear assignee-ready brief and follow-up.",
            symbolName: "person.2.badge.gearshape",
            keywords: ["delegate", "delegation", "assign this", "handoff", "owner handoff", "handover"]
        ),
        IronclawSkillProfile(
            id: "idea-parking",
            title: "Idea Parking",
            summary: "Capture ideas, triggers, and missing evidence without derailing the current task.",
            symbolName: "lightbulb",
            keywords: ["idea parking", "park this idea", "later idea", "parking lot", "backlog idea", "save this idea"]
        ),
        IronclawSkillProfile(
            id: "commitment-triage",
            title: "Commitment Triage",
            summary: "Extract obligations, owners, deadlines, and next steps.",
            symbolName: "person.crop.circle.badge.checkmark",
            keywords: ["commitment", "follow up", "deadline", "owner", "delegate", "nudge"]
        ),
        IronclawSkillProfile(
            id: "tech-debt-tracker",
            title: "Tech Debt Tracker",
            summary: "Capture debt items, impact, and the next remediation step.",
            symbolName: "wrench.and.screwdriver",
            keywords: ["tech debt", "technical debt", "cleanup later", "refactor later", "debt item", "deferred fix"]
        ),
        IronclawSkillProfile(
            id: "review-checklist",
            title: "Review Checklist",
            summary: "Create a concise ship checklist before review or handoff.",
            symbolName: "list.clipboard",
            keywords: ["review checklist", "ship checklist", "merge checklist", "preflight checklist", "release checklist"]
        ),
        IronclawSkillProfile(
            id: "portfolio",
            title: "Portfolio",
            summary: "Inspect DeFi positions and NEAR intent opportunities.",
            symbolName: "chart.pie",
            keywords: ["wallet", "portfolio", "yield", "rebalance", "defi", "near intent", "trading"]
        )
    ]

    static func matchingSkills(for text: String, limit: Int? = nil) -> [IronclawSkillProfile] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let matches = scoredMatches(for: trimmed)
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.skill.title < rhs.skill.title
                }
                return lhs.score > rhs.score
            }
            .map(\.skill)

        if let limit {
            return Array(matches.prefix(limit))
        }
        return matches
    }

    static func matchingSkillIDs(for text: String, limit: Int? = nil) -> [String] {
        matchingSkills(for: text, limit: limit).map(\.id)
    }

    static func suggestedSkills(for text: String, limit: Int = 4) -> [IronclawSkillProfile] {
        let lowercased = text.lowercased()
        let matches = matchingSkills(for: text, limit: limit)
        if !matches.isEmpty {
            return matches
        }

        if lowercased.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(all.filter { ["coding", "github-workflow", "local-test"].contains($0.id) }.prefix(limit))
        }

        return Array(all.filter { ["coding", "local-test", "project-setup"].contains($0.id) }.prefix(limit))
    }

    static func profiles(for ids: [String], limit: Int? = nil) -> [IronclawSkillProfile] {
        var seen = Set<String>()
        var profiles: [IronclawSkillProfile] = []

        for id in ids {
            guard seen.insert(id).inserted,
                  let profile = all.first(where: { $0.id == id }) else {
                continue
            }
            profiles.append(profile)
            if let limit, profiles.count >= limit {
                break
            }
        }

        return profiles
    }

    static func promptSection(for text: String) -> String {
        let skills = suggestedSkills(for: text, limit: 5)
        guard !skills.isEmpty else { return "" }
        let lines = skills.map { "- \($0.id): \($0.summary)" }.joined(separator: "\n")
        return """
        Agent skills to consider:
        \(lines)

        Select the useful skills internally. Do not print the routing unless the user asks how the agent chose its approach.
        """
    }

    private static func scoredMatches(for text: String) -> [(skill: IronclawSkillProfile, score: Int)] {
        let lowercased = text.lowercased()
        return all.map { skill -> (skill: IronclawSkillProfile, score: Int) in
            let score = skill.keywords.reduce(0) { partial, keyword in
                partial + (lowercased.contains(keyword) ? 1 : 0)
            }
            return (skill, score)
        }
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
            return "Add a credential for \(authenticationDisplayName) so Hosted IronClaw can continue this tool call."
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
        return "Always is disabled on phone for powerful hosted tools. Approve each run so command, network, file, and credential access stays scoped."
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
            return "Add a Hosted IronClaw URL first."
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return "Enter a valid Hosted IronClaw HTTPS URL."
        }
        if Self.retiredLocalDefaults.contains(trimmed) || !URLSecurity.isPublicHost(host) {
            return "Use a Hosted IronClaw HTTPS URL. LAN gateways are local development only."
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
