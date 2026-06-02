import Foundation

struct SessionPersistence {
    enum SessionSaveOutcome: Equatable {
        case persisted
        case simulatorFallbackOnly
        case volatileOnly
    }

    static let sessionKeychainAccount = "session"
    static let profileKeychainAccount = "profile"
    static let simulatorFallbackKey = "debug.session"
    static let pendingAuthStateKey = "pendingAuthState"
    static let simulatorFallbackTTL: TimeInterval = 24 * 60 * 60
    static let pendingAuthTTL: TimeInterval = 10 * 60

    var defaults: UserDefaults = .standard

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadStoredSession() -> AuthSession? {
        #if targetEnvironment(simulator)
        if let fallbackSession = loadSimulatorFallbackSession() {
            try? KeychainStore.save(fallbackSession, account: Self.sessionKeychainAccount)
            return fallbackSession
        }
        #endif

        do {
            return try KeychainStore.read(AuthSession.self, account: Self.sessionKeychainAccount)
        } catch {
            return loadSimulatorFallbackSession()
        }
    }

    func saveSession(_ session: AuthSession) -> SessionSaveOutcome {
        do {
            try KeychainStore.save(session, account: Self.sessionKeychainAccount)
            _ = saveSimulatorFallbackSession(session)
            return .persisted
        } catch {
            return saveSimulatorFallbackSession(session) ? .simulatorFallbackOnly : .volatileOnly
        }
    }

    func deleteStoredSession() {
        KeychainStore.delete(account: Self.sessionKeychainAccount)
    }

    func loadCachedProfile() -> UserProfile? {
        (try? KeychainStore.read(UserProfile.self, account: Self.profileKeychainAccount)) ?? nil
    }

    func saveCachedProfile(_ profile: UserProfile) {
        try? KeychainStore.save(profile, account: Self.profileKeychainAccount)
    }

    func deleteCachedProfile() {
        KeychainStore.delete(account: Self.profileKeychainAccount)
    }

    func createPendingAuthRequest(provider: OAuthProvider, state: String, codeVerifier: String) -> PendingAuthRequest {
        let request = PendingAuthRequest(
            state: state,
            providerRawValue: provider.rawValue,
            codeVerifier: codeVerifier,
            expiresAt: Date().addingTimeInterval(Self.pendingAuthTTL)
        )
        savePendingAuthRequest(request)
        return request
    }

    func requirePendingAuthRequest() throws -> PendingAuthRequest {
        guard let data = defaults.data(forKey: Self.pendingAuthStateKey),
              let request = try? JSONDecoder().decode(PendingAuthRequest.self, from: data),
              !request.state.isEmpty else {
            throw APIError.status(401, "No sign-in request is waiting for this callback.")
        }
        guard request.expiresAt > Date() else {
            clearPendingAuthState()
            throw APIError.status(401, "The sign-in callback expired. Try signing in again.")
        }
        return request
    }

    func clearPendingAuthState() {
        defaults.removeObject(forKey: Self.pendingAuthStateKey)
    }

    @discardableResult
    func saveSimulatorFallbackSession(_ session: AuthSession) -> Bool {
        #if targetEnvironment(simulator)
        let envelope = SimulatorFallbackSessionEnvelope(
            session: session,
            expiresAt: Date().addingTimeInterval(Self.simulatorFallbackTTL)
        )
        guard let data = try? JSONEncoder().encode(envelope) else {
            return false
        }
        defaults.set(data, forKey: Self.simulatorFallbackKey)
        return true
        #else
        return false
        #endif
    }

    func loadSimulatorFallbackSession() -> AuthSession? {
        #if targetEnvironment(simulator)
        guard let data = defaults.data(forKey: Self.simulatorFallbackKey) else {
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

    func deleteSimulatorFallbackSession() {
        #if targetEnvironment(simulator)
        defaults.removeObject(forKey: Self.simulatorFallbackKey)
        #endif
    }

    private func savePendingAuthRequest(_ request: PendingAuthRequest) {
        if let data = try? JSONEncoder().encode(request) {
            defaults.set(data, forKey: Self.pendingAuthStateKey)
        }
    }
}

struct PendingAuthRequest: Codable, Equatable {
    var state: String
    var providerRawValue: String
    var codeVerifier: String
    var expiresAt: Date

    var provider: OAuthProvider {
        OAuthProvider(rawValue: providerRawValue) ?? .google
    }
}

struct SimulatorFallbackSessionEnvelope: Codable, Equatable {
    var session: AuthSession
    var expiresAt: Date
}
