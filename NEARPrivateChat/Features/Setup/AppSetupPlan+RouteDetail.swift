import Foundation

struct AppSetupRouteDetailContent: Codable, Hashable {
    let title: String
    let summary: String
    let symbolName: String
}

extension AppSetupPlan {
    var routeDetailContent: AppSetupRouteDetailContent? {
        let labels = expectedRouteModelIDs.map(Self.setupRouteModelLabel)

        switch modelRoute {
        case .privateModel:
            guard let label = labels.first else { return nil }
            return AppSetupRouteDetailContent(
                title: "NEAR Private route",
                summary: "\(label) · attested when proof is fresh.",
                symbolName: "lock.shield"
            )
        case .council:
            guard !labels.isEmpty else { return nil }
            return AppSetupRouteDetailContent(
                title: labels.count > 2 ? "Council lineup (\(labels.count))" : "Council lineup",
                summary: "\(labels.joined(separator: " + ")) · proof depends on the selected models.",
                symbolName: "square.grid.2x2"
            )
        case .ironclaw:
            let usesHosted = expectedRouteModelIDs.contains(ModelOption.ironclawModelID)
            let label = labels.first ?? (usesHosted ? "Hosted IronClaw" : "IronClaw Mobile")
            return AppSetupRouteDetailContent(
                title: "IronClaw route",
                summary: usesHosted
                    ? "\(label) · sends work outside this phone."
                    : "\(label) · Phone Agent route, outside NEAR Private proof.",
                symbolName: "terminal"
            )
        }
    }

    private static func setupRouteModelLabel(_ modelID: String) -> String {
        switch modelID {
        case ModelOption.ironclawModelID:
            return "Hosted IronClaw"
        case ModelOption.ironclawMobileModelID:
            return "IronClaw Mobile"
        default:
            return ModelOption.humanize(modelID: modelID)
        }
    }

    func firstRunCapabilityRecommendation(readiness: AppSetupReadinessSnapshot) -> CapabilityNextStep? {
        if councilEnabled, modelRoute != .council {
            guard readiness.modelCatalogLoaded, !readiness.nearCloudKeyConfigured else { return nil }
            return CapabilityNextStep(
                title: "Unlock a fuller council",
                detail: "This quick start opens private chat first because fewer than two council models are ready. Connect NEAR AI Cloud to add more models for research comparison.",
                actionTitle: "Connect Cloud",
                kind: .openCloud
            )
        }

        guard agentEnabled else { return nil }

        if !readiness.ironclawMobileAvailable, readiness.hostedIronclawAvailable {
            return CapabilityNextStep(
                title: "Hosted agent is available",
                detail: "This quick start opens private chat first because IronClaw Mobile is unavailable. Open Hosted IronClaw for repo, shell, or approval-gated work.",
                actionTitle: "Open Agent",
                kind: .openAgent
            )
        }

        guard modelRoute != .ironclaw else { return nil }

        return CapabilityNextStep(
            title: "Finish Agent setup",
            detail: "This quick start opens private chat first. Connect Hosted IronClaw to use repo, shell, or approval-gated Agent work.",
            actionTitle: "Connect Agent",
            kind: .openAgent
        )
    }
}
