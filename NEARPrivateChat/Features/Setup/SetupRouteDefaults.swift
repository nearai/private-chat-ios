import Foundation

enum AppSetupModelRoute: String, Codable, Hashable {
    case privateModel
    case council
    case ironclaw

    var title: String {
        switch self {
        case .privateModel: "Private model"
        case .council: "LLM Council"
        case .ironclaw: "Agent"
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

struct SetupRouteDefaults: Codable, Hashable {
    var privateModelID: String?
    var councilModelIDs: [String]
    var ironclawMobileModelID: String?

    static let empty = SetupRouteDefaults(
        privateModelID: nil,
        councilModelIDs: [],
        ironclawMobileModelID: nil
    )

    var isEmpty: Bool {
        normalized == .empty
    }

    var normalized: SetupRouteDefaults {
        SetupRouteDefaults(
            privateModelID: Self.normalizedID(privateModelID),
            councilModelIDs: Self.normalizedIDs(councilModelIDs),
            ironclawMobileModelID: Self.normalizedID(ironclawMobileModelID)
        )
    }

    func preferredIronclawModelID(readiness: AppSetupReadinessSnapshot) -> String? {
        if readiness.ironclawMobileAvailable {
            return normalized.ironclawMobileModelID ?? ModelOption.ironclawMobileModelID
        }
        if readiness.hostedIronclawAvailable {
            return ModelOption.ironclawModelID
        }
        return nil
    }

    private static func normalizedID(_ id: String?) -> String? {
        guard let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for modelID in ids {
            guard let trimmed = normalizedID(modelID),
                  seen.insert(trimmed.lowercased()).inserted else {
                continue
            }
            normalized.append(trimmed)
        }
        return normalized
    }
}
