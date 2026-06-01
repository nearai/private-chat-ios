import Foundation

struct ModelCatalogStore {
    let models: [ModelOption]
    let nearCloudModels: [ModelOption]
    let allowedModelIDs: Set<String>?
    let preferredModelIDs: [String]
    let nearCloudPreferredModelIDs: [String]

    var externalModels: [ModelOption] {
        [Self.ironclawMobileModel(), Self.ironclawModel()] + cloudRouteModels
    }

    var agentModels: [ModelOption] {
        [Self.ironclawMobileModel(), Self.ironclawModel()]
    }

    var cloudRouteModels: [ModelOption] {
        Self.uniqueModels(nearCloudModels + Self.fallbackNearCloudModels())
            .filter { !$0.isUtilityModel }
    }

    var cloudModels: [ModelOption] {
        rankedModels(from: cloudRouteModels)
    }

    var chatModels: [ModelOption] {
        let privateModels = models.isEmpty ? Self.fallbackPrivateModels() : models
        return (privateModels + externalModels).filter { model in
            !model.isUtilityModel && isAllowedByCurrentPlan(model)
        }
    }

    var pickerModels: [ModelOption] {
        chatModels.filter { !$0.isDeprecatedPickerModel }
    }

    func pinnedPickerModels(from pinnedModelIDs: [String]) -> [ModelOption] {
        let available = pickerModels
        return pinnedModelIDs.compactMap { id in
            available.first { $0.id == id }
        }
    }

    func rankedModels(from source: [ModelOption]) -> [ModelOption] {
        source.sorted { lhs, rhs in
            let lhsRank = modelRank(lhs)
            let rhsRank = modelRank(rhs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func isAllowedByCurrentPlan(_ model: ModelOption) -> Bool {
        if model.isExternalModel {
            return true
        }
        guard let allowedModelIDs else {
            return true
        }
        return allowedModelIDs.contains(model.id.lowercased())
    }

    private func modelRank(_ model: ModelOption) -> Int {
        let comparableIDs = Self.uniqueStrings([model.id, model.nearCloudUnderlyingModelID].compactMap { $0 })
        if model.isNearCloudModel,
           let cloudIndex = nearCloudPreferredModelIDs.firstIndex(where: { preferredID in
               comparableIDs.contains { $0.localizedCaseInsensitiveCompare(preferredID) == .orderedSame }
           }) {
            return cloudIndex
        }
        if let preferredIndex = preferredModelIDs.firstIndex(where: { preferredID in
            comparableIDs.contains { $0.localizedCaseInsensitiveCompare(preferredID) == .orderedSame }
        }) {
            return preferredIndex
        }
        if model.isEliteModel {
            return 100
        }
        if model.isRecommendedReasoningModel && !model.isLowerPriorityModel {
            return 200
        }
        if model.isPrivateVerifiableChatModel {
            return 300
        }
        if model.isLowerPriorityModel {
            return 1_000
        }
        return model.isAnthropicModel ? 450 : 500
    }

    static func ironclawMobileModel() -> ModelOption {
        ModelOption(
            modelID: ModelOption.ironclawMobileModelID,
            publicModel: true,
            metadata: ModelOption.Metadata(
                verifiable: false,
                contextLength: nil,
                modelDisplayName: "IronClaw Mobile",
                modelDescription: "Runs an iOS-safe IronClaw runtime with NEAR Private inference, web search, attachments, projects, and optional Hosted IronClaw handoff for git/code/shell tasks.",
                modelIcon: nil,
                aliases: ["IronClaw", "mobile runtime", "agent", "iOS", "workstation", "git", "code"]
            )
        )
    }

    static func ironclawModel() -> ModelOption {
        ModelOption(
            modelID: ModelOption.ironclawModelID,
            publicModel: true,
            metadata: ModelOption.Metadata(
                verifiable: false,
                contextLength: nil,
                modelDisplayName: "Hosted IronClaw",
                modelDescription: "Connect Hosted IronClaw for git, code, shell, research, and software tasks.",
                modelIcon: nil,
                aliases: ["IronClaw", "Hosted IronClaw", "agent", "hosted endpoint", "workstation", "git", "code", "shell"]
            )
        )
    }

    static func fallbackNearCloudModels() -> [ModelOption] {
        []
    }

    static func fallbackPrivateModels() -> [ModelOption] {
        [
            ModelOption(
                modelID: ModelOption.nearPrivateDefaultModelID,
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: nil,
                    modelDisplayName: "NEAR Private model",
                    modelDescription: "Default private route with proof support.",
                    modelIcon: nil,
                    aliases: ["NEAR Private", "verified", "private"]
                )
            )
        ]
    }

    static func nearCloudRouteModels(from cloudModels: [ModelOption]) -> [ModelOption] {
        var seen = Set<String>()
        return cloudModels.compactMap { model in
            let cloudID = model.nearCloudUnderlyingModelID ?? model.id
            let normalizedID = cloudID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedID.isEmpty, seen.insert(normalizedID.lowercased()).inserted else {
                return nil
            }
            let aliases = uniqueStrings(["NEAR AI Cloud", "privacy proxy", "external model", normalizedID, model.displayName] + (model.metadata?.aliases ?? []))
            let description = model.metadata?.modelDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
            let routeDescription = description?.isEmpty == false
                ? "\(description!) Routes through NEAR AI Cloud with privacy proxy forwarding."
                : "Routes \(model.displayName) through NEAR AI Cloud with privacy proxy forwarding."
            return ModelOption(
                modelID: nearCloudRouteModelID(for: normalizedID),
                publicModel: model.publicModel,
                metadata: ModelOption.Metadata(
                    verifiable: false,
                    contextLength: model.metadata?.contextLength,
                    modelDisplayName: model.displayName,
                    modelDescription: routeDescription,
                    modelIcon: model.metadata?.modelIcon,
                    aliases: aliases
                )
            )
        }
    }

    static func uniqueModels(_ models: [ModelOption]) -> [ModelOption] {
        var seen = Set<String>()
        var output: [ModelOption] = []
        for model in models {
            let key = (model.nearCloudUnderlyingModelID ?? model.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else {
                continue
            }
            output.append(model)
        }
        return output
    }

    static func model(_ model: ModelOption, matchesCandidateID candidateID: String) -> Bool {
        let candidate = candidateID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return false }
        let comparableIDs = uniqueStrings([model.id, model.nearCloudUnderlyingModelID].compactMap { $0 })
        return comparableIDs.contains { $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame }
    }

    private static func nearCloudFallbackModel(
        cloudModelID: String,
        displayName: String,
        description: String
    ) -> ModelOption {
        ModelOption(
            modelID: nearCloudRouteModelID(for: cloudModelID),
            publicModel: true,
            metadata: ModelOption.Metadata(
                verifiable: false,
                contextLength: nil,
                modelDisplayName: displayName,
                modelDescription: description,
                modelIcon: nil,
                aliases: ["NEAR AI Cloud", cloudModelID, displayName, "privacy proxy", "external model"]
            )
        )
    }

    private static func nearCloudRouteModelID(for cloudModelID: String) -> String {
        let normalized = cloudModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return ModelOption.nearCloudModelID(for: normalized)
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
