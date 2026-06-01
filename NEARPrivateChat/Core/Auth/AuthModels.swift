import Foundation
import SwiftUI

enum OAuthProvider: String, CaseIterable, Identifiable {
    case near
    case google
    case github

    var id: String { rawValue }

    var title: String {
        switch self {
        case .near: "Continue with NEAR"
        case .google: "Continue with Google"
        case .github: "Continue with GitHub"
        }
    }

    var symbolName: String {
        switch self {
        case .near: "hexagon"
        case .google: "g.circle"
        case .github: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct AuthSession: Codable, Equatable {
    var token: String
    var sessionID: String
    var expiresAt: String?
    var isNewUser: Bool

    enum CodingKeys: String, CodingKey {
        case token
        case sessionToken = "session_token"
        case authToken = "auth_token"
        case accessToken = "access_token"
        case sessionID
        case sessionIDSnake = "session_id"
        case sessionId
        case expiresAt
        case expiresAtSnake = "expires_at"
        case isNewUser
        case isNewUserSnake = "is_new_user"
    }

    init(token: String, sessionID: String, expiresAt: String?, isNewUser: Bool) {
        self.token = token
        self.sessionID = sessionID
        self.expiresAt = expiresAt
        self.isNewUser = isNewUser
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decodeIfPresent(String.self, forKey: .token) ??
            container.decodeIfPresent(String.self, forKey: .sessionToken) ??
            container.decodeIfPresent(String.self, forKey: .authToken) ??
            container.decodeIfPresent(String.self, forKey: .accessToken) ??
            ""
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ??
            container.decodeIfPresent(String.self, forKey: .sessionIDSnake) ??
            container.decodeIfPresent(String.self, forKey: .sessionId) ??
            ""
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt) ??
            container.decodeIfPresent(String.self, forKey: .expiresAtSnake)
        isNewUser = try container.decodeIfPresent(Bool.self, forKey: .isNewUser) ??
            container.decodeIfPresent(Bool.self, forKey: .isNewUserSnake) ??
            false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encode(isNewUser, forKey: .isNewUser)
    }
}

struct AuthCodeCallback: Equatable {
    var code: String
    var state: String
    var providerState: String?
}

struct AuthCodeExchangePayload: Encodable {
    var provider: String
    var code: String
    var codeVerifier: String
    var redirectURI: String
    var state: String

    enum CodingKeys: String, CodingKey {
        case provider
        case code
        case codeVerifier = "code_verifier"
        case redirectURI = "redirect_uri"
        case state
    }
}

struct AuthCodeExchangeResponse: Decodable {
    var session: AuthSession

    enum CodingKeys: String, CodingKey {
        case session
        case authSession = "auth_session"
    }

    init(from decoder: Decoder) throws {
        if let session = try? AuthSession(from: decoder), !session.token.isEmpty {
            self.session = session
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let session = try container.decodeIfPresent(AuthSession.self, forKey: .session) ??
            container.decodeIfPresent(AuthSession.self, forKey: .authSession) {
            self.session = session
            return
        }
        throw DecodingError.keyNotFound(
            CodingKeys.session,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Auth code exchange did not return a session.")
        )
    }
}

struct NearCloudConnectResponse: Decodable, Hashable {
    var apiKey: String?
    var models: [ModelOption]
    var connectURL: URL?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case apiKey
        case api_key
        case nearCloudAPIKey
        case near_cloud_api_key
        case models
        case connectURL
        case connect_url
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ??
            container.decodeIfPresent(String.self, forKey: .api_key) ??
            container.decodeIfPresent(String.self, forKey: .nearCloudAPIKey) ??
            container.decodeIfPresent(String.self, forKey: .near_cloud_api_key)
        models = try container.decodeIfPresent([ModelOption].self, forKey: .models) ?? []
        connectURL = try container.decodeIfPresent(URL.self, forKey: .connectURL) ??
            container.decodeIfPresent(URL.self, forKey: .connect_url)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

struct LegalTermsSection: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let body: String
}

enum LegalTerms {
    static let version = "2026-05-25"
    static let effectiveDate = "May 25, 2026"
    static let appTermsDocumentName = "TERMS_AND_CONDITIONS.md"
    static let nearAIServicesTermsURL = URL(string: "https://near.ai/terms-of-service")!
    static let nearAICloudTermsURL = URL(string: "https://near.ai/near-ai-cloud-terms-of-service")!
    static let nearAIAcceptableUseURL = URL(string: "https://near.ai/acceptable-use-policy")!
    static let nearAIPrivacyPolicyURL = URL(string: "https://near.ai/privacy-policy")!
    static let ironclawRepositoryURL = URL(string: "https://github.com/nearai/ironclaw")!

    static let acceptanceText = "I am 18 or older. I agree to the NEAR Private Chat iOS Terms, NEAR AI Services Terms, NEAR AI Cloud Terms, Acceptable Use Policy, and applicable IronClaw or third-party terms. I understand that networked models, web search, files, and Agents can send selected content off this device."
    static let acceptancePrompt = "Review the terms, then accept to continue."
    static let acceptanceCheckboxText = "I reviewed version \(version) and accept the terms for this app and its connected NEAR AI routes."

    static let signupSummary = [
        "Required before you get account access.",
        "Applies to private chat, NEAR AI Cloud, LLM Council, files, sharing, web, and IronClaw.",
        "Cloud premium models use a privacy proxy and do not carry NEAR Private proof.",
        "Proof shows where a request ran. It can't confirm the answer is true.",
        "Agent actions and connected keys remain your responsibility."
    ]

    static let sections: [LegalTermsSection] = [
        LegalTermsSection(
            title: "Acceptance",
            body: "You must accept these Terms before signing in or using the App. If you use the App for an organization, you represent that you are authorized to bind that organization. The App stores the accepted Terms version and acceptance time locally, and it may require renewed acceptance after material updates."
        ),
        LegalTermsSection(
            title: "Connected Terms",
            body: "The App may connect to NEAR AI Services, NEAR AI Cloud, and IronClaw. Your use is also subject to the current NEAR AI Services Terms, NEAR AI Cloud Terms, NEAR AI Acceptable Use Policy, NEAR AI Privacy Policy, IronClaw licenses, App Store terms, and applicable third-party model/provider terms. Upstream terms control for the upstream service they govern."
        ),
        LegalTermsSection(
            title: "Age, Eligibility, and Account Security",
            body: "You must be at least 18 and legally permitted to use the App and connected services. You are responsible for your account, device, API keys, session tokens, SSH keys, repositories, Agent connections, backups, and recovery methods."
        ),
        LegalTermsSection(
            title: "Privacy, Cloud, and Proof",
            body: "Private routes may provide proof metadata when supported by the service. NEAR AI Cloud routes can include open-weight and premium closed-source models; premium routes may be anonymously proxied to third-party providers and may not have TEE attestation in the App. Attestation is cryptographic evidence about where a request was served, not a guarantee that an answer is accurate, safe, lawful, complete, or suitable."
        ),
        LegalTermsSection(
            title: "Files, Search, and Context",
            body: "Prompts, files, extracted text, saved links, project instructions, memory, source packs, imports, and web queries may leave your device when you enable or use networked routes. Search results, links, snippets, and imported content are untrusted and may be inaccurate, malicious, copyrighted, private, or prompt-injection material."
        ),
        LegalTermsSection(
            title: "Agent Capabilities",
            body: "IronClaw Mobile and Hosted IronClaw can inspect or modify files, interact with repositories, run commands and tests, call tools, browse, use configured credentials, or operate through a Hosted IronClaw connection. You are responsible for every instruction, approval, connected permission, credential, repository, connection, and resulting action."
        ),
        LegalTermsSection(
            title: "Acceptable Use",
            body: "You may not use the App for illegal, harmful, infringing, abusive, deceptive, unsafe, sanctioned, privacy-invasive, credential-theft, malware, unauthorized-access, spam, harassment, or high-risk activity without required legal basis, approvals, safeguards, and human oversight. You must comply with the NEAR AI Acceptable Use Policy and all applicable laws."
        ),
        LegalTermsSection(
            title: "Outputs and Professional Advice",
            body: "AI outputs can be wrong, incomplete, outdated, biased, unsafe, or unsuitable. You are responsible for reviewing and validating outputs before relying on them, publishing them, or using them in consequential contexts. The App does not provide legal, medical, financial, tax, investment, safety-critical, or other professional advice."
        ),
        LegalTermsSection(
            title: "Billing, Sharing, and Exports",
            body: "Some routes require API keys, usage credits, subscriptions, or rate limits. You are responsible for usage caused by your account, keys, agents, and connected users. Shared links, write grants, imports, exports, signed transcripts, file previews, pasteboard actions, and screenshots can expose private data; confirm recipients and contents before sharing."
        ),
        LegalTermsSection(
            title: "Dispute Defaults",
            body: "The App terms draft follows the NEAR AI Services Terms default structure: Delaware law, informal dispute resolution before formal proceedings, individual arbitration in Wilmington or by video where applicable, class action and jury trial waivers where permitted, and local consumer-law carveouts for EEA, UK, and Swiss consumers. Upstream provider terms control disputes with those providers."
        ),
        LegalTermsSection(
            title: "Disclaimer",
            body: "The App and experimental features are provided as is and as available to the fullest extent permitted by law. Features may fail, change, stall, be unavailable, or produce unintended outputs or actions. The distributing entity is NEAR AI, Inc.; support and legal notices may be sent to legal@near.ai."
        )
    ]
}

enum LegalTermsAcceptanceStore {
    private static let pendingVersionKey = "legalTerms.pending.version"
    private static let pendingAcceptedAtKey = "legalTerms.pending.acceptedAt"
    private static let scopedVersionPrefix = "legalTerms.accepted.version"
    private static let scopedAcceptedAtPrefix = "legalTerms.accepted.at"

    static func hasPendingCurrentVersion(defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: pendingVersionKey) == LegalTerms.version
    }

    static func recordPendingAcceptance(defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(LegalTerms.version, forKey: pendingVersionKey)
        defaults.set(ISO8601DateFormatter().string(from: now), forKey: pendingAcceptedAtKey)
        NotificationCenter.default.post(name: .legalTermsAcceptanceDidChange, object: nil)
    }

    static func clearPendingAcceptance(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingVersionKey)
        defaults.removeObject(forKey: pendingAcceptedAtKey)
        NotificationCenter.default.post(name: .legalTermsAcceptanceDidChange, object: nil)
    }

    static func hasAcceptedCurrentVersion(for accountID: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: scopedVersionKey(for: accountID)) == LegalTerms.version
    }

    @discardableResult
    static func consumePendingAcceptance(for accountID: String, defaults: UserDefaults = .standard) -> Bool {
        guard hasPendingCurrentVersion(defaults: defaults) else { return false }
        let acceptedAt = defaults.string(forKey: pendingAcceptedAtKey) ?? ISO8601DateFormatter().string(from: Date())
        defaults.set(LegalTerms.version, forKey: scopedVersionKey(for: accountID))
        defaults.set(acceptedAt, forKey: scopedAcceptedAtKey(for: accountID))
        clearPendingAcceptance(defaults: defaults)
        return true
    }

    static func acceptCurrentVersion(for accountID: String, defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(LegalTerms.version, forKey: scopedVersionKey(for: accountID))
        defaults.set(ISO8601DateFormatter().string(from: now), forKey: scopedAcceptedAtKey(for: accountID))
    }

    static func migrate(from oldAccountID: String, to newAccountID: String, defaults: UserDefaults = .standard) {
        guard oldAccountID != newAccountID,
              hasAcceptedCurrentVersion(for: oldAccountID, defaults: defaults),
              !hasAcceptedCurrentVersion(for: newAccountID, defaults: defaults) else { return }
        defaults.set(LegalTerms.version, forKey: scopedVersionKey(for: newAccountID))
        let acceptedAt = defaults.string(forKey: scopedAcceptedAtKey(for: oldAccountID)) ?? ISO8601DateFormatter().string(from: Date())
        defaults.set(acceptedAt, forKey: scopedAcceptedAtKey(for: newAccountID))
    }

    private static func scopedVersionKey(for accountID: String) -> String {
        "\(scopedVersionPrefix).\(normalizedAccountID(accountID))"
    }

    private static func scopedAcceptedAtKey(for accountID: String) -> String {
        "\(scopedAcceptedAtPrefix).\(normalizedAccountID(accountID))"
    }

    private static func normalizedAccountID(_ accountID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = accountID.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar).description : "_"
        }
        return String(scalars.joined()).prefix(96).description
    }
}

struct UserProfile: Codable, Identifiable, Hashable {
    struct User: Codable, Hashable {
        let id: String
        let email: String?
        let name: String?
        let avatarURL: String?

        enum CodingKeys: String, CodingKey {
            case id
            case email
            case name
            case avatarURL = "avatar_url"
        }
    }

    struct LinkedAccount: Codable, Hashable {
        let provider: String
        let linkedAt: String?

        enum CodingKeys: String, CodingKey {
            case provider
            case linkedAt = "linked_at"
        }
    }

    let user: User
    let linkedAccounts: [LinkedAccount]

    var id: String { user.id }

    enum CodingKeys: String, CodingKey {
        case user
        case linkedAccounts = "linked_accounts"
    }
}

struct UserSettingsResponse: Decodable, Hashable {
    let userID: String?
    let settings: RemoteUserSettings

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case settings
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        settings = try container.decodeIfPresent(RemoteUserSettings.self, forKey: .settings) ??
            container.decodeIfPresent(RemoteUserSettings.self, forKey: .content) ??
            RemoteUserSettings()
    }
}

struct RemoteUserSettings: Codable, Hashable {
    var notification: Bool? = nil
    var systemPrompt: String? = nil
    var webSearch: Bool? = nil
    var appearance: String? = nil
    var largeTextAsFile: Bool? = nil
    var temperature: Double? = nil
    var topP: Double? = nil
    var maxTokens: Int? = nil

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
