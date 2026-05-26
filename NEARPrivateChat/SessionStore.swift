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
    private let simulatorFallbackKey = "debug.session"
    private let pendingAuthStateKey = "pendingAuthState"
    private let simulatorFallbackTTL: TimeInterval = 24 * 60 * 60
    private let pendingAuthTTL: TimeInterval = 10 * 60

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
        Task { await refreshProfile() }
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard url.scheme == api.configuration.callbackScheme,
              url.host?.lowercased() == api.configuration.callbackURL.host?.lowercased() else {
            return false
        }
        do {
            let expectedState = try requirePendingAuthState()
            let newSession = try api.parseAuthCallback(url, expectedState: expectedState)
            clearPendingAuthState()
            save(newSession)
            Task {
                await refreshProfile()
                showBanner(newSession.isNewUser ? "Account created." : "Signed in.")
            }
        } catch {
            clearPendingAuthState()
            showBanner(error.localizedDescription)
        }
        return true
    }

    func refreshProfile() async {
        guard isSignedIn else { return }
        do {
            profile = try await api.fetchProfile()
        } catch {
            showBanner(error.localizedDescription)
        }
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
            deleteSimulatorFallbackSession()
        }
    }

    private func authenticate(with provider: OAuthProvider) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let pendingRequest = createPendingAuthRequest()
            let url = try api.authURL(
                for: provider,
                state: pendingRequest.state,
                codeChallenge: pendingRequest.codeChallenge
            )
            let callbackURL = try await startWebAuthentication(url: url)
            let newSession = try api.parseAuthCallback(
                callbackURL,
                expectedState: pendingRequest.state,
                allowProviderManagedState: true
            )
            clearPendingAuthState()
            save(newSession)
            await refreshProfile()
            showBanner(newSession.isNewUser ? "Account created." : "Signed in.")
        } catch {
            clearPendingAuthState()
            showBanner(error.localizedDescription)
        }
    }

    private func createPendingAuthRequest() -> PendingAuthRequest {
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let codeVerifier = Self.makePKCECodeVerifier()
        let envelope = PendingAuthRequest(
            state: state,
            codeVerifier: codeVerifier,
            expiresAt: Date().addingTimeInterval(pendingAuthTTL)
        )
        if let data = try? JSONEncoder().encode(envelope) {
            UserDefaults.standard.set(data, forKey: pendingAuthStateKey)
        }
        return envelope
    }

    private func requirePendingAuthState() throws -> String {
        guard let data = UserDefaults.standard.data(forKey: pendingAuthStateKey),
              let envelope = try? JSONDecoder().decode(PendingAuthRequest.self, from: data),
              !envelope.state.isEmpty else {
            throw APIError.status(401, "No sign-in request is waiting for this callback.")
        }
        guard envelope.expiresAt > Date() else {
            clearPendingAuthState()
            throw APIError.status(401, "The sign-in callback expired. Try signing in again.")
        }
        return envelope.state
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
        session = newSession
        api.authToken = newSession.token

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
    var codeVerifier: String
    var expiresAt: Date

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
