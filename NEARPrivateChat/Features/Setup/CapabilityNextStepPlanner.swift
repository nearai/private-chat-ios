import Foundation

enum CapabilityRouteBlock: String, Codable, Equatable, Sendable {
    case nearCloudKeyRequired
    case hostedIronclawEndpointRequired
    case councilNeedsModels
}

enum CapabilityNextStepKind: String, Codable, Equatable, Sendable {
    case openSecurity
    case openCloud
    case openAgent
    case useAutoCouncil
    case rerunSetup
}

enum AccountSettingsDeepLink: String, Codable, Equatable, Hashable, Sendable {
    case nearCloudKeys
    case ironclawAgent

    init?(capabilityNextStepKind: CapabilityNextStepKind) {
        switch capabilityNextStepKind {
        case .openCloud:
            self = .nearCloudKeys
        case .openAgent:
            self = .ironclawAgent
        case .openSecurity, .useAutoCouncil, .rerunSetup:
            return nil
        }
    }
}

struct CapabilityNextStep: Codable, Equatable, Sendable {
    let title: String
    let detail: String
    let actionTitle: String
    let kind: CapabilityNextStepKind
}

enum CapabilityNextStepPlanner {
    static func recommend(
        routeBlock: CapabilityRouteBlock?,
        setupPlan: AppSetupPlan,
        currentRoute: ChatRouteKind,
        hasFreshPrivateProof: Bool,
        hostedIronclawAvailable: Bool,
        autoCouncilReady: Bool
    ) -> CapabilityNextStep? {
        switch routeBlock {
        case .nearCloudKeyRequired:
            return CapabilityNextStep(
                title: "Connect NEAR AI Cloud",
                detail: "This route is blocked until NEAR AI Cloud is connected. Private chat still works right now.",
                actionTitle: "Connect Cloud",
                kind: .openCloud
            )
        case .hostedIronclawEndpointRequired:
            return CapabilityNextStep(
                title: "Connect Hosted IronClaw",
                detail: "Phone-safe Agent skills are ready. Hosted IronClaw routes need a Hosted IronClaw URL.",
                actionTitle: "Connect Agent",
                kind: .openAgent
            )
        case .councilNeedsModels:
            if autoCouncilReady {
                return CapabilityNextStep(
                    title: "Restore the Council lineup",
                    detail: "Recommended Council rebuilds a working lineup so you can compare models without rebuilding it by hand.",
                    actionTitle: "Use recommended Council",
                    kind: .useAutoCouncil
                )
            }
        case nil:
            break
        }

        if setupPlan.agentEnabled && !currentRoute.isIronclawRoute && !hostedIronclawAvailable {
            return CapabilityNextStep(
                title: "Finish Agent setup",
                detail: "Your defaults expect Agent work. Connect Hosted IronClaw when you need repo, shell, or approval-gated tasks.",
                actionTitle: "Connect Agent",
                kind: .openAgent
            )
        }

        if setupPlan.councilEnabled && autoCouncilReady {
            return CapabilityNextStep(
                title: "Try recommended Council",
                detail: "Your defaults favor multi-model comparison. Start with the ready lineup and customize later if needed.",
                actionTitle: "Use recommended Council",
                kind: .useAutoCouncil
            )
        }

        if currentRoute == .nearPrivate && !hasFreshPrivateProof {
            return CapabilityNextStep(
                title: "Check private proof",
                detail: "Private chat is ready now. Fetch or refresh proof when you need signed route evidence for the current model.",
                actionTitle: "Open Proof report",
                kind: .openSecurity
            )
        }

        return CapabilityNextStep(
            title: "Adjust your defaults",
            detail: "Rerun setup if you want to change the app's first-run route, context, or capability defaults.",
            actionTitle: "Rerun Setup",
            kind: .rerunSetup
        )
    }
}
