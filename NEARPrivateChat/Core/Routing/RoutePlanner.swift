import Foundation

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
        if modelID == ModelOption.nearCloudQwenMaxModelID || modelID.hasPrefix(ModelOption.nearCloudModelPrefix) {
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
                message: "Choose at least two usable Council models, or switch to a single private model. Your draft and attachments were kept.",
                recoveryAction: .editCouncilLineup,
                recoveryTitle: "Edit Council"
            )
        }

        let modelIDs = isCouncilRequested ? councilModelIDs : [selectedModelID]
        if modelIDs.contains(where: { routeKind(forModelID: $0) == .nearCloud }), !nearCloudKeyConfigured {
            return ChatRouteReadinessIssue(
                route: .nearCloud,
                title: "Connect NEAR Cloud",
                message: "Connect NEAR Cloud in Account before sending with this route. Your draft and attachments were kept.",
                recoveryAction: .addNearCloudKey,
                recoveryTitle: "Add Key"
            )
        }

        if modelIDs.contains(where: { routeKind(forModelID: $0) == .ironclawHosted }), !hostedIronclawEndpointUsable {
            let endpointMessage = hostedIronclawEndpointMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = endpointMessage?.isEmpty == false ? endpointMessage! : "Add a hosted HTTPS IronClaw endpoint in Account before sending."
            return ChatRouteReadinessIssue(
                route: .hostedIronclaw,
                title: "Hosted IronClaw endpoint required",
                message: "\(detail) Your draft and attachments were kept.",
                recoveryAction: .configureIronClawEndpoint,
                recoveryTitle: "Configure Endpoint"
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
}
