import Foundation

extension ModelCatalogStore {
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
                    modelDisplayName: "GLM 5.1",
                    modelDescription: "Default NEAR Private route with proof support.",
                    modelIcon: nil,
                    aliases: ["NEAR Private", "verified", "private", "GLM"]
                )
            ),
            ModelOption(
                modelID: "deepseek-ai/DeepSeek-V4-Flash",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: 1_048_576,
                    modelDisplayName: "DeepSeek V4 Flash",
                    modelDescription: "NEAR Private DeepSeek V4 Flash route with proof support.",
                    modelIcon: nil,
                    aliases: ["DeepSeek", "private", "reasoning", "fast", "TDX"]
                )
            ),
            ModelOption(
                modelID: "Qwen/Qwen3.5-122B-A10B",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: nil,
                    modelDisplayName: "Qwen3.5 122B A10B",
                    modelDescription: "NEAR Private open-weight reasoning route with proof support.",
                    modelIcon: nil,
                    aliases: ["Qwen", "private", "open-weight", "reasoning"]
                )
            ),
            ModelOption(
                modelID: "Qwen/Qwen3.6-35B-A3B-FP8",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: nil,
                    modelDisplayName: "Qwen 3.6 35B A3B FP8",
                    modelDescription: "NEAR Private open-weight fast reasoning route with proof support.",
                    modelIcon: nil,
                    aliases: ["Qwen", "private", "open-weight", "fast"]
                )
            ),
            ModelOption(
                modelID: "Qwen/Qwen3.6-27B-FP8",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: 262_144,
                    modelDisplayName: "Qwen 3.6 27B FP8",
                    modelDescription: "NEAR Private dense reasoning route with proof support.",
                    modelIcon: nil,
                    aliases: ["Qwen", "private", "open-weight", "reasoning"]
                )
            ),
            ModelOption(
                modelID: "Qwen/Qwen3-30B-A3B-Instruct-2507",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: 262_144,
                    modelDisplayName: "Qwen3 30B A3B Instruct 2507",
                    modelDescription: "NEAR Private instruction route with proof support.",
                    modelIcon: nil,
                    aliases: ["Qwen", "private", "open-weight", "instruct"]
                )
            ),
            ModelOption(
                modelID: "Qwen/Qwen3-VL-30B-A3B-Instruct",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: true,
                    contextLength: 256_000,
                    modelDisplayName: "Qwen3-VL-30B-A3B-Instruct",
                    modelDescription: "NEAR Private vision-language route with proof support.",
                    modelIcon: nil,
                    aliases: ["Qwen", "private", "open-weight", "vision"]
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
        let comparableIDs = uniqueStrings(
            [model.id, model.nearCloudUnderlyingModelID].compactMap { $0 } +
                canonicalModelAliases(for: model.id)
        )
        return comparableIDs.contains { $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame }
    }

    static func canonicalModelID(for modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedModelID(trimmed) == normalizedModelID(Self.defaultModelID) {
            return Self.defaultModelID
        }
        if canonicalModelAliases(for: Self.defaultModelID).contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return Self.defaultModelID
        }
        return trimmed
    }

    static func modelIDsEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return false
        }
        return Self.model(ModelOption(modelID: lhs, publicModel: true, metadata: nil), matchesCandidateID: rhs) ||
            Self.model(ModelOption(modelID: rhs, publicModel: true, metadata: nil), matchesCandidateID: lhs) ||
            Self.normalizedModelID(lhs) == Self.normalizedModelID(rhs)
    }

    static func canonicalModelAliases(for modelID: String) -> [String] {
        if modelID.localizedCaseInsensitiveCompare(ModelOption.nearPrivateDefaultModelID) == .orderedSame ||
            modelID.localizedCaseInsensitiveCompare("zai-org/GLM-latest") == .orderedSame {
            return ["zai-org/GLM-latest"]
        }
        return []
    }

    static func nearCloudRouteModelID(for cloudModelID: String) -> String {
        let normalized = cloudModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return ModelOption.nearCloudModelID(for: normalized)
    }

    static func uniqueStrings(_ values: [String]) -> [String] {
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
