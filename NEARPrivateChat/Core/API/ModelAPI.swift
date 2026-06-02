import Foundation

protocol ModelAPI: AnyObject {
    func fetchModels() async throws -> [ModelOption]
    func connectNearCloudAccount() async throws -> NearCloudConnectResponse
    func fetchNearCloudModels(apiKey: String?) async throws -> [ModelOption]
    func fetchNearCloudChatCompletion(
        apiKey: String,
        model: String,
        prompt: String,
        systemPrompt: String,
        advancedParams: AdvancedModelParams
    ) async throws -> String
}

final class PrivateChatModelAPI: ModelAPI {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchModels() async throws -> [ModelOption] {
        let response: ModelListResponse = try await client.request("/v1/model/list", method: "GET", authenticated: true)
        return response.models
    }

    func connectNearCloudAccount() async throws -> NearCloudConnectResponse {
        try await client.request("/v1/near-cloud/connect", method: "POST", body: NearCloudConnectPayload(), authenticated: true)
    }

    func fetchNearCloudModels(apiKey: String? = nil) async throws -> [ModelOption] {
        let trimmedAPIKey = Self.normalizedNearCloudAPIKey(apiKey)
        guard !trimmedAPIKey.isEmpty else {
            throw APIError.status(401, "Connect NEAR AI Cloud in Account before loading Cloud models.")
        }
        guard let url = URL(string: "https://cloud-api.near.ai/v1/model/list") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = APIClient.streamTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        let response: ModelListResponse = try await client.perform(request)
        return response.models
    }

    func fetchNearCloudChatCompletion(
        apiKey: String,
        model: String,
        prompt: String,
        systemPrompt: String,
        advancedParams: AdvancedModelParams = .defaults
    ) async throws -> String {
        let trimmedAPIKey = Self.normalizedNearCloudAPIKey(apiKey)
        guard !trimmedAPIKey.isEmpty else {
            throw APIError.status(401, "Connect NEAR AI Cloud in Account before sending with this route.")
        }
        guard let url = URL(string: "https://cloud-api.near.ai/v1/chat/completions") else {
            throw APIError.invalidURL
        }

        let trimmedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let messages: [CloudChatMessage] = [
            trimmedSystemPrompt.isEmpty ? nil : CloudChatMessage(role: "system", content: trimmedSystemPrompt),
            CloudChatMessage(role: "user", content: prompt)
        ].compactMap { $0 }
        let payload = CloudChatCompletionPayload(
            model: model,
            messages: messages,
            maxTokens: advancedParams.sanitized.maxTokens ?? 1_500,
            temperature: advancedParams.sanitized.temperature,
            topP: advancedParams.sanitized.topP,
            reasoning: advancedParams.sanitized.reasoningEffort.apiValue.map { CloudReasoningConfig(effort: $0) }
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = APIClient.streamTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try client.encoder.encode(payload)

        let response: CloudChatCompletionResponse = try await client.perform(request)
        guard let content = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw APIError.emptyResponse
        }
        return content
    }

    static func normalizedNearCloudAPIKey(_ apiKey: String?) -> String {
        var trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("authorization:") {
            trimmed = String(trimmed.dropFirst("authorization:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.lowercased().hasPrefix("bearer ") {
            trimmed = String(trimmed.dropFirst("bearer ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}

private struct NearCloudConnectPayload: Encodable {}

private struct CloudChatCompletionPayload: Encodable {
    let model: String
    let messages: [CloudChatMessage]
    let maxTokens: Int
    let temperature: Double?
    let topP: Double?
    let reasoning: CloudReasoningConfig?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case topP = "top_p"
        case reasoning
    }
}

private struct CloudReasoningConfig: Encodable {
    let effort: String
}

private struct CloudChatMessage: Codable {
    let role: String
    let content: String
}

private struct CloudChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        let message: CloudChatMessage
    }

    let choices: [Choice]
}
