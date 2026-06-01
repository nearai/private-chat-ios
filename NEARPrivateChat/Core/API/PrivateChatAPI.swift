import Foundation
#if canImport(UIKit)
import UIKit
#endif

private actor ResponseStreamVisibility {
    private var sawVisibleOutput = false

    func markVisibleOutput() {
        sawVisibleOutput = true
    }

    func hasVisibleOutput() -> Bool {
        sawVisibleOutput
    }
}

final class PrivateChatAPI {
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private static let streamTimeout: TimeInterval = 240
    static let maxUploadBytes = 10 * 1024 * 1024
    static let maxFilePreviewBytes = 96 * 1024
    var configuration: AppConfiguration
    var authToken: String?

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    func authURL(for provider: OAuthProvider, state: String? = nil, codeChallenge: String? = nil) throws -> URL {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        switch provider {
        case .near:
            components?.path = "/near-login"
        case .google, .github:
            components?.path = "/v1/auth/\(provider.rawValue)"
        }
        let callbackURL = Self.callbackURL(configuration.callbackURL, state: state)
        var queryItems = [
            URLQueryItem(name: "frontend_callback", value: callbackURL.absoluteString)
        ]
        if let state, !state.isEmpty {
            queryItems.append(URLQueryItem(name: "state", value: state))
        }
        if let codeChallenge, !codeChallenge.isEmpty {
            queryItems.append(URLQueryItem(name: "response_type", value: "code"))
            queryItems.append(URLQueryItem(name: "code_challenge", value: codeChallenge))
            queryItems.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw APIError.invalidURL }
        return url
    }

    func parseAuthCallback(
        _ url: URL,
        expectedState: String? = nil
    ) throws -> AuthCodeCallback {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidCallback
        }
        let values = Self.callbackValues(from: components)
        guard let expectedState, !expectedState.isEmpty else {
            throw APIError.status(401, "Sign-in must start from an active app request.")
        }
        let callbackStates = values["state", default: []].filter { !$0.isEmpty }
        let hasExpectedState = callbackStates.contains(expectedState)
        guard hasExpectedState else {
            throw APIError.status(401, "Sign-in callback failed state validation.")
        }
        guard Self.authToken(from: values) == nil else {
            throw APIError.status(426, "This app no longer accepts bearer tokens through sign-in links. Update the auth service to return an authorization code.")
        }
        guard let code = Self.firstNonEmptyValue(named: "code", in: values) else {
            throw APIError.invalidCallback
        }
        return AuthCodeCallback(
            code: code,
            state: expectedState,
            providerState: callbackStates.first { $0 != expectedState }
        )
    }

    func exchangeAuthCode(
        provider: OAuthProvider,
        callback: AuthCodeCallback,
        codeVerifier: String
    ) async throws -> AuthSession {
        let payload = AuthCodeExchangePayload(
            provider: provider.rawValue,
            code: callback.code,
            codeVerifier: codeVerifier,
            redirectURI: Self.callbackURL(configuration.callbackURL, state: callback.state).absoluteString,
            state: callback.state
        )
        do {
            let response: AuthCodeExchangeResponse = try await request(
                "/v1/auth/\(provider.rawValue)/exchange",
                method: "POST",
                body: payload,
                authenticated: false
            )
            return response.session
        } catch APIError.status(let code, _) where code == 404 || code == 405 {
            let response: AuthCodeExchangeResponse = try await request(
                "/v1/auth/exchange",
                method: "POST",
                body: payload,
                authenticated: false
            )
            return response.session
        }
    }

    private static func callbackURL(_ url: URL, state: String?) -> URL {
        guard let state, !state.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "state" }
        queryItems.append(URLQueryItem(name: "state", value: state))
        components.queryItems = queryItems
        return components.url ?? url
    }

    private static func callbackValues(from components: URLComponents) -> [String: [String]] {
        var values: [String: [String]] = [:]
        append(components.queryItems, to: &values)
        if let fragment = components.fragment,
           let fragmentComponents = URLComponents(string: "nearprivatechat://auth?\(fragment)") {
            append(fragmentComponents.queryItems, to: &values)
        }
        return values
    }

    private static func append(_ queryItems: [URLQueryItem]?, to values: inout [String: [String]]) {
        for item in queryItems ?? [] {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            values[name, default: []].append(item.value ?? "")
        }
    }

    private static func firstNonEmptyValue(named name: String, in values: [String: [String]]) -> String? {
        values[name]?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func authToken(from values: [String: [String]]) -> String? {
        for name in [
            "token",
            "session_token",
            "sessionToken",
            "auth_token",
            "authToken",
            "access_token",
            "accessToken",
            "bearer_token",
            "bearerToken"
        ] {
            if let token = firstNonEmptyValue(named: name, in: values) {
                return token
            }
        }
        return nil
    }

    private static func sessionID(from values: [String: [String]]) -> String? {
        for name in ["session_id", "sessionId", "sid"] {
            if let sessionID = firstNonEmptyValue(named: name, in: values) {
                return sessionID
            }
        }
        return nil
    }

    func fetchProfile() async throws -> UserProfile {
        try await request("/v1/users/me", method: "GET", authenticated: true)
    }

    func fetchUserSettings() async throws -> UserSettingsResponse {
        try await request("/v1/users/me/settings", method: "GET", authenticated: true)
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
        return try await request("/v1/users/me/settings", method: "POST", body: payload, authenticated: true)
    }

    func fetchSubscriptionPlans() async throws -> [SubscriptionPlan] {
        let response: SubscriptionPlansResponse = try await request("/v1/subscriptions/plans", method: "GET", authenticated: false)
        return response.plans
    }

    func fetchSubscriptions(includeInactive: Bool = false) async throws -> [SubscriptionInfo] {
let suffix = includeInactive ? "?include_inactive=true" : ""
        let response: SubscriptionsResponse = try await request("/v1/subscriptions\(suffix)", method: "GET", authenticated: true)
        return response.subscriptions
    }

    func fetchModels() async throws -> [ModelOption] {
let response: ModelListResponse = try await request("/v1/model/list", method: "GET", authenticated: true)
        return response.models
    }

    func connectNearCloudAccount() async throws -> NearCloudConnectResponse {
        return try await request("/v1/near-cloud/connect", method: "POST", body: NearCloudConnectPayload(), authenticated: true)
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
        request.timeoutInterval = Self.streamTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        let response: ModelListResponse = try await perform(request)
        return response.models
    }

    func fetchConversations() async throws -> [ConversationSummary] {
        return try await request("/v1/conversations", method: "GET", authenticated: true)
    }

    func createConversation(title: String) async throws -> ConversationSummary {
let payload = ConversationCreatePayload(metadata: ["title": title])
        return try await request("/v1/conversations", method: "POST", body: payload, authenticated: true)
    }

    func createConversation(title: String, metadata: [String: String]) async throws -> ConversationSummary {
var payloadMetadata = metadata
        payloadMetadata["title"] = title
        let payload = ConversationCreatePayload(metadata: payloadMetadata)
        return try await request("/v1/conversations", method: "POST", body: payload, authenticated: true)
    }

    func addItemsToConversation(_ conversationID: String, items: [ConversationImportItem]) async throws {
let payload = ConversationItemsCreatePayload(items: items)
        let bodyData = try encoder.encode(payload)
        let request = try makeRequest(
            path: Self.conversationPath(conversationID, suffix: ["items"]),
            method: "POST",
            body: bodyData,
            authenticated: true
        )
        _ = try await performRaw(request)
    }

    func updateConversationTitle(_ conversationID: String, title: String) async throws {
let payload = ConversationCreatePayload(metadata: ["title": title])
        let _: ConversationSummary = try await request(
            Self.conversationPath(conversationID),
            method: "POST",
            body: payload,
            authenticated: true
        )
    }

    func fetchConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse {
        return try await request(Self.conversationPath(conversationID, suffix: ["items"]), method: "GET", authenticated: true)
    }

    func uploadFile(from url: URL) async throws -> ChatAttachment {
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let (data, filename, mimeType) = try await Task.detached(priority: .userInitiated) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = values.fileSize, fileSize > Self.maxUploadBytes {
                throw APIError.status(413, "Files must be 10 MB or smaller.")
            }
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maxUploadBytes else {
                throw APIError.status(413, "Files must be 10 MB or smaller.")
            }
            let filename = Self.sanitizedMultipartFilename(url.lastPathComponent.isEmpty ? "Attachment" : url.lastPathComponent)
            return (data, filename, Self.mimeType(for: url))
        }.value
        let upload = try Self.normalizedVisionUpload(data: data, filename: filename, mimeType: mimeType)
        return try await uploadFileData(
            upload.data,
            filename: upload.filename,
            mimeType: upload.mimeType
        )
    }

    func uploadTextFile(filename: String, text: String) async throws -> ChatAttachment {
        guard let data = text.data(using: .utf8) else {
            throw APIError.emptyResponse
        }
        return try await uploadFileData(data, filename: Self.sanitizedMultipartFilename(filename), mimeType: "text/plain")
    }

    func fetchFiles() async throws -> RemoteFilesResponse {
        try await request("/v1/files", method: "GET", authenticated: true)
    }

    func fetchFile(_ fileID: String) async throws -> RemoteFileInfo {
        try await request("/v1/files/\(try Self.safePathSegment(fileID))", method: "GET", authenticated: true)
    }

    func fetchFileContent(_ fileID: String) async throws -> Data {
        let request = try makeRequest(path: "/v1/files/\(try Self.safePathSegment(fileID))/content", method: "GET", body: nil, authenticated: true)
        return try await performRaw(request)
    }

    func fetchFilePreviewContent(_ fileID: String, maxBytes: Int = PrivateChatAPI.maxFilePreviewBytes) async throws -> Data {
        let byteLimit = max(1, min(maxBytes, Self.maxUploadBytes))
        var request = try makeRequest(path: "/v1/files/\(try Self.safePathSegment(fileID))/content", method: "GET", body: nil, authenticated: true)
        request.setValue("bytes=0-\(byteLimit - 1)", forHTTPHeaderField: "Range")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.emptyResponse
        }

        var data = Data()
        data.reserveCapacity(byteLimit)
        for try await byte in bytes {
            if data.count >= byteLimit { break }
            data.append(byte)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError.status(http.statusCode, decodeErrorMessage(from: data))
        }
        return data
    }

    private func uploadFileData(_ data: Data, filename: String, mimeType: String) async throws -> ChatAttachment {
        guard data.count <= Self.maxUploadBytes else {
            throw APIError.status(413, "Files must be 10 MB or smaller.")
        }
        let safeFilename = Self.sanitizedMultipartFilename(filename)
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipartField(name: "purpose", value: Self.uploadPurpose(filename: safeFilename, mimeType: mimeType), boundary: boundary)
        body.appendMultipartField(name: "expires_after[anchor]", value: "created_at", boundary: boundary)
        body.appendMultipartField(name: "expires_after[seconds]", value: "36000", boundary: boundary)
        body.appendMultipartFile(
            name: "file",
            filename: safeFilename,
            mimeType: mimeType,
            data: data,
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")

        var request = try makeRequest(path: "/v1/files", method: "POST", body: body, authenticated: true)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let response: FileUploadResponse = try await perform(request)
        return ChatAttachment(
            id: response.id,
            name: response.filename,
            kind: response.purpose,
            bytes: response.bytes
        )
    }

    func fetchReadableConversation(_ conversationID: String) async throws -> ConversationSummary {
        try await readableRequest(Self.conversationPath(conversationID))
    }

    func fetchReadableConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse {
        try await readableRequest(Self.conversationPath(conversationID, suffix: ["items"]))
    }

    func deleteConversation(_ conversationID: String) async throws {
        let _: EmptyResponse = try await request(
            Self.conversationPath(conversationID),
            method: "DELETE",
            authenticated: true
        )
    }

    func cloneConversation(_ conversationID: String) async throws -> ConversationSummary {
        try await request(
            Self.conversationPath(conversationID, suffix: ["clone"]),
            method: "POST",
            body: EmptyPayload(),
            authenticated: true
        )
    }

    func archiveConversation(_ conversationID: String) async throws {
        let request = try makeRequest(
            path: Self.conversationPath(conversationID, suffix: ["archive"]),
            method: "POST",
            body: nil,
            authenticated: true
        )
        _ = try await performRaw(request)
    }

    func unarchiveConversation(_ conversationID: String) async throws {
        let request = try makeRequest(
            path: Self.conversationPath(conversationID, suffix: ["archive"]),
            method: "DELETE",
            body: nil,
            authenticated: true
        )
        _ = try await performRaw(request)
    }

    func pinConversation(_ conversationID: String) async throws {
        let request = try makeRequest(
            path: Self.conversationPath(conversationID, suffix: ["pin"]),
            method: "POST",
            body: nil,
            authenticated: true
        )
        _ = try await performRaw(request)
    }

    func unpinConversation(_ conversationID: String) async throws {
        let request = try makeRequest(
            path: Self.conversationPath(conversationID, suffix: ["pin"]),
            method: "DELETE",
            body: nil,
            authenticated: true
        )
        _ = try await performRaw(request)
    }

    func fetchConversationShares(_ conversationID: String) async throws -> ConversationSharesListResponse {
        try await request(Self.conversationPath(conversationID, suffix: ["shares"]), method: "GET", authenticated: true)
    }

    func fetchSharedWithMe() async throws -> [SharedConversationInfo] {
        return try await request("/v1/shared-with-me", method: "GET", authenticated: true)
    }

    func createPublicShare(_ conversationID: String) async throws -> [ConversationShareInfo] {
        let payload = CreateConversationSharePayload(permission: SharePermission.read.rawValue, target: .public)
        return try await request(
            Self.conversationPath(conversationID, suffix: ["shares"]),
            method: "POST",
            body: payload,
            authenticated: true
        )
    }

    func createDirectShare(
        _ conversationID: String,
        recipients: [ShareInviteRecipient],
        permission: String
    ) async throws -> [ConversationShareInfo] {
        let payload = CreateConversationSharePayload(
            permission: SharePermission.sanitized(permission).rawValue,
            target: .direct(recipients)
        )
        return try await request(
            Self.conversationPath(conversationID, suffix: ["shares"]),
            method: "POST",
            body: payload,
            authenticated: true
        )
    }

    func createOrganizationShare(
        _ conversationID: String,
        emailPattern: String,
        permission: String
    ) async throws -> [ConversationShareInfo] {
        let payload = CreateConversationSharePayload(
            permission: SharePermission.sanitized(permission).rawValue,
            target: .organization(emailPattern)
        )
        return try await request(
            Self.conversationPath(conversationID, suffix: ["shares"]),
            method: "POST",
            body: payload,
            authenticated: true
        )
    }

    func createGroupShare(
        _ conversationID: String,
        groupID: String,
        permission: String
    ) async throws -> [ConversationShareInfo] {
        let payload = CreateConversationSharePayload(
            permission: SharePermission.sanitized(permission).rawValue,
            target: .group(groupID)
        )
        return try await request(
            Self.conversationPath(conversationID, suffix: ["shares"]),
            method: "POST",
            body: payload,
            authenticated: true
        )
    }

    func fetchShareGroups() async throws -> [ShareGroupInfo] {
        try await request("/v1/share-groups", method: "GET", authenticated: true)
    }

    func createShareGroup(name: String, members: [ShareInviteRecipient]) async throws -> ShareGroupInfo {
        let payload = ShareGroupPayload(name: name, members: members)
        return try await request("/v1/share-groups", method: "POST", body: payload, authenticated: true)
    }

    func updateShareGroup(_ groupID: String, name: String, members: [ShareInviteRecipient]) async throws -> ShareGroupInfo {
        let payload = ShareGroupPayload(name: name, members: members)
        return try await request("/v1/share-groups/\(try Self.safePathSegment(groupID))", method: "PATCH", body: payload, authenticated: true)
    }

    func deleteShareGroup(_ groupID: String) async throws {
        let _: EmptyResponse = try await request(
            "/v1/share-groups/\(try Self.safePathSegment(groupID))",
            method: "DELETE",
            authenticated: true
        )
    }

    func deleteConversationShare(_ conversationID: String, shareID: String) async throws {
        let _: EmptyResponse = try await request(
            Self.conversationPath(conversationID, suffix: ["shares", try Self.safePathSegment(shareID)]),
            method: "DELETE",
            authenticated: true
        )
    }

    func deleteFile(_ fileID: String) async throws {
        let _: EmptyResponse = try await request(
            "/v1/files/\(try Self.safePathSegment(fileID))",
            method: "DELETE",
            authenticated: true
        )
    }

    func signOut(sessionID: String) async throws {
        guard !sessionID.isEmpty else { return }
        let payload = LogoutPayload(sessionID: sessionID)
        let _: EmptyResponse = try await request("/v1/auth/logout", method: "POST", body: payload, authenticated: true)
    }

    func fetchAttestationReport(
        nonce: String,
        signingAlgorithm: String = "ecdsa",
        model: String? = nil
    ) async throws -> AttestationSnapshot {
        var query = [
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "signing_algo", value: signingAlgorithm)
        ]
        if let model, !model.isEmpty {
            query.append(URLQueryItem(name: "model", value: model))
        }
        var components = URLComponents()
        components.path = "/v1/attestation/report"
        components.queryItems = query
        guard let path = components.string else { throw APIError.invalidURL }

        let request = try makeRequest(path: path, method: "GET", body: nil, authenticated: false)
        let data = try await performRaw(request)
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
        let prettyJSON = String(data: prettyData, encoding: .utf8) ?? String(data: data, encoding: .utf8) ?? ""

        let coveredModelIDs = Self.extractModelIDs(from: jsonObject)
        let attestedAt = Self.extractAttestationDate(from: jsonObject) ?? Date()
        return AttestationSnapshot(
            nonce: nonce,
            signingAlgorithm: signingAlgorithm,
            model: coveredModelIDs.first,
            coveredModelIDs: coveredModelIDs,
            fetchedAt: attestedAt,
            chatGatewayAddress: Self.extractString(
                from: jsonObject,
                path: ["chat_api_gateway_attestation", "signing_address"]
            ),
            cloudGatewayAddress: Self.extractString(
                from: jsonObject,
                path: ["cloud_api_gateway_attestation", "signing_address"]
            ),
            modelAttestationCount: Self.extractArrayCount(from: jsonObject, path: ["model_attestations"]),
            prettyJSON: prettyJSON
        )
    }

    func streamResponse(
        model: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        webSearchEnabled: Bool,
        systemPrompt: String,
        advancedParams: AdvancedModelParams = .defaults,
        initiator: String = "new_message",
        visibleOutputTimeout: TimeInterval? = nil,
        onEvent: @escaping (ResponseStreamEvent) async -> Void
    ) async throws {
let promptText = text.isEmpty && !attachments.isEmpty
            ? "Review the attached file context. Lead with the most useful summary, then call out decisions, risks, and next actions."
            : text
        let content = Self.responseContent(promptText: promptText, attachments: attachments)
        let payload = ResponsePayload(
            model: model,
            input: [
                ResponseInput(role: "user", content: content)
            ],
            conversation: conversationID,
            stream: true,
            tools: webSearchEnabled ? [ResponseTool(type: "web_search")] : nil,
            include: webSearchEnabled ? ["web_search_call.action.sources"] : nil,
            instructions: Self.responseInstructions(webSearchEnabled: webSearchEnabled, systemPrompt: systemPrompt),
            signingAlgo: "ecdsa",
            previousResponseID: previousResponseID,
            initiator: initiator,
            temperature: advancedParams.sanitized.temperature,
            topP: advancedParams.sanitized.topP,
            maxTokens: advancedParams.sanitized.maxTokens
        )

        let body = try encoder.encode(payload)
        var request = try makeRequest(path: "/v1/responses", method: "POST", body: body, authenticated: true)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.streamTimeout

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try await validateStreamingResponse(response, bytes: bytes)

        let visibility = ResponseStreamVisibility()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard line.hasPrefix("data:") else { continue }
                    let dataLine = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !dataLine.isEmpty, dataLine != "[DONE]" else { continue }
                    guard let eventData = dataLine.data(using: .utf8),
                          let event = self.parseStreamEvent(eventData) else { continue }
                    if event.hasVisibleOutput {
                        await visibility.markVisibleOutput()
                    }
                    await onEvent(event)
                    switch event {
                    case let .failed(message):
                        throw APIError.status(403, message)
                    case .completed:
                        return
                    default:
                        break
                    }
                }
                throw APIError.status(502, "The response stream ended early.")
            }

            if let visibleOutputTimeout {
                group.addTask {
                    let nanoseconds = UInt64(max(0.1, visibleOutputTimeout) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nanoseconds)
                    if await !visibility.hasVisibleOutput() {
                        throw APIError.status(408, "The selected model is still reasoning without visible output.")
                    }

                    while !Task.isCancelled {
                        try await Task.sleep(nanoseconds: 60_000_000_000)
                    }
                }
            }

            do {
                _ = try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
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
        request.timeoutInterval = Self.streamTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(payload)

        let response: CloudChatCompletionResponse = try await perform(request)
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

    private func request<T: Decodable, B: Encodable>(
        _ path: String,
        method: String,
        body: B,
        authenticated: Bool
    ) async throws -> T {
        let bodyData = try encoder.encode(body)
        let request = try makeRequest(path: path, method: method, body: bodyData, authenticated: authenticated)
        return try await perform(request)
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String,
        authenticated: Bool
    ) async throws -> T {
        let request = try makeRequest(path: path, method: method, body: nil, authenticated: authenticated)
        return try await perform(request)
    }

    private func readableRequest<T: Decodable>(_ path: String) async throws -> T {
        let trimmedToken = authToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedToken.isEmpty else {
            return try await request(path, method: "GET", authenticated: false)
        }

        do {
            return try await request(path, method: "GET", authenticated: true)
        } catch APIError.status(let code, _) where code == 401 || code == 403 {
            return try await request(path, method: "GET", authenticated: false)
        }
    }

    private static func conversationPath(_ conversationID: String, suffix: [String] = []) throws -> String {
        let conversationSegment = try safePathSegment(conversationID, minimumLength: 6)
        let pathSegments = ["v1", "conversations", conversationSegment] + suffix
        return "/" + pathSegments.joined(separator: "/")
    }

    static func isSafeAPIPathID(_ value: String, minimumLength: Int = 1) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == value,
              trimmed.count >= minimumLength,
              trimmed.count <= 256,
              !trimmed.contains("."),
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains(":"),
              !trimmed.contains("%") else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func safePathSegment(_ value: String, minimumLength: Int = 1) throws -> String {
        guard isSafeAPIPathID(value, minimumLength: minimumLength),
              let encoded = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "_-"))) else {
            throw APIError.invalidURL
        }
        return encoded
    }

    private func makeRequest(path: String, method: String, body: Data?, authenticated: Bool) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: configuration.baseURL)?.absoluteURL else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1000", forHTTPHeaderField: "ngrok-skip-browser-warning")
        if authenticated {
            let trimmedToken = authToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedToken.isEmpty else { throw APIError.unauthenticated }
            // NEAR backend uses cookie-based session auth — the live cookie
            // header is `nearai-prod_crabshack_session=<hex>`. OAuth-issued
            // JWTs go through `Authorization: Bearer …`. Send both so
            // whichever the endpoint validates wins; the unused one is
            // ignored. Also send browser-like Origin/Referer/UA headers
            // because the backend may reject non-browser requests outright
            // (SameSite=Lax cookies often get this treatment).
            request.setValue(
                "nearai-prod_crabshack_session=\(trimmedToken)",
                forHTTPHeaderField: "Cookie"
            )
            request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
            request.setValue("https://private.near.ai", forHTTPHeaderField: "Origin")
            request.setValue("https://private.near.ai/", forHTTPHeaderField: "Referer")
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )
        }
        request.httpBody = body
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.emptyResponse
        }
        #if DEBUG
        // Diagnostic — surface the exact HTTP status + body the server
        // returned. Visible in Xcode console when iterating on the
        // auth/cookie scheme.
        if !(200..<300).contains(http.statusCode) {
            let rawBody = String(data: data.prefix(400), encoding: .utf8) ?? "<binary>"
            let path = request.url?.path ?? "<unknown>"
            print("[NEAR API] \(request.httpMethod ?? "GET") \(path) → HTTP \(http.statusCode)\n  body: \(rawBody)\n  headers: \(http.allHeaderFields)")
        }
        #endif
        guard (200..<300).contains(http.statusCode) else {
            let detail = decodeErrorMessage(from: data)
            let suffix = detail.isEmpty ? "" : " — \(detail)"
            throw APIError.status(http.statusCode, "HTTP \(http.statusCode)\(suffix)")
        }
        if T.self == EmptyResponse.self, data.isEmpty {
            guard let emptyResponse = EmptyResponse() as? T else {
                throw APIError.emptyResponse
            }
            return emptyResponse
        }
        guard !data.isEmpty else { throw APIError.emptyResponse }
        return try decoder.decode(T.self, from: data)
    }

    private func performRaw(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.status(http.statusCode, decodeErrorMessage(from: data))
        }
        return data
    }

    private func validateStreamingResponse(
        _ response: URLResponse,
        bytes: URLSession.AsyncBytes
    ) async throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            var message = ""
            for try await line in bytes.lines {
                if line.hasPrefix("data:") {
                    let dataLine = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let data = dataLine.data(using: .utf8) {
                        message = decodeErrorMessage(from: data)
                    }
                    if !message.isEmpty { break }
                } else {
                    message += line
                }
                if message.count > 1_000 { break }
            }
            if let data = message.data(using: .utf8) {
                let decoded = decodeErrorMessage(from: data)
                if !decoded.isEmpty {
                    message = decoded
                }
            }
            throw APIError.status(http.statusCode, message)
        }
    }

    private func decodeErrorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["detail", "error", "message"] {
                if let value = object[key] as? String {
                    return value
                }
                if let nested = object[key] as? [String: Any],
                   let message = nested["message"] as? String {
                    return message
                }
            }
        }
        guard let raw = String(data: Data(data.prefix(240)), encoding: .utf8) else { return "" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("<"), !trimmed.hasPrefix("{") else { return "" }
        return trimmed
    }

    func parseStreamEvent(_ data: Data) -> ResponseStreamEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return nil
        }

        switch type {
        case "error", "response.error":
            return .failed(Self.firstErrorMessage(in: object) ?? "The model request failed.")
        case "response.web_search_call.in_progress", "response.web_search_call.searching":
            return .webSearchStarted(query: nil)
        case "response.web_search_call.completed":
            return .webSearchCompleted(query: nil, sources: [])
        case "response.created":
            let response = object["response"] as? [String: Any]
            return .created(responseID: response?["id"] as? String ?? "")
        case "response.reasoning.delta", "response.reasoning.done":
            return .reasoningStarted
        case "response.output_item.added":
            let item = object["item"] as? [String: Any]
            switch item?["type"] as? String {
            case "reasoning":
                return .reasoningStarted
            case "web_search_call":
                let action = item?["action"] as? [String: Any]
                return .webSearchStarted(query: action?["query"] as? String)
            default:
                return nil
            }
        case "response.output_text.delta":
            let delta = object["delta"] as? String ?? ""
            if let failedMessage = Self.streamFailureMessage(from: delta) {
                return .failed(failedMessage)
            }
            return .textDelta(delta)
        case "response.output_text.done":
            let text = object["text"] as? String
            if let failedMessage = Self.streamFailureMessage(from: text) {
                return .failed(failedMessage)
            }
            return .itemDone(text: text)
        case "response.content_part.done":
            let part = object["part"] as? [String: Any]
            let text = part?["text"] as? String
            if let failedMessage = Self.streamFailureMessage(from: text) {
                return .failed(failedMessage)
            }
            return .itemDone(text: text)
        case "response.output_item.done":
            let item = object["item"] as? [String: Any]
            if item?["type"] as? String == "web_search_call" {
                let action = item?["action"] as? [String: Any]
                return .webSearchCompleted(
                    query: action?["query"] as? String,
                    sources: Self.webSearchSources(from: action)
                )
            }
            let content = item?["content"] as? [[String: Any]]
            let text = content?.compactMap { $0["text"] as? String }.joined()
            if let failedMessage = Self.streamFailureMessage(from: text) {
                return .failed(failedMessage)
            }
            return .itemDone(text: text)
        case "conversation.title.updated":
            return .titleUpdated(object["conversation_title"] as? String ?? "")
        case "response.completed":
            let response = object["response"] as? [String: Any]
            return .completed(responseID: response?["id"] as? String)
        case "response.failed":
            let text = object["text"] as? String
            let response = object["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any]
            return .failed(
                Self.streamFailureMessage(from: text) ??
                    text ??
                    Self.firstErrorMessage(in: response) ??
                    error?["message"] as? String ??
                    "The model is currently unavailable."
            )
        default:
            return nil
        }
    }

    private static func firstErrorMessage(in object: [String: Any]?) -> String? {
        guard let object else { return nil }
        for key in ["error", "message", "detail"] {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
            if let nested = object[key] as? [String: Any] {
                if let message = firstErrorMessage(in: nested) {
                    return message
                }
            }
        }
        return nil
    }

    private static func streamFailureMessage(from text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        for key in ["error", "message", "detail"] {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
            if let nested = object[key] as? [String: Any],
               let message = nested["message"] as? String,
               !message.isEmpty {
                return message
            }
        }
        return nil
    }

    private static func extractString(from object: Any, path: [String]) -> String? {
        var current = object
        for key in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[key] else {
                return nil
            }
            current = next
        }
        return current as? String
    }

    private static func extractArrayCount(from object: Any, path: [String]) -> Int {
        var current = object
        for key in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[key] else {
                return 0
            }
            current = next
        }
        return (current as? [Any])?.count ?? 0
    }

    private static func extractModelIDs(from object: Any) -> [String] {
        var ids: [String] = []
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for key in ["model", "model_id", "modelId", "id", "name"] {
                    if let modelID = dictionary[key] as? String,
                       looksLikeModelID(modelID) {
                        ids.append(modelID)
                    }
                }
                dictionary.values.forEach(walk)
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(object)
        var seen = Set<String>()
        return ids.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func looksLikeModelID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 160 else { return false }
        return trimmed.contains("/") || trimmed.localizedCaseInsensitiveContains("glm") || trimmed.localizedCaseInsensitiveContains("qwen")
    }

    private static func extractAttestationDate(from object: Any) -> Date? {
        let formatter = ISO8601DateFormatter()
        var candidates: [Any] = []
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for key in ["attested_at", "generated_at", "created_at", "timestamp", "time"] {
                    if let candidate = dictionary[key] {
                        candidates.append(candidate)
                    }
                }
                dictionary.values.forEach(walk)
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(object)
        for candidate in candidates {
            if let string = candidate as? String,
               let date = formatter.date(from: string) {
                return date
            }
            if let number = candidate as? TimeInterval, number > 1_000_000_000 {
                return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1_000 : number)
            }
        }
        return nil
    }

    /// Steering that lets the model attach exactly one structured "near-widget"
    /// block to an answer when the answer's natural shape is a number, a trend,
    /// a comparison, a digest, or a preview of actionable next moves. Parsed
    /// client-side by `MessageWidget.extract` and rendered as a native card.
    /// This is the one sanctioned exception to the "avoid raw JSON" rule in the
    /// answer contract above.
    static var widgetInstructionForTesting: String { widgetInstruction }

    static func responseInstructionsForTesting(webSearchEnabled: Bool, systemPrompt: String = "") -> String {
        responseInstructions(webSearchEnabled: webSearchEnabled, systemPrompt: systemPrompt)
    }

    static func responseContentDescriptorsForTesting(attachments: [ChatAttachment]) -> [(type: String, fileID: String?)] {
        responseContent(promptText: "Test prompt", attachments: attachments).map { ($0.type, $0.fileID) }
    }

    private static func responseContent(promptText: String, attachments: [ChatAttachment]) -> [ResponseContent] {
        [ResponseContent(type: "input_text", text: promptText, fileID: nil)] +
            attachments.map { attachment in
                ResponseContent(
                    type: attachment.isNativeVisionImage ? "input_image" : "input_file",
                    text: nil,
                    fileID: attachment.id
                )
            }
    }

    private static let widgetInstruction = """


    Generative widgets:
    - When the answer is naturally a trend over time, a head-to-head comparison, a multi-item news digest, a preview of proposed actions, or a key tracked metric that benefits from emphasis, ALSO append exactly one fenced code block tagged near-widget containing a compact JSON object. This is the only place raw JSON is allowed.
    - Use kind action_plan when the user asks to turn context/files/tables into actions, trackers, reminders, calendar-worthy items, tasks, decisions, risks, or things they should care about. Stage commands only; do not claim a tracker, reminder, or calendar event was created unless the app confirms it.
    - For action_plan actions, include structured candidate fields when known: source, date, time, duration, recurrence, timezone, location, attendees, missing_fields, and confidence. Put fuzzy values like "upon waking" in schedule/time and list the concrete field that still needs confirmation in missing_fields.
    - Do NOT emit a widget for a simple one-off number, a short factual reply, or a plain explanatory answer — only when a native card materially helps. Put the prose answer first; the near-widget block goes last; never emit more than one.
    - Schema (include only the keys that apply):
      {"kind":"chart|metric|comparison|news_brief|action_plan","title":"short source label","time":"e.g. 1h ago","freshness":"fresh|stale","follow_up":"a natural follow-up question","chart":{"label":"Project progress","value":"42% complete","delta":"+3 items","trend":"up|down|flat","points":[20,28,35,42],"caption":"context line","timeframe":"past week"},"metric":{"label":"Open risks","value":"4","delta":"+1","trend":"up|down|flat","caption":"..."},"comparison":{"subtitle":"A vs B","columns":["A","B"],"rows":[{"label":"Row","cells":[{"text":"yes","tone":"good"},{"text":"no","tone":"off"}]}]},"news_brief":{"heading":"Today · 3 stories","stories":[{"title":"...","tag":"Research","sources":[{"label":"Source","domain":"example.com"}]}]},"action_plan":{"heading":"Top actions","summary":"why these matter","actions":[{"title":"...","type":"tracker|briefing|reminder|calendar|task|decision|risk|question|interest","detail":"why or missing details","schedule":"optional cadence/time","source":"file.xlsx · Supplements row 12","date":"YYYY-MM-DD if known","time":"8:00 AM or upon waking","duration":"30m","recurrence":"daily","timezone":"America/Toronto","location":"optional","attendees":["optional email/name"],"missing_fields":["exact bedtime"],"confidence":0.84,"command":"Create a tracker for ... every ...","tone":"good|warn|bad|neutral"}]}}
    """

    private static func responseInstructions(webSearchEnabled: Bool, systemPrompt: String) -> String {
        let date = Date.now.formatted(date: .complete, time: .omitted)
        let trimmedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let userInstruction = trimmedSystemPrompt.isEmpty ? "" : "\n\nUser system preference:\n\(trimmedSystemPrompt)"
        if webSearchEnabled {
            return """
            You are NEAR Private Chat. The current date is \(date). For current, recent, time-sensitive, or specific public factual questions, call web_search before answering.

            Answer contract:
            - Lead with the direct answer in 1-3 tight sentences.
            - Use the app-supported Markdown subset: headings, ordered and unordered lists, nested lists, GitHub-flavored tables, fenced code blocks with language tags, links, bold, italic, and blockquotes.
            - Keep tables compact enough to read on a phone; prefer a list when a table would be too wide.
            - Prefer concrete dates, names, numbers, and named sources.
            - Separate facts, inference, and recommended next actions when the topic is ambiguous.
            - Avoid generic caveats, fake tool calls, XML, HTML, Mermaid, LaTeX/math-only markup, raw JSON outside the sanctioned near-widget block, and emoji headings.
            - Treat attached files as user-provided project context and cite filenames when helpful.\(Self.widgetInstruction)\(userInstruction)
            """
        }

        return """
        You are NEAR Private Chat. The current date is \(date).

        Answer contract:
        - Lead with the direct answer in 1-3 tight sentences.
        - Use the app-supported Markdown subset: headings, ordered and unordered lists, nested lists, GitHub-flavored tables, fenced code blocks with language tags, links, bold, italic, and blockquotes.
        - Keep tables compact enough to read on a phone; prefer a list when a table would be too wide.
        - Prefer concrete dates, names, and numbers.
        - Separate facts, inference, and recommended next actions when the topic is ambiguous.
        - Avoid generic caveats, fake tool calls, XML, HTML, Mermaid, LaTeX/math-only markup, raw JSON outside the sanctioned near-widget block, and emoji headings.
        - Treat attached files as user-provided project context and cite filenames when helpful.
        - Be explicit when an answer may require current information.\(Self.widgetInstruction)\(userInstruction)
        """
    }

    private static func webSearchSources(from rawSources: [[String: Any]]) -> [WebSearchSource] {
        rawSources.compactMap { source in
            guard let rawURL = source["url"] as? String,
                  let url = WebSearchSource.sanitizedURLString(rawURL) else { return nil }
            return WebSearchSource(
                type: firstSourceString(in: source, keys: ["type", "source_type", "kind"]),
                url: url,
                title: firstSourceString(in: source, keys: ["title", "name", "display_title"]),
                publishedAt: firstSourceString(in: source, keys: ["published_at", "publishedAt", "date", "published"]),
                snippet: firstSourceString(in: source, keys: ["snippet", "description", "summary", "text"])
            )
        }
    }

    private static func webSearchSources(from rawObject: Any?) -> [WebSearchSource] {
        guard let rawObject else { return [] }
        if let sources = rawObject as? [[String: Any]] {
            return webSearchSources(from: sources)
        }
        if let dictionary = rawObject as? [String: Any] {
            var collected: [WebSearchSource] = []
            if let rawURL = dictionary["url"] as? String,
               let url = WebSearchSource.sanitizedURLString(rawURL) {
                collected.append(
                    WebSearchSource(
                        type: firstSourceString(in: dictionary, keys: ["type", "source_type", "kind"]),
                        url: url,
                        title: firstSourceString(in: dictionary, keys: ["title", "name", "display_title"]),
                        publishedAt: firstSourceString(in: dictionary, keys: ["published_at", "publishedAt", "date", "published"]),
                        snippet: firstSourceString(in: dictionary, keys: ["snippet", "description", "summary", "text"])
                    )
                )
            }
            for key in ["sources", "results", "items", "documents", "citations"] {
                collected += webSearchSources(from: dictionary[key])
            }
            return collected
        }
        if let array = rawObject as? [Any] {
            return array.flatMap { webSearchSources(from: $0) }
        }
        return []
    }

    private static func firstSourceString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String,
               WebSearchSource.cleanedMetadata(value, maxLength: 600) != nil {
                return value
            }
        }
        return nil
    }

    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return "application/pdf"
        case "csv":
            return "text/csv"
        case "tsv":
            return "text/tab-separated-values"
        case "xlsx":
            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls":
            return "application/vnd.ms-excel"
        case "json":
            return "application/json"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        case "heic":
            return "image/heic"
        case "heif":
            return "image/heif"
        case "tif", "tiff":
            return "image/tiff"
        case "txt", "md", "log", "swift", "js", "ts", "tsx", "py", "html", "css":
            return "text/plain"
        default:
            return "application/octet-stream"
        }
    }

    static func uploadPurpose(filename: String, mimeType: String) -> String {
        ChatAttachment.isNativeVisionImage(filename: filename, mimeTypeOrKind: mimeType) ? "vision" : "user_data"
    }

    static func needsVisionTranscode(filename: String, mimeType: String) -> Bool {
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        if ["heic", "heif", "tif", "tiff"].contains(fileExtension) {
            return true
        }
        return ["image/heic", "image/heif", "image/tiff"].contains(mimeType.lowercased())
    }

    static func normalizedVisionFilename(filename: String, mimeType: String) -> String {
        guard needsVisionTranscode(filename: filename, mimeType: mimeType) else {
            return sanitizedMultipartFilename(filename)
        }
        let safeFilename = sanitizedMultipartFilename(filename)
        let base = (safeFilename as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\((base.isEmpty ? "image" : base)).jpg"
    }

    static func normalizedVisionUpload(data: Data, filename: String, mimeType: String) throws -> (data: Data, filename: String, mimeType: String) {
        guard needsVisionTranscode(filename: filename, mimeType: mimeType) else {
            return (data, sanitizedMultipartFilename(filename), mimeType)
        }
        #if canImport(UIKit)
        guard let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.92) else {
            throw APIError.status(415, "Could not convert this HEIC/TIFF image to JPEG.")
        }
        return (
            jpegData,
            normalizedVisionFilename(filename: filename, mimeType: mimeType),
            "image/jpeg"
        )
        #else
        throw APIError.status(415, "HEIC/TIFF images must be converted to JPEG before native vision upload.")
        #endif
    }

    private static func sanitizedMultipartFilename(_ filename: String) -> String {
        let cleaned = filename
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\\", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Attachment" : String(cleaned.prefix(160))
    }
}

private struct EmptyResponse: Decodable {}

private struct EmptyPayload: Encodable {}

private struct NearCloudConnectPayload: Encodable {}

private enum SharePermission: String {
    case read
    case write

    static func sanitized(_ value: String) -> SharePermission {
        value.lowercased() == SharePermission.write.rawValue ? .write : .read
    }
}

private struct CreateConversationSharePayload: Encodable {
    let permission: String
    let target: ShareTargetPayload
}

private struct ShareGroupPayload: Encodable {
    let name: String
    let members: [ShareInviteRecipient]
}

private enum ShareTargetPayload: Encodable {
    case `public`
    case direct([ShareInviteRecipient])
    case group(String)
    case organization(String)

    private enum CodingKeys: String, CodingKey {
        case mode
        case recipients
        case groupID = "group_id"
        case emailPattern = "email_pattern"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .public:
            try container.encode("public", forKey: .mode)
        case let .direct(recipients):
            try container.encode("direct", forKey: .mode)
            try container.encode(recipients, forKey: .recipients)
        case let .group(groupID):
            try container.encode("group", forKey: .mode)
            try container.encode(groupID, forKey: .groupID)
        case let .organization(emailPattern):
            try container.encode("organization", forKey: .mode)
            try container.encode(emailPattern, forKey: .emailPattern)
        }
    }
}

private struct ConversationCreatePayload: Encodable {
    let metadata: [String: String]
}

private struct ConversationItemsCreatePayload: Encodable {
    let items: [ConversationImportItem]
}

private struct LogoutPayload: Encodable {
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
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

private struct FileUploadResponse: Decodable {
    let id: String
    let bytes: Int
    let filename: String
    let purpose: String
}

private struct ResponsePayload: Encodable {
    let model: String
    let input: [ResponseInput]
    let conversation: String
    let stream: Bool
    let tools: [ResponseTool]?
    let include: [String]?
    let instructions: String?
    let signingAlgo: String
    let previousResponseID: String?
    let initiator: String?
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case conversation
        case stream
        case tools
        case include
        case instructions
        case signingAlgo = "signing_algo"
        case previousResponseID = "previous_response_id"
        case initiator
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
    }
}

private struct ResponseTool: Encodable {
    let type: String
}

private struct ResponseInput: Encodable {
    let role: String
    let content: [ResponseContent]
}

private struct ResponseContent: Encodable {
    let type: String
    let text: String?
    let fileID: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case fileID = "file_id"
    }
}

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

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        let safeName = Self.multipartQuotedString(name)
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(safeName)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartFile(
        name: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String
    ) {
        let safeName = Self.multipartQuotedString(name)
        let safeFilename = Self.multipartQuotedString(filename)
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(safeName)\"; filename=\"\(safeFilename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }

    private static func multipartQuotedString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }
}
