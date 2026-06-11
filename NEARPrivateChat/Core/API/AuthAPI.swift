import Foundation

protocol AuthAPI: AnyObject {
    var configuration: AppConfiguration { get set }
    var authToken: String? { get set }

    func authURL(for provider: OAuthProvider, state: String?, codeChallenge: String?) throws -> URL
    func parseAuthCallback(_ url: URL, expectedState: String?) throws -> AuthCallbackResult
    func exchangeAuthCode(provider: OAuthProvider, callback: AuthCodeCallback, codeVerifier: String) async throws -> AuthSession
    func fetchProfile() async throws -> UserProfile
    func signOut(sessionID: String) async throws
    func signInWithNear(signedMessage: NEP413SignedMessage, payload: NEP413Payload) async throws -> AuthSession
}

final class PrivateChatAuthAPI: AuthAPI {
    private let client: APIClient

    var configuration: AppConfiguration {
        get { client.configuration }
        set { client.configuration = newValue }
    }

    var authToken: String? {
        get { client.authToken }
        set { client.authToken = newValue }
    }

    init(client: APIClient) {
        self.client = client
    }

    func authURL(for provider: OAuthProvider, state: String? = nil, codeChallenge: String? = nil) throws -> URL {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        switch provider {
        case .near:
            components?.path = "/near-login"
        case .google:
            components?.path = "/v1/auth/google"
        case .github:
            components?.path = "/v1/auth/github"
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
    ) throws -> AuthCallbackResult {
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
        if let token = Self.authToken(from: values) {
            return .session(
                AuthSession(
                    token: token,
                    sessionID: Self.sessionID(from: values) ?? "",
                    expiresAt: nil,
                    isNewUser: Self.boolValue(from: values, names: ["is_new_user", "isNewUser"]) ?? false
                )
            )
        }
        guard let code = Self.firstNonEmptyValue(named: "code", in: values) else {
            throw APIError.invalidCallback
        }
        return .authorizationCode(
            AuthCodeCallback(
                code: code,
                state: expectedState,
                providerState: callbackStates.first { $0 != expectedState }
            )
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
            let response: AuthCodeExchangeResponse = try await client.request(
                "/v1/auth/\(provider.rawValue)/exchange",
                method: "POST",
                body: payload,
                authenticated: false
            )
            return response.session
        } catch APIError.status(let code, _) where code == 404 || code == 405 {
            let response: AuthCodeExchangeResponse = try await client.request(
                "/v1/auth/exchange",
                method: "POST",
                body: payload,
                authenticated: false
            )
            return response.session
        }
    }

    func fetchProfile() async throws -> UserProfile {
        try await client.request("/v1/users/me", method: "GET", authenticated: true)
    }

    /// Native NEAR sign-in: POSTs a NEP-413 signed message to `/v1/auth/near`
    /// (the same endpoint the web wallet flow uses) and returns the issued
    /// session. The server verifies the signature and that the public key is a
    /// key on `accountId` before issuing a token.
    func signInWithNear(signedMessage: NEP413SignedMessage, payload: NEP413Payload) async throws -> AuthSession {
        let body = NearAuthRequest(
            signedMessage: signedMessage,
            payload: NearAuthRequest.Payload(
                message: payload.message,
                nonce: payload.nonce.map { Int($0) },
                recipient: payload.recipient
            )
        )
        let response: NearAuthResponse = try await client.request(
            "/v1/auth/near",
            method: "POST",
            body: body,
            authenticated: false
        )
        return AuthSession(
            token: response.token,
            sessionID: response.sessionID ?? "",
            expiresAt: nil,
            isNewUser: response.isNewUser ?? false
        )
    }

    func signOut(sessionID: String) async throws {
        guard !sessionID.isEmpty else { return }
        let payload = LogoutPayload(sessionID: sessionID)
        let _: EmptyResponse = try await client.request("/v1/auth/logout", method: "POST", body: payload, authenticated: true)
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
           let fragmentComponents = URLComponents(string: "nearai://auth?\(fragment)") {
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
        for name in ["session_id", "sessionID", "sessionId"] {
            if let sessionID = firstNonEmptyValue(named: name, in: values) {
                return sessionID
            }
        }
        return nil
    }

    private static func boolValue(from values: [String: [String]], names: [String]) -> Bool? {
        for name in names {
            guard let rawValue = firstNonEmptyValue(named: name, in: values)?.lowercased() else {
                continue
            }
            switch rawValue {
            case "1", "true", "yes":
                return true
            case "0", "false", "no":
                return false
            default:
                continue
            }
        }
        return nil
    }
}

private struct LogoutPayload: Encodable {
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}

/// Wire body for `POST /v1/auth/near`, mirroring the production web client:
/// `{signed_message: {accountId, publicKey, signature}, payload: {message,
/// nonce: [u8], recipient}}`.
private struct NearAuthRequest: Encodable {
    struct Payload: Encodable {
        let message: String
        let nonce: [Int]
        let recipient: String
    }
    let signedMessage: NEP413SignedMessage
    let payload: Payload

    enum CodingKeys: String, CodingKey {
        case signedMessage = "signed_message"
        case payload
    }
}

private struct NearAuthResponse: Decodable {
    let token: String
    let sessionID: String?
    let isNewUser: Bool?

    enum CodingKeys: String, CodingKey {
        case token
        case sessionID = "session_id"
        case isNewUser = "is_new_user"
    }
}
