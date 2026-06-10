import Foundation

/// A failed private send the user can re-run through the privacy proxy with
/// one tap. Built only for restricted-route failures; never auto-applied —
/// switching a private turn to the cloud proxy is a per-turn, disclosed choice.
struct ProxyRetryOffer: Identifiable, Equatable {
    /// The failed assistant message this offer belongs to.
    let id: String
    let originalModelID: String
    /// Nil when no NEAR AI Cloud key is configured — the card then offers to
    /// add one instead of re-sending.
    let proxyModelID: String?
    let text: String
    let attachments: [ChatAttachment]
    let previousResponseID: String?
    let conversationID: String?
}

struct ChatRouteReadinessIssue: Identifiable, Hashable {
    enum BlockedRoute: String, Hashable {
        case nearCloud
        case hostedIronclaw
        case council
    }

    enum RecoveryAction: String, Hashable {
        case addNearCloudKey
        case configureIronClawEndpoint
        case switchToPrivate
        case editCouncilLineup
    }

    let route: BlockedRoute
    let title: String
    let message: String
    let recoveryAction: RecoveryAction
    let recoveryTitle: String

    var id: String { route.rawValue }
}

struct RoutePlanner {
    static func routeKind(forModelID modelID: String) -> ChatRouteKind {
        if modelID.hasPrefix(ModelOption.nearCloudModelPrefix) {
            return .nearCloud
        }
        if modelID == ModelOption.ironclawMobileModelID {
            return .ironclawMobile
        }
        if modelID == ModelOption.ironclawModelID {
            return .ironclawHosted
        }
        return .nearPrivate
    }

    static func routeReadinessIssue(
        selectedModelID: String,
        requestedCouncilModelIDs: [String],
        isCouncilRequested: Bool,
        nearCloudKeyConfigured: Bool,
        hostedIronclawEndpointUsable: Bool,
        hostedIronclawEndpointMessage: String? = nil
    ) -> ChatRouteReadinessIssue? {
        let councilModelIDs = uniqueStrings(
            requestedCouncilModelIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        ).filter { !$0.isEmpty }

        if isCouncilRequested, councilModelIDs.count < 2 {
            return ChatRouteReadinessIssue(
                route: .council,
                title: "Council needs two models",
                message: "Pick at least two usable Council models, or switch to a single private model. Your draft and attachments are kept.",
                recoveryAction: .editCouncilLineup,
                recoveryTitle: "Edit Council"
            )
        }

        let modelIDs = isCouncilRequested ? councilModelIDs : [selectedModelID]
        if modelIDs.contains(where: { routeKind(forModelID: $0) == .nearCloud }), !nearCloudKeyConfigured {
            return ChatRouteReadinessIssue(
                route: .nearCloud,
                title: "Connect NEAR AI Cloud",
                message: "Connect NEAR AI Cloud in Account to send on this route. Your draft and attachments are kept.",
                recoveryAction: .addNearCloudKey,
                recoveryTitle: "Add Key"
            )
        }

        if modelIDs.contains(where: { routeKind(forModelID: $0) == .ironclawHosted }), !hostedIronclawEndpointUsable {
            let endpointMessage = hostedIronclawEndpointMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = endpointMessage?.isEmpty == false ? endpointMessage! : "Add a Hosted IronClaw URL in Account to send."
            return ChatRouteReadinessIssue(
                route: .hostedIronclaw,
                title: "Hosted IronClaw connection required",
                message: "\(detail) Your draft and attachments are kept.",
                recoveryAction: .configureIronClawEndpoint,
                recoveryTitle: "Connect Agent"
            )
        }

        return nil
    }

    static func sourceRoutingSemantics(
        sourceMode: ChatSourceMode,
        researchModeEnabled: Bool,
        webSearchEnabled: Bool,
        route: ChatRouteKind
    ) -> ChatSourceRoutingSemantics {
        ChatSourceRoutingSemantics.evaluate(
            sourceMode: sourceMode,
            researchModeEnabled: researchModeEnabled,
            webSearchEnabled: webSearchEnabled,
            route: route
        )
    }

    static func promptSourcePrivacyOverride(
        for prompt: String,
        hasAttachments: Bool = false
    ) -> ChatPromptSourcePrivacyOverride {
        let normalized = " " + prompt
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) + " "
        let looseNormalized = " " + prompt
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) + " "

        func hasPhrase(_ phrase: String) -> Bool {
            let loosePhrase = phrase
                .lowercased()
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.contains(" \(phrase) ") ||
                (!loosePhrase.isEmpty && looseNormalized.contains(" \(loosePhrase) "))
        }

        let blocksWeb = [
            "no web", "without web", "no browsing", "do not browse", "don't browse",
            "dont browse", "no live web", "without live web",
            "do not search the web", "don't search the web", "no internet",
            "dont search the web", "without internet", "no online",
            "offline only", "do not use web", "don't use web", "dont use web",
            "do not go online", "don't go online", "dont go online",
            "do not look up", "don't look up", "dont look up"
        ].contains(where: hasPhrase)

        let fileOnly = [
            "only this file", "only the attached file", "only attached file",
            "use only attached", "use only this attached", "attached file only",
            "attachments only", "only these files", "these files only",
            "file only", "from this file only", "from the attached file only",
            "only this sheet", "only this spreadsheet", "only this workbook",
            "use the pdf only", "pdf only"
        ].contains(where: { phrase in
            normalized.contains(phrase)
        }) || (hasAttachments && blocksWeb && normalized.contains(" only "))

        let requiresPrivate = [
            "keep it private", "keep this private", "private only", "stay private",
            "private route", "near private only", "use near private", "stay on near private",
            "do not use cloud", "don't use cloud", "dont use cloud",
            "no cloud", "no cloud model", "no near ai cloud", "never cloud",
            "not cloud", "not hosted", "no hosted",
            "do not use hosted", "don't use hosted", "do not send to hosted",
            "do not send this to hosted", "don't send this to hosted",
            "do not send to cloud", "do not send this to cloud", "don't send this to cloud",
            "dont send to cloud", "do not send to near ai cloud", "don't send to near ai cloud",
            "on device only", "local only"
        ].contains(where: hasPhrase)

        return ChatPromptSourcePrivacyOverride(
            blocksWeb: blocksWeb || fileOnly,
            prefersFileOnly: fileOnly,
            requiresPrivateRoute: requiresPrivate
        )
    }

    static func promptNeedsLiveWeb(_ prompt: String) -> Bool {
        guard !promptSourcePrivacyOverride(for: prompt).blocksWeb else {
            return false
        }
        let lowercased = prompt.lowercased()
        let triggers = [
            "latest",
            "current",
            "currently",
            "today",
            "right now",
            "this week",
            "recent",
            "fresh",
            "live",
            "up to date",
            "up-to-date",
            "as of",
            "news",
            "web search",
            "search the web",
            "deep search",
            "deep research",
            "research",
            "look up",
            "investigate",
            "from sources",
            "source-backed",
            "browse",
            "cite",
            "citations",
            "citation",
            "sources",
            "source links"
        ]
        if triggers.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let valueCue = [
            "price", "prices", "value", "worth", "quote", "rate",
            "market cap", "floor price", "trading at"
        ].contains { lowercased.contains($0) }
        let liveAskCue = [
            "what", "how much", "find", "look up", "track", "monitor",
            "watch", "compare", "comparison", " vs ", " versus ",
            "price of", "price for", "prices of", "prices for", "value of", "cost of", "quote for"
        ].contains { lowercased.contains($0) }
        let endsWithValueCue =
            lowercased.range(of: #"\b(price|prices|value|worth|quote|rate)\??$"#, options: .regularExpression) != nil
        return valueCue && (liveAskCue || endsWithValueCue)
    }

    static func promptRequestsCouncil(_ prompt: String) -> Bool {
        let lowercased = prompt
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowercased.isEmpty else { return false }

        let directPhrases = [
            "llm council",
            "model council",
            "multi-model",
            "multi model",
            "multiple models",
            "several models",
            "council mode",
            "use council",
            "using council",
            "use the council",
            "ask the council",
            "run the council",
            "council review",
            "council answer",
            "ask different models",
            "ask multiple models",
            "run different models",
            "run multiple models",
            "all the models",
            "second opinion",
            "second opinions",
            "compare model answers",
            "compare answers from models",
            "consensus answer",
            "model consensus"
        ]
        if directPhrases.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let modelSurfaceExclusions = [
            "without changing models",
            "model picker",
            "model selection",
            "selected model",
            "route labels"
        ]
        if modelSurfaceExclusions.contains(where: { lowercased.contains($0) }) {
            return false
        }

        let comparisonWords = [
            "compare",
            "contrast",
            "debate",
            "cross-check",
            "cross check",
            "sanity check",
            "red team"
        ]
        let modelWords = [
            "model",
            "models",
            "answers",
            "responses",
            "opinions",
            "takes"
        ]
        return comparisonWords.contains { lowercased.contains($0) } &&
            modelWords.contains { lowercased.contains($0) }
    }

    static func promptNeedsRemoteWorkstation(_ prompt: String) -> Bool {
        let lowercased = prompt
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowercased.isEmpty else { return false }
        guard !promptForbidsRemoteWorkstation(lowercased) else { return false }

        let explicitAgentPhrases = [
            "use ironclaw",
            "ask ironclaw",
            "hosted ironclaw",
            "ironclaw agent",
            "coding agent",
            "software agent",
            "remote workstation",
            "hosted workstation",
            "agent mission:",
            "Phone Agent:",
            "run tests",
            "run the tests",
            "git status",
            "make changes",
            "fix the repo",
            "review the repo",
            "audit the repo",
            "clone and",
            "research to code",
            "research-to-code",
            "open a pr",
            "write software",
            "build software"
        ]
        if explicitAgentPhrases.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let remoteActions = [
            "agent",
            "agentic",
            "audit",
            "analyze",
            "review",
            "debug",
            "diagnose",
            "triage",
            "implement",
            "scaffold",
            "refactor",
            "run",
            "execute",
            "inspect",
            "clone",
            "checkout",
            "branch",
            "commit",
            "push",
            "pull",
            "open a pr",
            "create a pr",
            "make a pr",
            "pull request",
            "edit",
            "modify",
            "patch",
            "fix",
            "write",
            "build",
            "test",
            "ship",
            "install",
            "deploy",
            "ssh",
            "use git",
            "can you use",
            "from my phone"
        ]
        let remoteTargets = [
            "git ",
            " git",
            "git?",
            "git.",
            "github",
            "repo",
            "repository",
            " code ",
            "code?",
            "code.",
            "codebase",
            "source code",
            "source file",
            "pull request",
            "package.json",
            "requirements.txt",
            "unit test",
            "tests",
            "xcode",
            "swiftui",
            "write software",
            "build software",
            "software",
            "xcodebuild",
            "swift",
            "npm",
            "node ",
            "javascript",
            "typescript",
            "python",
            "pytest",
            "rust",
            "cargo",
            "terminal",
            "shell",
            "filesystem",
            "file system",
            "docker",
            "mcp",
            "workstation",
            "ironclaw hosted"
        ]
        let hasAction = remoteActions.contains { lowercased.contains($0) }
        let hasTarget = remoteTargets.contains { lowercased.contains($0) }
        return hasAction && hasTarget
    }

    static func modelAfterHostedAutoRoute(
        selectedModelID: String,
        text: String,
        hostedIronclawAvailable: Bool
    ) -> String {
        guard selectedModelID != ModelOption.ironclawModelID,
              selectedModelID != ModelOption.ironclawMobileModelID,
              !promptSourcePrivacyOverride(for: text).requiresPrivateRoute,
              promptNeedsRemoteWorkstation(text),
              hostedIronclawAvailable else {
            return selectedModelID
        }
        return ModelOption.ironclawModelID
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else {
                continue
            }
            output.append(trimmed)
        }
        return output
    }

    private static func promptForbidsRemoteWorkstation(_ lowercased: String) -> Bool {
        let hardStops = [
            "do not run",
            "don't run",
            "dont run",
            "do not execute",
            "don't execute",
            "dont execute",
            "do not use tools",
            "don't use tools",
            "dont use tools",
            "without using tools",
            "without running",
            "no tool use",
            "no tools",
            "no shell",
            "no terminal",
            "do not modify",
            "don't modify",
            "dont modify",
            "do not edit",
            "don't edit",
            "dont edit",
            "do not make changes",
            "don't make changes",
            "dont make changes"
        ]
        if hardStops.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let explanationOnlyPhrases = [
            "just tell me how",
            "only tell me how",
            "tell me how to",
            "explain how to",
            "walk me through",
            "give me instructions",
            "give me a plan",
            "make a plan"
        ]
        return explanationOnlyPhrases.contains { lowercased.contains($0) } &&
            (lowercased.contains("repo") ||
                lowercased.contains("code") ||
                lowercased.contains("test") ||
                lowercased.contains("xcode") ||
                lowercased.contains("terminal") ||
                lowercased.contains("shell"))
    }
}
