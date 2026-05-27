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
                modelDescription: "Runs an iOS-safe IronClaw runtime with NEAR Private inference, web search, attachments, projects, and automatic hosted workstation handoff for git/code/shell tasks.",
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
                modelDescription: "Connect a hosted IronClaw HTTPS workstation for git, code, shell, research, and software tasks.",
                modelIcon: nil,
                aliases: ["IronClaw", "Hosted IronClaw", "agent", "hosted endpoint", "workstation", "git", "code", "shell"]
            )
        )
    }

    static func fallbackNearCloudModels() -> [ModelOption] {
        [
            nearCloudFallbackModel(
                cloudModelID: "anthropic/claude-opus-4-7",
                displayName: "Claude Opus 4.7",
                description: "Runs Claude Opus 4.7 through NEAR Cloud with privacy proxy routing."
            ),
            nearCloudFallbackModel(
                cloudModelID: "openai/gpt-5.5",
                displayName: "GPT-5.5",
                description: "Runs GPT-5.5 through NEAR Cloud with privacy proxy routing."
            ),
            nearCloudFallbackModel(
                cloudModelID: "qwen/qwen3.7-max",
                displayName: "Qwen3.7 Max",
                description: "Runs Qwen3.7 Max through NEAR Cloud with privacy proxy routing."
            ),
            nearCloudFallbackModel(
                cloudModelID: "moonshotai/kimi-k2.6",
                displayName: "Kimi K2.6",
                description: "Runs Kimi K2.6 through NEAR Cloud with privacy proxy routing."
            ),
            nearCloudFallbackModel(
                cloudModelID: "google/gemini-3.5-flash",
                displayName: "Gemini 3.5 Flash",
                description: "Runs Gemini 3.5 Flash through NEAR Cloud with privacy proxy routing."
            ),
            nearCloudFallbackModel(
                cloudModelID: "openai/gpt-oss-120b",
                displayName: "GPT OSS 120B",
                description: "Runs GPT OSS 120B through NEAR Cloud with privacy proxy routing."
            )
        ]
    }

    static func fallbackPrivateModels() -> [ModelOption] {
        [
            ModelOption(
                modelID: "zai-org/GLM-5.1-FP8",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: nil,
                    modelDisplayName: "GLM 5.1",
                    modelDescription: "Default NEAR Private route with verification support.",
                    modelIcon: nil,
                    aliases: ["GLM", "GLM 5.1", "NEAR Private", "verified", "private"]
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
            let aliases = uniqueStrings(["NEAR Cloud", "privacy proxy", "unverified", normalizedID, model.displayName] + (model.metadata?.aliases ?? []))
            let description = model.metadata?.modelDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
            let routeDescription = description?.isEmpty == false
                ? "\(description!) Runs through NEAR Cloud with privacy proxy routing."
                : "Runs \(model.displayName) through NEAR Cloud with privacy proxy routing."
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
                aliases: ["NEAR Cloud", cloudModelID, displayName, "privacy proxy", "unverified"]
            )
        )
    }

    private static func nearCloudRouteModelID(for cloudModelID: String) -> String {
        let normalized = cloudModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.localizedCaseInsensitiveCompare("qwen/qwen3.7-max") == .orderedSame {
            return ModelOption.nearCloudQwenMaxModelID
        }
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
