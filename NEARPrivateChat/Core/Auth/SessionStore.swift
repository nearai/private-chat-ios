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

    private let api: AuthAPI
    private let persistence: SessionPersistence
    private var webSession: ASWebAuthenticationSession?
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

    init(api: AuthAPI, persistence: SessionPersistence = SessionPersistence()) {
        self.api = api
        self.persistence = persistence
        super.init()
        #if DEBUG
        if DemoCapture.isEnabled {
            configureDemoCaptureSession()
            return
        }
        // A debug token (env-injected, never persisted) signs into the REAL app
        // for interactive testing — full Home/Chat, no demo screens. Only active
        // when launched with NEAR_DEBUG_SESSION_TOKEN; a normal run is unaffected.
        if DebugBackend.isEnabled {
            configureDemoCaptureSession()
            return
        }
        #endif
        session = persistence.loadStoredSession()
        api.authToken = session?.token
        if session != nil {
            profile = persistence.loadCachedProfile()
        }
    }

    #if DEBUG
    func configureDemoCaptureSession() {
        // A real session token (env-injected, never persisted) lets the *Live
        // demo screens exercise the actual backend; otherwise a fake token keeps
        // the harness fully offline.
        let liveToken = DebugBackend.sessionToken
        let demoSession = AuthSession(
            token: liveToken ?? "demo-capture-token",
            sessionID: liveToken != nil ? "live-debug-session" : "demo-capture-session",
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

    /// The device public key the user must authorize on their NEAR account
    /// (Full Access) before native sign-in can succeed.
    var nearDevicePublicKey: String {
        NearKeyStore.publicKeyString(for: NearKeyStore.loadOrCreateKey())
    }

    func signInWithNearAccount(_ accountID: String) {
        Task { await authenticateWithNearAccount(accountID) }
    }

    /// Native NEAR sign-in: signs the standard challenge with the device key and
    /// exchanges it at `/v1/auth/near`. Requires the device public key to be an
    /// access key on `accountID` (see `nearDevicePublicKey`).
    private func authenticateWithNearAccount(_ accountID: String) async {
        let trimmed = accountID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            showBanner("Enter your NEAR account ID, e.g. yourname.near.")
            return
        }
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let key = NearKeyStore.loadOrCreateKey()
        // Mirror the production web flow: fixed challenge message, locally
        // generated 32-byte nonce, recipient = the private.near.ai host.
        let payload = NEP413Payload(
            message: "Sign in to NEAR AI",
            nonce: NEP413Signer.timestampNonce(),
            recipient: "private.near.ai",
            callbackUrl: nil
        )
        let signed = NEP413Signer.sign(payload: payload, accountId: trimmed, privateKey: key)
        do {
            let session = try await api.signInWithNear(signedMessage: signed, payload: payload)
            adoptSession(token: session.token, sessionID: session.sessionID, isNewUser: session.isNewUser)
            showBanner(session.isNewUser ? "Account created." : "Signed in.")
        } catch {
            showBanner(Self.userFacingAuthenticationError(error))
        }
    }

    func signInWithToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showBanner("Paste a session token first.")
            return
        }
        adoptSession(token: trimmed, sessionID: "", isNewUser: false)
    }

    /// Adopts a session obtained outside the OAuth redirect flow — the in-app
    /// web-login harvest (WebSignInView) and native NEAR wallet signing both
    /// land here with the real `{token, session_id}` the backend issued. Unlike
    /// `signInWithToken`, this keeps the session_id so sign-out can revoke it
    /// server-side.
    func adoptSession(token: String, sessionID: String, isNewUser: Bool) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            showBanner("That sign-in didn't return a session token.")
            return
        }
        let newSession = AuthSession(
            token: trimmedToken,
            sessionID: sessionID.trimmingCharacters(in: .whitespacesAndNewlines),
            expiresAt: nil,
            isNewUser: isNewUser
        )
        save(newSession)
        Task { await refreshProfile(force: true) }
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard api.configuration.isAuthCallback(url) else {
            return false
        }
        do {
            let pendingRequest = try requirePendingAuthRequest()
            let callback = try api.parseAuthCallback(url, expectedState: pendingRequest.state)
            clearPendingAuthState()
            Task {
                do {
                    let newSession = try await completeAuthentication(
                        provider: pendingRequest.provider,
                        callback: callback,
                        codeVerifier: pendingRequest.codeVerifier
                    )
                    save(newSession)
                    await refreshProfile(force: true)
                    showBanner(newSession.isNewUser ? "Account created." : "Signed in.")
                } catch {
                    showBanner(Self.userFacingAuthenticationError(error))
                }
            }
        } catch {
            clearPendingAuthState()
            showBanner(Self.userFacingAuthenticationError(error))
        }
        return true
    }

    func refreshProfile(force: Bool = true) async {
        guard isSignedIn else { return }
        if !force, profile != nil {
            return
        }
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
                    showBanner("Signed out on this device. No server session to revoke.")
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
            persistence.deleteStoredSession()
            persistence.deleteCachedProfile()
            persistence.deleteSimulatorFallbackSession()
        }
    }

    private func authenticate(with provider: OAuthProvider) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let pendingRequest = createPendingAuthRequest(provider: provider)
            let url = try api.authURL(
                for: provider,
                state: pendingRequest.state,
                codeChallenge: Self.codeChallenge(for: pendingRequest.codeVerifier)
            )
            let callbackURL = try await startWebAuthentication(url: url)
            let callback = try api.parseAuthCallback(callbackURL, expectedState: pendingRequest.state)
            let newSession = try await completeAuthentication(
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
            showBanner(Self.userFacingAuthenticationError(error))
        }
    }

    private func completeAuthentication(
        provider: OAuthProvider,
        callback: AuthCallbackResult,
        codeVerifier: String
    ) async throws -> AuthSession {
        switch callback {
        case .authorizationCode(let codeCallback):
            return try await api.exchangeAuthCode(
                provider: provider,
                callback: codeCallback,
                codeVerifier: codeVerifier
            )
        case .session(let session):
            guard !session.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw APIError.invalidCallback
            }
            return session
        }
    }

    private func createPendingAuthRequest(provider: OAuthProvider) -> PendingAuthRequest {
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let codeVerifier = Self.makePKCECodeVerifier()
        return persistence.createPendingAuthRequest(
            provider: provider,
            state: state,
            codeVerifier: codeVerifier
        )
    }

    private func requirePendingAuthRequest() throws -> PendingAuthRequest {
        try persistence.requirePendingAuthRequest()
    }

    private func clearPendingAuthState() {
        persistence.clearPendingAuthState()
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
            persistence.deleteCachedProfile()
        }

        switch persistence.saveSession(newSession) {
        case .persisted:
            break
        case .simulatorFallbackOnly:
            showBanner("Signed in. Simulator fallback storage is active.")
        case .volatileOnly:
            showBanner("Signed in for this launch. Keychain storage is unavailable in this build.")
        }
    }

    private func saveCachedProfile(_ profile: UserProfile) {
        persistence.saveCachedProfile(profile)
    }

    private static func userFacingAuthenticationError(_ error: Error) -> String {
        if let authenticationError = error as? ASWebAuthenticationSessionError,
           authenticationError.code == .canceledLogin {
            return "Sign-in canceled."
        }

        let nsError = error as NSError
        if nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession",
           nsError.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue {
            return "Sign-in canceled."
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Sign-in failed. Try again." : message
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
