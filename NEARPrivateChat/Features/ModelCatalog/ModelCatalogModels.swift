import Foundation
import SwiftUI

enum ModelReasoningEffort: String, CaseIterable, Codable, Identifiable, Hashable {
    case automatic
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Auto"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Let the provider choose the reasoning budget."
        case .low:
            return "Favor speed and lower token spend."
        case .medium:
            return "Balance quality, latency, and token spend."
        case .high:
            return "Spend more reasoning for harder prompts."
        }
    }

    var apiValue: String? {
        switch self {
        case .automatic: nil
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        }
    }
}

struct AdvancedModelParams: Codable, Hashable {
    var temperature: Double?
    var topP: Double?
    var maxTokens: Int?
    var reasoningEffort: ModelReasoningEffort

    static let defaults = AdvancedModelParams()

    init(
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        reasoningEffort: ModelReasoningEffort = .automatic
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.reasoningEffort = reasoningEffort
    }

    enum CodingKeys: String, CodingKey {
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case reasoningEffort = "reasoning_effort"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        topP = try container.decodeIfPresent(Double.self, forKey: .topP)
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
        reasoningEffort = try container.decodeIfPresent(ModelReasoningEffort.self, forKey: .reasoningEffort) ?? .automatic
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        if reasoningEffort != .automatic {
            try container.encode(reasoningEffort, forKey: .reasoningEffort)
        }
    }

    var isDefault: Bool {
        temperature == nil && topP == nil && maxTokens == nil && reasoningEffort == .automatic
    }

    var sanitized: AdvancedModelParams {
        AdvancedModelParams(
            temperature: temperature.map { min(max($0, 0), 2) },
            topP: topP.map { min(max($0, 0), 1) },
            maxTokens: maxTokens.map { min(max($0, 1), 200_000) },
            reasoningEffort: reasoningEffort
        )
    }

    var summary: String {
        var parts: [String] = []
        if let temperature {
            parts.append("temp \(Self.format(temperature))")
        }
        if let topP {
            parts.append("top-p \(Self.format(topP))")
        }
        if let maxTokens {
            parts.append("\(maxTokens) max")
        }
        if reasoningEffort != .automatic {
            parts.append("reasoning \(reasoningEffort.title.lowercased())")
        }
        return parts.isEmpty ? "Defaults" : parts.joined(separator: " · ")
    }

    private static func format(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        return formatted
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

struct ModelListResponse: Decodable {
    let models: [ModelOption]
}

struct ModelOption: Decodable, Identifiable, Hashable {
    struct Metadata: Decodable, Hashable {
        let verifiable: Bool?
        let contextLength: Int?
        let modelDisplayName: String?
        let modelDescription: String?
        let modelIcon: String?
        let aliases: [String]?

        enum CodingKeys: String, CodingKey {
            case verifiable
            case contextLength
            case modelDisplayName
            case modelDescription
            case modelIcon
            case aliases
        }
    }

    let modelID: String
    let publicModel: Bool?
    let metadata: Metadata?
    static let nearPrivateDefaultModelID = "zai-org/GLM-5.1-FP8"
    static let ironclawModelID = "ironclaw/agent"
    static let ironclawMobileModelID = "ironclaw/mobile-runtime"
    static let nearCloudModelPrefix = "near-cloud/"
    static let llmCouncilSynthesisModelID = "llm-council/synthesis"

    var id: String { modelID }

    var displayName: String {
        if isIronclawMobileRuntime {
            return "IronClaw Mobile"
        }
        if isIronclawHostedModel {
            return "Hosted IronClaw"
        }
        if isNearCloudModel {
            if let modelDisplayName = sanitizedModelDisplayName {
                return modelDisplayName
            }
            if let underlyingModelID = nearCloudUnderlyingModelID {
                return Self.humanize(modelID: underlyingModelID)
            }
            return "NEAR AI Cloud model"
        }
        if modelID == Self.llmCouncilSynthesisModelID {
            return "Council Synthesis"
        }
        if let metadataName = sanitizedModelDisplayName {
            return metadataName
        }
        return Self.humanize(modelID: modelID)
    }

    private var sanitizedModelDisplayName: String? {
        guard let value = metadata?.modelDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Turn a fully-qualified model id into a readable label by dropping the
    /// provider prefix and numeric-precision suffix. Falls back to the raw
    /// trailing segment if no recognisable pattern is present.
    static func humanize(modelID: String) -> String {
        let trailing = modelID.split(separator: "/").last.map(String.init) ?? modelID
        let precisionSuffixes = ["-FP8", "-FP16", "-INT8", "-INT4", "-BF16", "-Q4", "-Q8", "-Q4_K_M", "-Q5_K_M"]
        var trimmed = trailing
        for suffix in precisionSuffixes where trimmed.uppercased().hasSuffix(suffix) {
            trimmed = String(trimmed.dropLast(suffix.count))
            break
        }
        // Family-version split keeps compact model labels readable without
        // exposing provider paths.
        let parts = trimmed.split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return trailing }
        let humanized = parts.enumerated().map { index, part -> String in
            let lowercasedPart = part.lowercased()
            let knownAcronyms: Set<String> = ["ai", "api", "glm", "gpt", "llm", "oss", "vl"]
            if knownAcronyms.contains(lowercasedPart) {
                return lowercasedPart.uppercased()
            }
            // Preserve all-caps family acronyms (GLM, GPT, LLM, etc.) and
            // version segments that mix digits + dots (5.1, 4.7, k2).
            if index == 0, part.uppercased() == part, part.count <= 4 {
                return part
            }
            if part.first?.isLetter == false {
                return part
            }
            if part.contains("."),
               let firstLetter = part.firstIndex(where: { $0.isLetter }),
               let firstDigit = part.firstIndex(where: { $0.isNumber }),
               firstLetter < firstDigit {
                let family = String(part[..<firstDigit])
                let version = String(part[firstDigit...])
                let familyLabel = family.prefix(1).uppercased() + family.dropFirst()
                if family.count == 1 {
                    return familyLabel.uppercased() + version.uppercased()
                }
                return "\(familyLabel) \(version.uppercased())"
            }
            if part.contains(".") {
                return part
            }
            // Title-case otherwise.
            return part.prefix(1).uppercased() + part.dropFirst()
        }
        return humanized.joined(separator: " ")
    }

    static func providerFamilyName(for modelID: String) -> String? {
        let lowercased = modelID.lowercased()
        if lowercased.contains("anthropic") || lowercased.contains("claude") {
            return "Anthropic"
        }
        if lowercased.contains("openai") || lowercased.contains("gpt") || lowercased.contains("o3") || lowercased.contains("o4") {
            return "OpenAI"
        }
        if lowercased.contains("qwen") {
            return "Qwen"
        }
        if lowercased.contains("moonshot") || lowercased.contains("kimi") {
            return "Moonshot"
        }
        if lowercased.contains("google") || lowercased.contains("gemini") {
            return "Google"
        }
        return nil
    }

    var isVerifiable: Bool {
        guard !isExternalModel else { return false }
        return metadata?.verifiable ?? true
    }

    var isIronclawHostedModel: Bool {
        modelID == Self.ironclawModelID
    }

    var isIronclawMobileRuntime: Bool {
        modelID == Self.ironclawMobileModelID
    }

    var isIronclawModel: Bool {
        isIronclawHostedModel || isIronclawMobileRuntime
    }

    var isNearCloudModel: Bool {
        modelID.hasPrefix(Self.nearCloudModelPrefix)
    }

    var isExternalModel: Bool {
        isIronclawModel || isNearCloudModel
    }

    var nearCloudUnderlyingModelID: String? {
        guard modelID.hasPrefix(Self.nearCloudModelPrefix) else { return nil }
        let underlying = String(modelID.dropFirst(Self.nearCloudModelPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return underlying.isEmpty ? nil : underlying
    }

    static func nearCloudModelID(for cloudModelID: String) -> String {
        "\(nearCloudModelPrefix)\(cloudModelID.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    var isUtilityModel: Bool {
        if isExternalModel { return false }
        let lowercased = searchText.lowercased()
        return lowercased.contains("embedding") ||
            lowercased.contains("reranker") ||
            lowercased.contains("whisper") ||
            lowercased.contains("flux")
    }

    var isAnthropicModel: Bool {
        modelID.hasPrefix("anthropic/")
    }

    var isClosedProviderModel: Bool {
        let lowercased = modelID.lowercased()
        if lowercased.hasPrefix("openai/gpt-oss") {
            return false
        }
        return lowercased.hasPrefix("openai/") ||
            lowercased.hasPrefix("anthropic/") ||
            lowercased.hasPrefix("google/") ||
            lowercased.hasPrefix("x-ai/") ||
            lowercased.hasPrefix("mistral/")
    }

    var isOpenWeightCandidate: Bool {
        guard !isExternalModel, !isUtilityModel, !isClosedProviderModel else { return false }
        let lowercased = searchText.lowercased()
        return lowercased.contains("glm") ||
            lowercased.contains("qwen") ||
            lowercased.contains("deepseek") ||
            lowercased.contains("kimi") ||
            lowercased.contains("moonshot") ||
            lowercased.contains("zai") ||
            lowercased.contains("llama") ||
            lowercased.contains("gpt-oss") ||
            lowercased.contains("oss")
    }

    var isEliteModel: Bool {
        let ids = [
            "anthropic/claude-opus-4-7",
            "openai/gpt-5.5",
            "qwen/qwen3.7-max",
            "moonshotai/kimi-k2.6",
            "anthropic/claude-sonnet-4-6",
            "openai/gpt-5.4",
            "google/gemini-3-pro",
            "openai/gpt-5.2",
            "openai/gpt-5.1",
            "openai/gpt-5",
            "google/gemini-2.5-pro",
            "anthropic/claude-opus-4-6",
            "anthropic/claude-sonnet-4-5",
            Self.nearPrivateDefaultModelID,
            "Qwen/Qwen3.5-122B-A10B",
            "Qwen/Qwen3.6-35B-A3B-FP8"
        ]
        return ids.contains(modelID) ||
            modelID.localizedCaseInsensitiveContains("claude-opus") ||
            modelID.localizedCaseInsensitiveContains("claude-sonnet") ||
            modelID.localizedCaseInsensitiveContains("claude-sonnet-4") ||
            modelID.localizedCaseInsensitiveContains("gemini-pro") ||
            modelID.localizedCaseInsensitiveContains("kimi") ||
            modelID.localizedCaseInsensitiveContains("deepseek")
    }

    var isPrivateVerifiableChatModel: Bool {
        !isExternalModel && isVerifiable && !isUtilityModel && !isLowerPriorityModel
    }

    var isLowerPriorityModel: Bool {
        let lowercased = searchText.lowercased()
        if lowercased.contains("deepseek-v4-flash") || lowercased.contains("deepseek v4 flash") {
            return false
        }
        return lowercased.contains("o3") ||
            lowercased.contains("o4-mini") ||
            lowercased.contains("haiku") ||
            lowercased.contains("mini") ||
            lowercased.contains("nano") ||
            lowercased.contains("lite") ||
            lowercased.contains("flash") ||
            lowercased.contains("gpt-oss") ||
            lowercased.contains("gemma")
    }

    var isDeprecatedPickerModel: Bool {
        guard !isIronclawModel else { return false }
        let comparableID = isNearCloudModel ? (nearCloudUnderlyingModelID ?? modelID) : modelID
        let lowercasedID = comparableID.lowercased()
        let lowercased = searchText.lowercased()

        if lowercasedID == "deepseek-ai/deepseek-v4-flash" {
            return false
        }
        if !isNearCloudModel,
           [
               "qwen/qwen3-30b-a3b-instruct-2507",
               "qwen/qwen3-vl-30b-a3b-instruct"
           ].contains(lowercasedID) {
            return false
        }

        if lowercased.contains("embedding") ||
            lowercased.contains("reranker") ||
            lowercased.contains("whisper") ||
            lowercased.contains("flux") {
            return true
        }

        if [
            "openai/gpt-oss-120b",
            "openai/gpt-5",
            "openai/gpt-5.1",
            "openai/gpt-5.2",
            "openai/gpt-5.4",
            "openai/gpt-4.1",
            "openai/o3",
            "google/gemini-2.5-pro",
            "google/gemini-2.5-flash",
            "anthropic/claude-opus-4-5",
            "anthropic/claude-sonnet-4-5",
            "anthropic/claude-haiku-4-5",
            "qwen/qwen3-30b-a3b-instruct-2507",
            "qwen/qwen3-vl-30b-a3b-instruct"
        ].contains(lowercasedID) {
            return true
        }

        if lowercased.contains("gpt-5.4") ||
            lowercased.contains("gpt-5.4-mini") ||
            lowercased.contains("gpt-oss") ||
            lowercased.contains("gpt-4.1") ||
            lowercased.contains("o3") ||
            lowercased.contains("o4-mini") ||
            lowercased.contains("haiku") ||
            lowercased.contains("sonnet-4-5") ||
            lowercased.contains("sonnet 4.5") ||
            lowercasedID.contains("-mini") ||
            lowercasedID.contains("/mini") ||
            lowercased.contains("nano") ||
            lowercased.contains("lite") ||
            lowercased.contains("flash") ||
            lowercased.contains("gemma") {
            return true
        }

        return false
    }

    var isRecommendedReasoningModel: Bool {
        let lowercased = searchText.lowercased()
        return isEliteModel ||
            lowercased.contains("reasoning") ||
            lowercased.contains("thinking") ||
            lowercased.contains("deepseek") ||
            lowercased.contains("gpt-5") ||
            lowercased.contains("qwen3.7") ||
            lowercased.contains("kimi-k2.6") ||
            lowercased.contains("gemini-3") ||
            lowercased.contains("gemini-2.5-pro") ||
            lowercased.contains("qwen3.5") ||
            lowercased.contains("qwen3.6") ||
            lowercased.contains("glm-5")
    }

    var isCodeModel: Bool {
        let lowercased = searchText.lowercased()
        return isIronclawModel ||
            lowercased.contains("code") ||
            lowercased.contains("coder") ||
            lowercased.contains("coding") ||
            lowercased.contains("software") ||
            lowercased.contains("repo") ||
            lowercased.contains("devstral")
    }

    var isVisionModel: Bool {
        let lowercased = searchText.lowercased()
        return lowercased.contains("vision") ||
            lowercased.contains("multimodal") ||
            lowercased.contains("image") ||
            lowercased.contains("-vl") ||
            lowercased.contains("/vl") ||
            lowercased.contains(" qwen-vl")
    }

    var isLongContextModel: Bool {
        if (metadata?.contextLength ?? 0) >= 128_000 {
            return true
        }
        let lowercased = searchText.lowercased()
        return lowercased.contains("long context") ||
            lowercased.contains("1m ctx") ||
            lowercased.contains("1m context") ||
            lowercased.contains("million token")
    }

    var capabilityBadges: [String] {
        var badges: [String] = []
        if isIronclawMobileRuntime {
            badges.append("Agent")
            badges.append("Mobile")
        } else if isIronclawHostedModel {
            badges.append("Agent")
            badges.append("Hosted")
        } else if isNearCloudModel {
            badges.append("NEAR AI Cloud")
            badges.append("Not attested")
        }
        if isRecommendedReasoningModel {
            badges.append("Reasoning")
        }
        if isEliteModel {
            badges.append("Cloud")
        }
        if isCodeModel {
            badges.append("Code")
        }
        if isVisionModel {
            badges.append("Vision")
        }
        if (metadata?.aliases ?? []).contains(where: { $0.localizedCaseInsensitiveContains("deepseek") }) {
            badges.append("DeepSeek alias")
        }
        if isLongContextModel {
            badges.append((metadata?.contextLength ?? 0) >= 1_000_000 ? "1M ctx" : "Long ctx")
        }
        if isVerifiable {
            badges.append("TEE")
        }
        return Array(badges.prefix(3))
    }

    private var searchText: String {
        ([modelID, displayName, metadata?.modelDescription] + (metadata?.aliases ?? []))
            .compactMap { $0 }
            .joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case modelID = "modelId"
        case publicModel = "public"
        case metadata
    }
}

struct CouncilPresetOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let models: [ModelOption]

    var isAvailable: Bool {
        models.count > 1
    }

    var modelIDs: [String] {
        models.map(\.id)
    }

    var previewNames: String {
        models.prefix(3).map(\.displayName).joined(separator: " + ") +
            (models.count > 3 ? " +\(models.count - 3)" : "")
    }
}
