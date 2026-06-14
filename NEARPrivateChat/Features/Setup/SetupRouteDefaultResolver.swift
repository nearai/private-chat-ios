import Foundation

enum SetupRouteDefaultResolver {
    static func currentDefaults(
        selectedModelID: String,
        isCouncilModeEnabled: Bool,
        councilModelIDs: [String],
        agentModelIDs: Set<String>,
        preferredAvailableModelID: String?,
        defaultModelID: String,
        maxCouncilModels: Int
    ) -> SetupRouteDefaults {
        SetupRouteDefaults(
            privateModelID: usablePrivateModelID(selectedModelID) ?? preferredAvailableModelID ?? defaultModelID,
            councilModelIDs: councilRouteModelIDs(councilModelIDs, maxCouncilModels: maxCouncilModels),
            ironclawMobileModelID: agentModelIDs.contains(ModelOption.ironclawMobileModelID)
                ? ModelOption.ironclawMobileModelID
                : nil
        ).normalized
    }

    static func resolvedDefaults(
        stored: SetupRouteDefaults,
        fallback: SetupRouteDefaults,
        preferredAvailableModelID: String?,
        agentModelIDs: Set<String>,
        defaultModelID: String,
        maxCouncilModels: Int
    ) -> SetupRouteDefaults {
        let stored = stored.normalized
        let fallback = fallback.normalized
        let privateModelID = usablePrivateModelID(stored.privateModelID) ??
            usablePrivateModelID(fallback.privateModelID) ??
            preferredAvailableModelID ??
            defaultModelID
        let councilSource = stored.councilModelIDs.isEmpty ? fallback.councilModelIDs : stored.councilModelIDs
        let ironclawMobileModelID =
            stored.ironclawMobileModelID == ModelOption.ironclawMobileModelID &&
            agentModelIDs.contains(ModelOption.ironclawMobileModelID)
            ? ModelOption.ironclawMobileModelID
            : fallback.ironclawMobileModelID

        return SetupRouteDefaults(
            privateModelID: privateModelID,
            councilModelIDs: councilRouteModelIDs(councilSource, maxCouncilModels: maxCouncilModels),
            ironclawMobileModelID: ironclawMobileModelID
        ).normalized
    }

    static func usablePrivateModelID(_ modelID: String?) -> String? {
        guard let trimmed = modelID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              RoutePlanner.routeKind(forModelID: trimmed) == .nearPrivate else {
            return nil
        }
        return trimmed
    }

    static func councilRouteModelIDs(_ ids: [String], maxCouncilModels: Int) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for modelID in ids {
            let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty,
                  RoutePlanner.routeKind(forModelID: trimmed) != .ironclawHosted,
                  RoutePlanner.routeKind(forModelID: trimmed) != .ironclawMobile,
                  seen.insert(key).inserted else {
                continue
            }
            normalized.append(trimmed)
            if normalized.count == maxCouncilModels {
                break
            }
        }
        return normalized
    }
}
