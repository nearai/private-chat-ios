import Foundation

@MainActor
final class AgentStore: ObservableObject {
    @Published var ironclawSettings = IronclawSettings.default {
        didSet {
            guard shouldPersist else { return }
            settingsPersistence.saveIronclawSettings(ironclawSettings)
        }
    }
    @Published var ironclawTokenConfigured = false
    @Published var ironclawStatusText = "Not connected"
    @Published var ironclawLastVerifiedAt: Date?
    @Published var ironclawToolNames: [String] = []
    @Published var isTestingIntegration = false
    @Published var isTestingIronclawWorkstation = false
    @Published var pendingHostedHandoffPreflight: HostedIronclawHandoffPreflight?

    static let verifiedRebornToolNames = ["shell", "git"]

    var bannerHandler: ((String) -> Void)?
    var routeInvalidatedHandler: (() -> Void)?
    var hostedRouteDisabledHandler: (() -> Void)?

    private let ironclawAPI: IronclawAPI
    private var accountID: String
    private var shouldPersist = true

    init(
        ironclawAPI: IronclawAPI = IronclawAPI(),
        accountID: String = AccountStorageScope.signedOutAccountID
    ) {
        self.ironclawAPI = ironclawAPI
        self.accountID = AccountStorageScope.resolvedAccountID(for: accountID)
        loadAccountScopedState()
    }

    var ironclawRemoteWorkstationAvailable: Bool {
        ironclawSettings.hasUsableHostedEndpoint && ironclawSettings.isEnabled
    }

    func configure(accountID: String) {
        let resolvedAccountID = AccountStorageScope.resolvedAccountID(for: accountID)
        guard resolvedAccountID != self.accountID else {
            loadAccountScopedState()
            return
        }
        self.accountID = resolvedAccountID
        loadAccountScopedState()
    }

    func reset() {
        shouldPersist = false
        ironclawSettings = .default
        shouldPersist = true
        ironclawTokenConfigured = false
        ironclawStatusText = "Not connected"
        ironclawLastVerifiedAt = nil
        ironclawToolNames = []
        isTestingIntegration = false
        isTestingIronclawWorkstation = false
        pendingHostedHandoffPreflight = nil
    }

    func saveIronclawIntegration(
        isEnabled: Bool,
        baseURL: String,
        authToken: String,
        threadID: String
    ) {
        let requestedSettings = IronclawSettings(
            isEnabled: isEnabled,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            threadID: threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let savedSettings = requestedSettings.standalonePhoneSanitized
        ironclawSettings = savedSettings
        if savedSettings.hasUsableHostedEndpoint {
            routeInvalidatedHandler?()
        }

        let trimmedToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            do {
                try settingsPersistence.saveIronclawAuthToken(trimmedToken)
                ironclawTokenConfigured = true
            } catch {
                let message = Self.displayFailureMessage(error.localizedDescription)
                ironclawStatusText = message
                showBanner(message)
                return
            }
        }

        if !savedSettings.isEnabled {
            hostedRouteDisabledHandler?()
        }

        if isEnabled, let validationMessage = requestedSettings.endpointValidationMessage {
            ironclawStatusText = validationMessage
            ironclawLastVerifiedAt = nil
            showBanner(validationMessage)
            return
        }

        if savedSettings.hasUsableHostedEndpoint {
            ironclawStatusText = ironclawTokenConfigured ? "Hosted IronClaw URL and token saved." : "Hosted IronClaw URL saved."
            showBanner(savedSettings.isEnabled ? "Hosted IronClaw enabled." : "Agent connection saved.")
        } else {
            ironclawStatusText = ironclawTokenConfigured ? "Agent token saved. Add Hosted IronClaw URL." : "Not connected"
            showBanner("Agent settings saved.")
        }
    }

    func disconnectIronclaw() {
        settingsPersistence.deleteIronclawAuthToken()
        ironclawTokenConfigured = false
        ironclawSettings.isEnabled = false
        ironclawStatusText = "Not connected"
        ironclawLastVerifiedAt = nil
        ironclawToolNames = []
        hostedRouteDisabledHandler?()
        routeInvalidatedHandler?()
        showBanner("Agent disconnected.")
    }

    func testIronclawConnection() async {
        guard ironclawSettings.hasUsableHostedEndpoint else {
            let message = ironclawSettings.endpointValidationMessage ?? "Add a Hosted IronClaw URL first."
            ironclawStatusText = message
            showBanner(message)
            return
        }
        isTestingIntegration = true
        defer { isTestingIntegration = false }
        do {
            let message = try await ironclawAPI.testConnection(
                settings: ironclawSettings,
                authToken: loadIronclawAuthToken()
            )
            ironclawStatusText = message
            await refreshIronclawTools()
            showBanner("Hosted IronClaw reachable.")
        } catch {
            let message = Self.displayFailureMessage(error.localizedDescription)
            ironclawStatusText = message
            showBanner(message)
        }
    }

    func testIronclawWorkstation() async {
        guard ironclawSettings.hasUsableHostedEndpoint else {
            let message = ironclawSettings.endpointValidationMessage ?? "Add a Hosted IronClaw URL first."
            ironclawStatusText = message
            showBanner(message)
            return
        }
        isTestingIronclawWorkstation = true
        defer { isTestingIronclawWorkstation = false }
        do {
            let message = try await ironclawAPI.testWorkstationCapability(
                settings: ironclawSettings,
                authToken: loadIronclawAuthToken()
            )
            ironclawStatusText = message
            ironclawLastVerifiedAt = Date()
            await refreshIronclawTools()
            if ironclawToolNames.isEmpty {
                ironclawToolNames = Self.verifiedRebornToolNames
            }
            showBanner("Hosted IronClaw tools checked.")
        } catch {
            let message = Self.displayFailureMessage(error.localizedDescription)
            ironclawStatusText = message
            showBanner(message)
        }
    }

    func refreshIronclawTools() async {
        guard ironclawSettings.hasUsableHostedEndpoint else {
            ironclawToolNames = []
            return
        }
        do {
            ironclawToolNames = try await ironclawAPI.fetchToolNames(
                settings: ironclawSettings,
                authToken: loadIronclawAuthToken()
            )
            if ironclawToolNames.isEmpty, ironclawLastVerifiedAt != nil {
                ironclawToolNames = Self.verifiedRebornToolNames
            }
        } catch {
            ironclawToolNames = ironclawLastVerifiedAt == nil ? [] : Self.verifiedRebornToolNames
        }
    }

    func loadIronclawAuthToken() -> String? {
        settingsPersistence.loadIronclawAuthToken()
    }

    func ironclawSettings(for conversationID: String) -> IronclawSettings {
        var settings = ironclawSettings
        let configuredThreadID = settings.threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        if configuredThreadID.isEmpty, let mappedThreadID = loadIronclawThreadID(for: conversationID) {
            settings.threadID = mappedThreadID
        }
        return settings
    }

    func hostedHandoffPreflight(
        text: String,
        promptAttachments: [ChatAttachment],
        selectedModelID: String,
        promptNeedsHostedWorkstation: Bool,
        projectDisclosure: ProjectHostedHandoffDisclosure?
    ) -> HostedIronclawHandoffPreflight? {
        guard ironclawRemoteWorkstationAvailable else { return nil }
        let willUseHosted = selectedModelID == ModelOption.ironclawModelID ||
            (selectedModelID == ModelOption.ironclawMobileModelID && promptNeedsHostedWorkstation)
        guard willUseHosted else { return nil }

        var disclosedItems = ["Prompt text: \(text.utf8.count) bytes"]
        let attachmentDisclosure = HostedIronclawAttachmentDisclosure.promptFiles(promptAttachments)
        if let disclosedItem = attachmentDisclosure.disclosedItem {
            disclosedItems.append(disclosedItem)
        }
        if let projectDisclosure {
            disclosedItems.append(contentsOf: projectDisclosure.disclosedItems)
        }

        let rawFingerprint = [
            selectedModelID,
            ironclawSettings.normalizedBaseURL,
            text,
            attachmentDisclosure.fingerprint,
            projectDisclosure?.fingerprint ?? ""
        ].joined(separator: "|~|")
        let host = URL(string: ironclawSettings.normalizedBaseURL)?.host ?? "Hosted IronClaw"
        return HostedIronclawHandoffPreflight(
            fingerprint: String(rawFingerprint.hashValue),
            destinationHost: host,
            promptPreview: Self.clipped(text, maxCharacters: 500),
            disclosedItems: disclosedItems
        )
    }

    func loadIronclawThreadID(for conversationID: String) -> String? {
        agentThreadPersistence.loadThreadID(for: conversationID)
    }

    func loadIronclawThreadIDCache() -> [String: String] {
        agentThreadPersistence.loadCache()
    }

    @discardableResult
    func saveIronclawThreadIDCache(_ cache: [String: String]) -> Bool {
        let didSave = agentThreadPersistence.saveCache(cache)
        if !didSave {
            showBanner("IronClaw thread cache could not be saved securely.")
        }
        return didSave
    }

    @discardableResult
    func rememberIronclawThreadID(_ threadID: String, for conversationID: String) -> Bool {
        let trimmed = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var cache = loadIronclawThreadIDCache()
        guard cache[conversationID] != trimmed else {
            ironclawStatusText = "Using thread \(String(trimmed.prefix(8)))."
            return true
        }
        cache[conversationID] = trimmed
        let didSave = saveIronclawThreadIDCache(cache)
        if didSave {
            ironclawStatusText = "Using thread \(String(trimmed.prefix(8)))."
        }
        return didSave
    }

    @discardableResult
    func removeIronclawThreadID(for conversationID: String) -> Bool {
        var cache = loadIronclawThreadIDCache()
        cache.removeValue(forKey: conversationID)
        return saveIronclawThreadIDCache(cache)
    }

    func applyConnectionDiagnosticStatus(_ message: String) {
        ironclawStatusText = message
    }

    func applyWorkstationDiagnosticSuccess(_ message: String) {
        ironclawStatusText = message
        ironclawLastVerifiedAt = Date()
    }

    private func loadAccountScopedState() {
        agentThreadPersistence.ensureMappingMigrationFlagSet()
        let loadedIronclawSettings = settingsPersistence.loadIronclawSettings()
        shouldPersist = false
        ironclawSettings = loadedIronclawSettings
        shouldPersist = true
        ironclawTokenConfigured = loadIronclawAuthToken()?.isEmpty == false

        if loadedIronclawSettings.hasUsableHostedEndpoint {
            ironclawStatusText = ironclawTokenConfigured ? "Hosted IronClaw URL and token saved." : "Hosted IronClaw URL saved."
        } else if loadedIronclawSettings.hasEndpoint {
            ironclawStatusText = loadedIronclawSettings.endpointValidationMessage ?? "Agent connection needs attention."
        } else if ironclawTokenConfigured {
            ironclawStatusText = "Agent token saved. Add Hosted IronClaw URL."
        } else {
            ironclawStatusText = "Not connected"
        }
        ironclawLastVerifiedAt = nil
        ironclawToolNames = []
    }

    private var settingsPersistence: SettingsPersistence {
        SettingsPersistence(accountID: accountID)
    }

    private var agentThreadPersistence: AgentThreadPersistence {
        AgentThreadPersistence(accountID: accountID)
    }

    private func showBanner(_ message: String) {
        bannerHandler?(message)
    }

    private static func displayFailureMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains("missing authorization header") ||
            trimmed.localizedCaseInsensitiveContains("invalid or expired authentication token") {
            return "Authentication is missing or expired. Sign in again, then retry."
        }
        return trimmed.isEmpty ? "Request failed." : trimmed
    }

    static func phoneAgentMissionPrompt(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if trimmed.localizedCaseInsensitiveContains("Agent Mission:") ||
            trimmed.localizedCaseInsensitiveContains("Hosted IronClaw Mission:") {
            return nil
        }

        let brief = strippedAgentLaunchPrefix(from: trimmed)
        let mission = phoneAgentMissionKind(for: brief)
        let skillPrompt = IronclawSkillCatalog.promptSection(for: brief)
        return """
        Hosted IronClaw Mission: \(mission.title)

        Mission brief from phone:
        \(brief)

        Execution contract:
        \(mission.executionContract)

        IronClaw skill routing:
        \(mission.skillRoutingHint)
        \(skillPrompt)

        Phone run contract:
        - Result first; do not echo this contract back to the user.
        - Keep commands bounded with timeouts and explain any skipped step.
        - Do not commit, push, or open a PR unless I explicitly ask.
        - Return Commands, Changed Files, Tests, Risk, and Next Actions.
        """
    }

    static func agentMissionBrief(from text: String) -> String? {
        guard let briefRange = text.range(of: "Mission brief from phone:", options: [.caseInsensitive]) else {
            return nil
        }
        let afterBrief = text[briefRange.upperBound...]
        let endRange = afterBrief.range(of: "Execution contract:", options: [.caseInsensitive])
        let rawBrief = endRange.map { String(afterBrief[..<$0.lowerBound]) } ?? String(afterBrief)
        let normalizedBrief = rawBrief
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*` -").union(.whitespacesAndNewlines))
        guard !normalizedBrief.isEmpty else {
            return nil
        }
        return normalizedBrief
    }

    static func strippedAgentLaunchPrefix(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "Hosted IronClaw:",
            "IronClaw Mobile:",
            "Agent mission:",
            "On-device Agent:",
            "Agent:"
        ]
        for prefix in prefixes where trimmed.lowercased().hasPrefix(prefix.lowercased()) {
            let start = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
            let stripped = trimmed[start...].trimmingCharacters(in: .whitespacesAndNewlines)
            return stripped.isEmpty ? trimmed : stripped
        }
        return trimmed
    }

    static func firstRepoURL(in text: String) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:(?:https?://)?(?:www\.)?)?(?:github\.com|gitlab\.com|bitbucket\.org)/[^\s,;)"']+"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        let rawURL = String(text[matchRange])
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
        return ProjectService.normalizedProjectLinkURL(rawURL)
    }

    static func repoProjectName(from url: URL) -> String? {
        guard let host = url.host()?.lowercased(), !host.isEmpty else {
            return nil
        }
        let pathParts = url.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard pathParts.count >= 2 else {
            return nil
        }

        let owner = cleanProjectName(pathParts[0])
        let repo = cleanProjectName(strippedGitSuffix(pathParts[1]))
        guard let owner, let repo else {
            return nil
        }
        return "\(owner)/\(repo)"
    }

    static func repoRootURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let pathParts = components.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard pathParts.count >= 2 else {
            return nil
        }
        components.path = "/\(pathParts[0])/\(strippedGitSuffix(pathParts[1]))"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func repoTaskLinkTitle(from url: URL, projectName: String) -> String {
        let pathParts = url.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard pathParts.count >= 4 else {
            return "Task link"
        }

        let kind = pathParts[2].lowercased()
        let identifier = pathParts[3]
        switch kind {
        case "issues":
            return "Issue #\(identifier)"
        case "pull", "pulls":
            return "PR #\(identifier)"
        case "merge_requests":
            return "MR #\(identifier)"
        case "commit", "commits":
            return "Commit \(String(identifier.prefix(8)))"
        case "tree":
            return "Branch \(identifier)"
        case "blob":
            return "File in \(projectName)"
        default:
            return "Task link"
        }
    }

    static func normalizedIronclawPrompt(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let prefixes = [
            "use ironclaw to ",
            "ask ironclaw to ",
            "have ironclaw ",
            "run ironclaw to "
        ]

        for prefix in prefixes where lowercased.hasPrefix(prefix) {
            let start = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
            let normalized = trimmed[start...].trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? text : normalized
        }

        return text
    }

    static func ironclawToolResultMarkdown(_ results: [IronclawMobileToolResult]) -> String {
        guard !results.isEmpty else { return "" }
        let blocks = results.map { result in
            var lines = [result.markdownLine]
            if let detail = result.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
               !detail.isEmpty {
                let maxCharacters = result.callName == IronclawMobileToolNames.runtimeCapabilities ? 1_200 : 900
                let clippedDetail = clipped(detail, maxCharacters: maxCharacters)
                let visibleLines = clippedDetail
                    .split(whereSeparator: \.isNewline)
                    .prefix(12)
                    .map { "  \($0)" }
                    .joined(separator: "\n")
                if !visibleLines.isEmpty {
                    lines.append(visibleLines)
                }
            }
            return lines.joined(separator: "\n")
        }
        return "**IronClaw Mobile actions**\n\(blocks.joined(separator: "\n"))\n\n"
    }

    static var ironclawMobileCapabilityDetail: String {
        """
        Available on iPhone:
        - NEAR Private inference with model fallback.
        - NEAR Private web search when enabled.
        - Prompt files and reusable project file context.
        - Local project creation and selection.
        - Source link capture, project instructions, project memory, and project notes.
        - File promotion into reusable project context.
        - Chat move, rename, pin, and archive actions.
        - Web-search, source-mode, and research-mode switching.

        Hosted IronClaw handoff:
        - When Hosted IronClaw is connected, Mobile can hand off git, code editing, tests, shell, package installation, and repo work and keep the answer in this chat.
        - Hosted IronClaw is expected to provide sandboxed shell, git, file read/write, grep, and patch tools; Account diagnostics can check those tools before a serious run.

        Not available locally inside the iOS sandbox:
        - Shell commands, Docker, Postgres, arbitrary host filesystem access, local LAN gateways, desktop daemons, and unsandboxed MCP/WASM tool execution.
        """
    }

    private static func cleanProjectName(_ rawName: String) -> String? {
        let trimmed = rawName
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(80))
    }

    private static func strippedGitSuffix(_ value: String) -> String {
        value.replacingOccurrences(of: #"\.git$"#, with: "", options: .regularExpression)
    }

    private static func phoneAgentMissionKind(for text: String) -> PhoneAgentMissionKind {
        let lowercased = text.lowercased()
        let hasSecurityIntent = [
            "security review",
            "security audit",
            "vulnerability",
            "vulnerabilities",
            "threat model",
            "secrets",
            "secret leak",
            "auth bug",
            "permission bug",
            "ssrf",
            "xss",
            "injection"
        ].contains { lowercased.contains($0) }
        let hasQAIntent = [
            "qa review",
            "qa pass",
            "quality assurance",
            "test plan",
            "manual qa",
            "smoke test",
            "web ui test",
            "browser test",
            "repro steps"
        ].contains { lowercased.contains($0) }
        let hasPlanningIntent = [
            "plan",
            "break down",
            "architecture",
            "technical design",
            "design doc",
            "scope this",
            "implementation plan"
        ].contains { lowercased.contains($0) }
        let hasProductPrioritizationIntent = [
            "prioritize",
            "prioritization",
            "roadmap",
            "what should we build",
            "product strategy",
            "rank these",
            "feature priority"
        ].contains { lowercased.contains($0) }
        let hasDecisionCaptureIntent = [
            "decision",
            "decisions",
            "decision log",
            "capture this",
            "adr",
            "record the decision"
        ].contains { lowercased.contains($0) }
        let hasResearchIntent = [
            "research",
            "latest",
            "current",
            "news",
            "web search",
            "search the web",
            "sources",
            "cite"
        ].contains { lowercased.contains($0) }
        let hasGithubTriageIntent = [
            "issue",
            "issues",
            "/issues/",
            "/pull/",
            "/pulls/",
            "/merge_requests/",
            "pull request",
            "pr ",
            "review",
            "audit",
            "triage"
        ].contains { lowercased.contains($0) }
        let hasCodeReviewIntent = hasGithubTriageIntent && [
            "code review",
            "review this pr",
            "review this pull",
            "review the diff",
            "review the repo",
            "review this repo",
            "audit the repo"
        ].contains { lowercased.contains($0) }
        let hasSetupIntent = [
            "clone",
            "set up",
            "setup",
            "install",
            "bootstrap",
            "get this running"
        ].contains { lowercased.contains($0) }
        let hasPatchIntent = [
            "fix",
            "implement",
            "edit",
            "modify",
            "patch",
            "refactor",
            "write",
            "build",
            "test"
        ].contains { lowercased.contains($0) }

        if hasSecurityIntent {
            return .securityReview
        }
        if hasQAIntent {
            return .qaReview
        }
        if hasProductPrioritizationIntent {
            return .productPrioritization
        }
        if hasDecisionCaptureIntent {
            return .decisionCapture
        }
        if hasPlanningIntent && !hasPatchIntent {
            return .planMode
        }
        if hasResearchIntent {
            return .researchToCode
        }
        if hasCodeReviewIntent {
            return .codeReview
        }
        if hasGithubTriageIntent {
            return .githubTriage
        }
        if hasSetupIntent && !hasPatchIntent {
            return .repoSetup
        }
        return .patchAndTest
    }

    private static func clipped(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: maxCharacters)
        return "\(text[..<endIndex])..."
    }

    private enum PhoneAgentMissionKind {
        case repoSetup
        case patchAndTest
        case researchToCode
        case githubTriage
        case codeReview
        case securityReview
        case qaReview
        case planMode
        case productPrioritization
        case decisionCapture

        var title: String {
            switch self {
            case .repoSetup:
                return "Repo Setup"
            case .patchAndTest:
                return "Patch + Test"
            case .researchToCode:
                return "Research To Code"
            case .githubTriage:
                return "GitHub Triage"
            case .codeReview:
                return "Code Review"
            case .securityReview:
                return "Security Review"
            case .qaReview:
                return "QA Review"
            case .planMode:
                return "Plan Mode"
            case .productPrioritization:
                return "Product Prioritization"
            case .decisionCapture:
                return "Decision Capture"
            }
        }

        var executionContract: String {
            switch self {
            case .repoSetup:
                return "Clone or inspect the repo, identify the stack, install only required dependencies, and report the exact run/test command path."
            case .patchAndTest:
                return "Inspect the relevant files, make the smallest useful patch, run focused tests or static checks with timeouts, and explain any remaining gap."
            case .researchToCode:
                return "Call nearai_web_search first when fresh sources are needed, convert findings into a concrete repo plan, then patch and test only when the repo context is available."
            case .githubTriage:
                return "Use IronClaw's GitHub and software-agent tools to inspect linked issues, PRs, or repo context, then produce a prioritized action plan with any safe patch or test result."
            case .codeReview:
                return "Review the linked repo, PR, diff, or files for correctness bugs, regressions, missing tests, and maintainability risks. Lead with findings by severity and include file/line references when available."
            case .securityReview:
                return "Perform a security-focused review for auth, secrets, injection, SSRF, permission boundaries, dependency risk, and unsafe network/file access. Separate confirmed issues from hypotheses and include concrete mitigations."
            case .qaReview:
                return "Design and run the smallest meaningful QA pass: identify critical flows, execute available tests or browser checks, capture repro steps for failures, and report pass/fail evidence."
            case .planMode:
                return "Clarify the goal from existing context, split the work into small verifiable steps, call out risks and dependencies, then recommend the next implementation step without overbuilding."
            case .productPrioritization:
                return "Rank candidate product work by user impact, confidence, effort, and dependency risk. Prefer concrete next shippable increments over broad feature catalogs."
            case .decisionCapture:
                return "Extract durable decisions, assumptions, owners, open questions, and follow-ups from the brief or repo context. Keep it terse enough to paste into a project note."
            }
        }

        var skillRoutingHint: String {
            switch self {
            case .repoSetup:
                return "Use the IronClaw project-setup, developer-setup, or new-project skill behavior when available."
            case .patchAndTest:
                return "Use the IronClaw coding and local-test skill behavior when available."
            case .researchToCode:
                return "Use the IronClaw coding, github-workflow, and web research behavior when available."
            case .githubTriage:
                return "Use the IronClaw github, github-workflow, delegation, and review-checklist skill behavior when available."
            case .codeReview:
                return "Use the IronClaw code-review and review-readiness skill behavior when available."
            case .securityReview:
                return "Use the IronClaw security-review skill behavior when available."
            case .qaReview:
                return "Use the IronClaw qa-review, web-ui-test, and local-test skill behavior when available."
            case .planMode:
                return "Use the IronClaw plan-mode skill behavior when available."
            case .productPrioritization:
                return "Use the IronClaw product-prioritization skill behavior when available."
            case .decisionCapture:
                return "Use the IronClaw decision-capture, commitment-triage, idea-parking, and tech-debt-tracker skill behavior when available."
            }
        }
    }
}
