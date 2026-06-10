import Foundation

struct AskOrchestratorDecision: Equatable, Sendable {
    enum Tool: String, Equatable, Hashable, Sendable {
        case web
        case projectFiles
        case promptFiles
        case council
        case agent
    }

    enum FailurePlan: Equatable, Sendable {
        case none
        case requestCloudKey
        case requestHostedAgent
        case requestCouncilModels
        case confirmUnverifiedRoute
    }

    var route: ChatRouteKind
    var tools: Set<Tool>
    var proofState: ProofState
    var failurePlan: FailurePlan
    var shouldOfferAgent: Bool
    var shouldOfferCouncil: Bool
}

struct AskOrchestrator: Sendable {
    struct Input: Equatable, Sendable {
        var prompt: String
        var selectedRoute: ChatRouteKind
        var hasProjectContext: Bool
        var hasPromptAttachments: Bool
        var nearCloudKeyConfigured: Bool
        var hostedAgentAvailable: Bool
        var councilAvailable: Bool
        var councilActive: Bool
    }

    static func decide(_ input: Input) -> AskOrchestratorDecision {
        let normalized = input.prompt.lowercased()
        var tools = Set<AskOrchestratorDecision.Tool>()
        let route = input.selectedRoute
        var failurePlan: AskOrchestratorDecision.FailurePlan = .none
        var shouldOfferAgent = false
        var shouldOfferCouncil = false

        let needsFiles = input.hasPromptAttachments || input.hasProjectContext || containsAny(
            normalized,
            [
                "this file", "these files", "my file", "my doc", "my document", "attached",
                "attachment", "pdf", "csv", "project file", "source file"
            ]
        )
        // Recency-year cues are derived from the calendar, not hardcoded, so the
        // "this looks time-sensitive" heuristic doesn't go stale each new year.
        let currentYear = Calendar.current.component(.year, from: Date())
        let recencyYears = [currentYear, currentYear + 1].map(String.init)
        let needsWeb = containsAny(
            normalized,
            ["latest", "today", "news", "current", "price", "as of", "web", "search", "cite"] + recencyYears
        )
        let taskShaped = containsAny(
            normalized,
            ["agent mission", "run as agent", "implement", "fix", "patch", "run tests", "open a pr", "create a pr", "deploy", "clone", "repo", "git"]
        )
        let decisionShaped = containsAny(
            normalized,
            ["should i", "which is better", "compare", "tradeoff", "pros and cons", "decide", "recommend"]
        )

        if needsFiles {
            tools.insert(input.hasPromptAttachments ? .promptFiles : .projectFiles)
        }
        if needsWeb {
            tools.insert(.web)
        }

        if taskShaped {
            shouldOfferAgent = true
            if route == .ironclawHosted, input.hostedAgentAvailable {
                tools.insert(.agent)
            } else if route == .ironclawHosted {
                failurePlan = .requestHostedAgent
            }
        }

        if decisionShaped {
            shouldOfferCouncil = true
            if input.councilActive {
                if input.councilAvailable {
                    tools.insert(.council)
                } else {
                    failurePlan = .requestCouncilModels
                }
            }
        }

        if route == .nearCloud {
            if !input.nearCloudKeyConfigured {
                failurePlan = .requestCloudKey
            }
        }

        let proofState: ProofState
        switch route {
        case .nearPrivate:
            proofState = .private_
        case .nearCloud:
            proofState = input.nearCloudKeyConfigured ? .proxied : .unverified
        case .ironclawMobile, .ironclawHosted:
            proofState = .unverified
        }

        return AskOrchestratorDecision(
            route: route,
            tools: tools,
            proofState: proofState,
            failurePlan: failurePlan,
            shouldOfferAgent: shouldOfferAgent,
            shouldOfferCouncil: shouldOfferCouncil
        )
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
