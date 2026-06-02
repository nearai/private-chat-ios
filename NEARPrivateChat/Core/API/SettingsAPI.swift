import Foundation

protocol SettingsAPI: AnyObject {
    func fetchUserSettings() async throws -> UserSettingsResponse
    func updateUserSettings(
        systemPrompt: String,
        webSearchEnabled: Bool,
        notificationEnabled: Bool,
        appearance: String,
        largeTextAsFile: Bool,
        advancedParams: AdvancedModelParams
    ) async throws -> UserSettingsResponse
}

final class PrivateChatSettingsAPI: SettingsAPI {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchUserSettings() async throws -> UserSettingsResponse {
        try await client.request("/v1/users/me/settings", method: "GET", authenticated: true)
    }

    func updateUserSettings(
        systemPrompt: String,
        webSearchEnabled: Bool,
        notificationEnabled: Bool,
        appearance: String,
        largeTextAsFile: Bool,
        advancedParams: AdvancedModelParams
    ) async throws -> UserSettingsResponse {
        let payload = UpdateUserSettingsPayload(
            notification: notificationEnabled,
            systemPrompt: systemPrompt,
            webSearch: webSearchEnabled,
            appearance: appearance,
            largeTextAsFile: largeTextAsFile,
            temperature: advancedParams.sanitized.temperature,
            topP: advancedParams.sanitized.topP,
            maxTokens: advancedParams.sanitized.maxTokens
        )
        return try await client.request("/v1/users/me/settings", method: "POST", body: payload, authenticated: true)
    }
}

private struct UpdateUserSettingsPayload: Encodable {
    let notification: Bool
    let systemPrompt: String
    let webSearch: Bool
    let appearance: String
    let largeTextAsFile: Bool
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case notification
        case systemPrompt = "system_prompt"
        case webSearch = "web_search"
        case appearance
        case largeTextAsFile
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
    }
}
