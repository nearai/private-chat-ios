import AuthenticationServices
import CryptoKit
import Foundation
import Security
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
final class SessionStore: NSObject, ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var profile: UserProfile?
    @Published var isAuthenticating = false
    @Published var bannerMessage: String?

    private let api: PrivateChatAPI
    private var webSession: ASWebAuthenticationSession?
    private let keychainAccount = "session"
    private let profileCacheAccount = "profile"
    private let simulatorFallbackKey = "debug.session"
    private let pendingAuthStateKey = "pendingAuthState"
    private let simulatorFallbackTTL: TimeInterval = 24 * 60 * 60
    private let pendingAuthTTL: TimeInterval = 10 * 60
    private var isRefreshingProfile = false

    var isSignedIn: Bool { session?.token.isEmpty == false }
    var displayName: String { profile?.user.name ?? profile?.user.email ?? "NEAR AI" }
    var setupAccountID: String? {
        UserSetupStorage.accountID(
            userID: profile?.id,
            sessionID: session?.sessionID,
            token: session?.token
        )
    }

    init(api: PrivateChatAPI) {
        self.api = api
        super.init()
        #if DEBUG
        if DemoCapture.isEnabled {
            configureDemoCaptureSession()
            return
        }
        #endif
        session = loadStoredSession()
        api.authToken = session?.token
        if session != nil {
            profile = loadCachedProfile()
        }
    }

    #if DEBUG
    func configureDemoCaptureSession() {
        let demoSession = AuthSession(
            token: "demo-capture-token",
            sessionID: "demo-capture-session",
            expiresAt: nil,
            isNewUser: false
        )
        session = demoSession
        api.authToken = demoSession.token
        profile = UserProfile(
            user: UserProfile.User(
                id: "demo.capture.near",
                email: "demo@near.ai",
                name: "Demo Account",
                avatarURL: nil
            ),
            linkedAccounts: [
                UserProfile.LinkedAccount(provider: "github", linkedAt: "2026-05-25T13:41:00Z")
            ]
        )
    }
    #endif

    func signIn(with provider: OAuthProvider) {
        Task { await authenticate(with: provider) }
    }

    func signInWithToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showBanner("Paste a session token first.")
            return
        }
        let newSession = AuthSession(token: trimmed, sessionID: "", expiresAt: nil, isNewUser: false)
        save(newSession)
        Task { await refreshProfile(force: true) }
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard url.scheme == api.configuration.callbackScheme,
              url.host?.lowercased() == api.configuration.callbackURL.host?.lowercased() else {
            return false
        }
        do {
            let pendingRequest = try requirePendingAuthRequest()
            let callback = try api.parseAuthCallback(url, expectedState: pendingRequest.state)
            clearPendingAuthState()
            Task {
                do {
                    let newSession = try await api.exchangeAuthCode(
                        provider: pendingRequest.provider,
                        callback: callback,
                        codeVerifier: pendingRequest.codeVerifier
                    )
                    save(newSession)
                    await refreshProfile(force: true)
                    showBanner(newSession.isNewUser ? "Account created." : "Signed in.")
                } catch {
                    showBanner(error.localizedDescription)
                }
            }
        } catch {
            clearPendingAuthState()
            showBanner(error.localizedDescription)
        }
        return true
    }

    func refreshProfile(force: Bool = true) async {
        guard isSignedIn else { return }
        if !force, profile != nil {
            return
        }
        #if targetEnvironment(simulator) && DEBUG
        // The simulator stub session has a fake bearer token. Skipping
        // the profile refresh prevents the API's 401 response from
        // bubbling up as an "Invalid or expired authentication token"
        // banner that pollutes visual QA. The stub profile is already
        // populated by `authenticate(with:)`.
        if session?.sessionID == "simulator-debug-session" {
            return
        }
        #endif
        guard !isRefreshingProfile else { return }
        isRefreshingProfile = true
        defer { isRefreshingProfile = false }

        do {
            let fetchedProfile = try await api.fetchProfile()
            profile = fetchedProfile
            saveCachedProfile(fetchedProfile)
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func scheduleProfileRefresh(force: Bool = false) {
        Task { await refreshProfile(force: force) }
    }

    func signOut() {
        Task {
            if let session {
                if session.sessionID.isEmpty {
                    showBanner("Signed out locally. No server session id was available to revoke.")
                } else {
                    do {
                        try await api.signOut(sessionID: session.sessionID)
                    } catch {
                        showBanner(error.localizedDescription)
                    }
                }
            }
            api.authToken = nil
            self.session = nil
            profile = nil
            clearPendingAuthState()
            KeychainStore.delete(account: keychainAccount)
            KeychainStore.delete(account: profileCacheAccount)
            deleteSimulatorFallbackSession()
        }
    }

    private func authenticate(with provider: OAuthProvider) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        #if targetEnvironment(simulator) && DEBUG
        // Simulator builds don't have a working OAuth callback flow — the
        // `nearprivatechat://` redirect from the NEAR auth backend can't
        // round-trip through ASWebAuthenticationSession in many test
        // environments. Short-circuit with a stub session so the rest of
        // the app is reachable for visual QA. This branch is compiled
        // out of release builds.
        let stubSession = AuthSession(
            token: "simulator-debug-token-\(provider.rawValue)",
            sessionID: "simulator-debug-session",
            expiresAt: nil,
            isNewUser: false
        )
        save(stubSession)
        profile = UserProfile(
            user: UserProfile.User(
                id: "simulator.\(provider.rawValue).near",
                email: "simulator@near.ai",
                name: "Simulator User",
                avatarURL: nil
            ),
            linkedAccounts: [
                UserProfile.LinkedAccount(provider: provider.rawValue, linkedAt: "2026-05-27T00:00:00Z")
            ]
        )
        showBanner("Signed in (simulator stub).")
        return
        #else
        do {
            let pendingRequest = createPendingAuthRequest(provider: provider)
            let url = try api.authURL(
                for: provider,
                state: pendingRequest.state,
                codeChallenge: pendingRequest.codeChallenge
            )
            let callbackURL = try await startWebAuthentication(url: url)
            let callback = try api.parseAuthCallback(callbackURL, expectedState: pendingRequest.state)
            let newSession = try await api.exchangeAuthCode(
                provider: provider,
                callback: callback,
                codeVerifier: pendingRequest.codeVerifier
            )
            clearPendingAuthState()
            save(newSession)
            await refreshProfile(force: true)
            showBanner(newSession.isNewUser ? "Account created." : "Signed in.")
        } catch {
            clearPendingAuthState()
            showBanner(error.localizedDescription)
        }
        #endif
    }

    private func createPendingAuthRequest(provider: OAuthProvider) -> PendingAuthRequest {
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let codeVerifier = Self.makePKCECodeVerifier()
        let envelope = PendingAuthRequest(
            state: state,
            providerRawValue: provider.rawValue,
            codeVerifier: codeVerifier,
            expiresAt: Date().addingTimeInterval(pendingAuthTTL)
        )
        if let data = try? JSONEncoder().encode(envelope) {
            UserDefaults.standard.set(data, forKey: pendingAuthStateKey)
        }
        return envelope
    }

    private func requirePendingAuthRequest() throws -> PendingAuthRequest {
        guard let data = UserDefaults.standard.data(forKey: pendingAuthStateKey),
              let envelope = try? JSONDecoder().decode(PendingAuthRequest.self, from: data),
              !envelope.state.isEmpty else {
            throw APIError.status(401, "No sign-in request is waiting for this callback.")
        }
        guard envelope.expiresAt > Date() else {
            clearPendingAuthState()
            throw APIError.status(401, "The sign-in callback expired. Try signing in again.")
        }
        return envelope
    }

    private func clearPendingAuthState() {
        UserDefaults.standard.removeObject(forKey: pendingAuthStateKey)
    }

    nonisolated private static func makePKCECodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        return base64URLEncoded(Data(bytes))
    }

    nonisolated fileprivate static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncoded(Data(digest))
    }

    nonisolated private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func save(_ newSession: AuthSession) {
        let sessionChanged = session?.token != newSession.token || session?.sessionID != newSession.sessionID
        session = newSession
        api.authToken = newSession.token
        if sessionChanged {
            profile = nil
            KeychainStore.delete(account: profileCacheAccount)
        }

        do {
            try KeychainStore.save(newSession, account: keychainAccount)
            _ = saveSimulatorFallbackSession(newSession)
        } catch {
            if saveSimulatorFallbackSession(newSession) {
                showBanner("Signed in. Simulator fallback storage is active.")
            } else {
                showBanner("Signed in for this launch. Keychain storage is unavailable in this build.")
            }
        }
    }

    private func loadCachedProfile() -> UserProfile? {
        (try? KeychainStore.read(UserProfile.self, account: profileCacheAccount)) ?? nil
    }

    private func saveCachedProfile(_ profile: UserProfile) {
        try? KeychainStore.save(profile, account: profileCacheAccount)
    }

    private func loadStoredSession() -> AuthSession? {
        #if targetEnvironment(simulator)
        if let fallbackSession = loadSimulatorFallbackSession() {
            try? KeychainStore.save(fallbackSession, account: keychainAccount)
            return fallbackSession
        }
        #endif

        do {
            return try KeychainStore.read(AuthSession.self, account: keychainAccount)
        } catch {
            return loadSimulatorFallbackSession()
        }
    }

    private func loadSimulatorFallbackSession() -> AuthSession? {
        #if targetEnvironment(simulator)
        guard let data = UserDefaults.standard.data(forKey: simulatorFallbackKey) else {
            return nil
        }
        if let envelope = try? JSONDecoder().decode(SimulatorFallbackSessionEnvelope.self, from: data) {
            guard envelope.expiresAt > Date() else {
                deleteSimulatorFallbackSession()
                return nil
            }
            return envelope.session
        }
        deleteSimulatorFallbackSession()
        return nil
        #else
        return nil
        #endif
    }

    private func saveSimulatorFallbackSession(_ session: AuthSession) -> Bool {
        #if targetEnvironment(simulator)
        let envelope = SimulatorFallbackSessionEnvelope(
            session: session,
            expiresAt: Date().addingTimeInterval(simulatorFallbackTTL)
        )
        guard let data = try? JSONEncoder().encode(envelope) else {
            return false
        }
        UserDefaults.standard.set(data, forKey: simulatorFallbackKey)
        return true
        #else
        return false
        #endif
    }

    private func deleteSimulatorFallbackSession() {
        #if targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: simulatorFallbackKey)
        #endif
    }

    private func startWebAuthentication(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: api.configuration.callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? APIError.invalidCallback)
                }
            }
            authSession.presentationContextProvider = self
            authSession.prefersEphemeralWebBrowserSession = false
            webSession = authSession
            if !authSession.start() {
                continuation.resume(throwing: APIError.status(0, "Unable to start browser sign-in."))
            }
        }
    }

    private func showBanner(_ message: String) {
        bannerMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if bannerMessage == message {
                bannerMessage = nil
            }
        }
    }

}

private struct PendingAuthRequest: Codable {
    var state: String
    var providerRawValue: String
    var codeVerifier: String
    var expiresAt: Date

    var provider: OAuthProvider {
        OAuthProvider(rawValue: providerRawValue) ?? .google
    }

    var codeChallenge: String {
        SessionStore.codeChallenge(for: codeVerifier)
    }
}

private struct SimulatorFallbackSessionEnvelope: Codable {
    var session: AuthSession
    var expiresAt: Date
}


extension SessionStore: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
        #elseif canImport(AppKit)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
