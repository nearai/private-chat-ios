import Foundation

protocol AuthAPI: AnyObject {
    var configuration: AppConfiguration { get set }
    var authToken: String? { get set }

    func authURL(for provider: OAuthProvider, state: String?, codeChallenge: String?) throws -> URL
    func parseAuthCallback(_ url: URL, expectedState: String?) throws -> AuthCodeCallback
    func exchangeAuthCode(provider: OAuthProvider, callback: AuthCodeCallback, codeVerifier: String) async throws -> AuthSession
    func fetchProfile() async throws -> UserProfile
    func signOut(sessionID: String) async throws
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
}

private struct LogoutPayload: Encodable {
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}
