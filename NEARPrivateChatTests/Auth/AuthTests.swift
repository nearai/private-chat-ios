import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testAuthCallbackAcceptsAuthorizationCodeWithMatchingState() throws {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)
        let url = URL(string: "nearprivatechat://auth?code=auth-code-1&state=nonce-1")!

        let callback = try api.parseAuthCallback(url, expectedState: "nonce-1")

        XCTAssertEqual(callback.code, "auth-code-1")
        XCTAssertEqual(callback.state, "nonce-1")
    }

    func testAuthCallbackRejectsMissingOrWrongState() {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)
        let missingStateURL = URL(string: "nearprivatechat://auth?code=auth-code-1")!
        let wrongStateURL = URL(string: "nearprivatechat://auth?code=auth-code-1&state=other")!

        XCTAssertThrowsError(try api.parseAuthCallback(missingStateURL, expectedState: "nonce-1"))
        XCTAssertThrowsError(try api.parseAuthCallback(wrongStateURL, expectedState: "nonce-1"))
    }

    func testAuthCallbackAcceptsFragmentAuthorizationCode() throws {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)
        let url = URL(string: "nearprivatechat://auth#code=auth-code-1&state=nonce-1")!

        let callback = try api.parseAuthCallback(url, expectedState: "nonce-1")

        XCTAssertEqual(callback.code, "auth-code-1")
    }

    func testAuthCallbackRejectsBearerTokenAliases() {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)
        let aliases = [
            "token",
            "session_token",
            "auth_token",
            "access_token",
            "bearer_token"
        ]
        for alias in aliases {
            let url = URL(string: "nearprivatechat://auth?\(alias)=session-token&state=nonce-1")!
            XCTAssertThrowsError(try api.parseAuthCallback(url, expectedState: "nonce-1"), alias)
        }
    }

    func testAuthenticatedRequestsRejectWhitespaceSessionTokenBeforeNetwork() async {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)
        api.authToken = "   \n\t"

        do {
            _ = try await api.fetchModels()
            XCTFail("Expected whitespace-only auth tokens to be rejected before a request is sent.")
        } catch APIError.unauthenticated {
            // Expected: no Authorization header should be attempted with an empty credential.
        } catch {
            XCTFail("Expected unauthenticated error, got \(error).")
        }
    }

    func testAuthCallbackToleratesDuplicateStateValues() throws {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)
        let url = URL(string: "nearprivatechat://auth?state=provider-state&code=auth-code-1&state=nonce-1")!

        let callback = try api.parseAuthCallback(url, expectedState: "nonce-1")

        XCTAssertEqual(callback.code, "auth-code-1")
        XCTAssertEqual(callback.providerState, "provider-state")
    }

    func testAuthCallbackRejectsProviderManagedStateByDefault() {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)
        let url = URL(string: "nearprivatechat://auth?code=auth-code-1&state=provider-state")!

        XCTAssertThrowsError(try api.parseAuthCallback(url, expectedState: "nonce-1"))
    }

    func testAuthCallbackRejectsMissingAppStateForActiveWebSession() {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)
        let url = URL(string: "nearprivatechat://auth/auth/callback?code=auth-code-1")!

        XCTAssertThrowsError(try api.parseAuthCallback(url, expectedState: "nonce-1"))
    }

    func testNearAuthURLIncludesState() throws {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)

        let url = try api.authURL(for: OAuthProvider.near, state: "nonce-1")

        XCTAssertTrue(url.absoluteString.contains("state=nonce-1"))
    }

    func testUserProfileRoundTripsForLaunchCache() throws {
        let profile = UserProfile(
            user: UserProfile.User(
                id: "user-123",
                email: "demo@example.com",
                name: "Demo User",
                avatarURL: "https://example.com/avatar.png"
            ),
            linkedAccounts: [
                UserProfile.LinkedAccount(provider: "google", linkedAt: "2026-05-26T10:00:00Z")
            ]
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.id, "user-123")
    }

    func testAuthURLUsesPKCECodeFlowForProviderLogin() throws {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)

        let url = try api.authURL(for: OAuthProvider.github, state: "nonce-1", codeChallenge: "challenge-1")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let callback = try XCTUnwrap(values["frontend_callback"])

        XCTAssertTrue(callback.contains("state=nonce-1"))
        XCTAssertEqual(values["state"], "nonce-1")
        XCTAssertEqual(values["response_type"], "code")
        XCTAssertEqual(values["code_challenge"], "challenge-1")
        XCTAssertEqual(values["code_challenge_method"], "S256")
    }

    func testAuthURLCanRequestPKCECodeFlow() throws {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)

        let url = try api.authURL(
            for: OAuthProvider.github,
            state: "nonce-1",
            codeChallenge: "challenge-1"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertTrue(values["frontend_callback"]?.contains("state=nonce-1") == true)
        XCTAssertEqual(values["state"], "nonce-1")
        XCTAssertEqual(values["response_type"], "code")
        XCTAssertEqual(values["code_challenge"], "challenge-1")
        XCTAssertEqual(values["code_challenge_method"], "S256")
    }

    func testSessionPersistenceKeepsLegacyAuthStorageKeys() {
        XCTAssertEqual(SessionPersistence.sessionKeychainAccount, "session")
        XCTAssertEqual(SessionPersistence.profileKeychainAccount, "profile")
        XCTAssertEqual(SessionPersistence.pendingAuthStateKey, "pendingAuthState")
        XCTAssertEqual(SessionPersistence.simulatorFallbackKey, "debug.session")
        XCTAssertEqual(SessionPersistence.pendingAuthTTL, TimeInterval(10 * 60))
        XCTAssertEqual(SessionPersistence.simulatorFallbackTTL, TimeInterval(24 * 60 * 60))
    }

    func testSessionPersistencePendingAuthStateRoundTripsOnStableKey() throws {
        let defaults = try makeIsolatedDefaults()
        let persistence = SessionPersistence(defaults: defaults)

        let request = persistence.createPendingAuthRequest(
            provider: .github,
            state: "nonce-1",
            codeVerifier: "verifier-1"
        )

        XCTAssertNotNil(defaults.data(forKey: SessionPersistence.pendingAuthStateKey))
        XCTAssertEqual(request.state, "nonce-1")
        XCTAssertEqual(request.provider, .github)
        XCTAssertEqual(request.codeVerifier, "verifier-1")
        XCTAssertLessThanOrEqual(request.expiresAt.timeIntervalSinceNow, SessionPersistence.pendingAuthTTL)
        XCTAssertGreaterThan(request.expiresAt.timeIntervalSinceNow, SessionPersistence.pendingAuthTTL - 5)

        let loaded = try persistence.requirePendingAuthRequest()
        XCTAssertEqual(loaded, request)

        persistence.clearPendingAuthState()
        XCTAssertNil(defaults.data(forKey: SessionPersistence.pendingAuthStateKey))
    }

    func testSessionPersistenceExpiredPendingAuthStateIsRejectedAndCleared() throws {
        let defaults = try makeIsolatedDefaults()
        let persistence = SessionPersistence(defaults: defaults)
        let expired = PendingAuthRequest(
            state: "nonce-1",
            providerRawValue: OAuthProvider.near.rawValue,
            codeVerifier: "verifier-1",
            expiresAt: Date().addingTimeInterval(-1)
        )
        defaults.set(try JSONEncoder().encode(expired), forKey: SessionPersistence.pendingAuthStateKey)

        XCTAssertThrowsError(try persistence.requirePendingAuthRequest()) { error in
            guard case let APIError.status(code, message) = error else {
                XCTFail("Expected APIError.status, got \(error).")
                return
            }
            XCTAssertEqual(code, 401)
            XCTAssertTrue(message.contains("expired"))
        }
        XCTAssertNil(defaults.data(forKey: SessionPersistence.pendingAuthStateKey))
    }

    func testSessionPersistenceSimulatorFallbackRoundTripsAndExpiresOnDebugKey() throws {
        let defaults = try makeIsolatedDefaults()
        let persistence = SessionPersistence(defaults: defaults)
        let session = AuthSession(
            token: "session-token-1",
            sessionID: "session-id-1",
            expiresAt: nil,
            isNewUser: false
        )

        #if targetEnvironment(simulator)
        XCTAssertTrue(persistence.saveSimulatorFallbackSession(session))
        XCTAssertNotNil(defaults.data(forKey: SessionPersistence.simulatorFallbackKey))
        XCTAssertEqual(persistence.loadSimulatorFallbackSession(), session)

        let expired = SimulatorFallbackSessionEnvelope(
            session: session,
            expiresAt: Date().addingTimeInterval(-1)
        )
        defaults.set(try JSONEncoder().encode(expired), forKey: SessionPersistence.simulatorFallbackKey)

        XCTAssertNil(persistence.loadSimulatorFallbackSession())
        XCTAssertNil(defaults.data(forKey: SessionPersistence.simulatorFallbackKey))
        #else
        XCTAssertFalse(persistence.saveSimulatorFallbackSession(session))
        XCTAssertNil(defaults.data(forKey: SessionPersistence.simulatorFallbackKey))
        #endif
    }

    func testAppDeepLinksRoutePhoneShortcutsWithoutAuthCollision() throws {
        let agent = try XCTUnwrap(AppDeepLinkAction.parse(URL(string: "nearprivatechat://agent?source=web&prompt=Review%20this")!))
        XCTAssertEqual(agent.route, .agent)
        XCTAssertEqual(agent.sourceMode, .web)
        XCTAssertEqual(agent.draft, "Review this")

        let verified = try XCTUnwrap(AppDeepLinkAction.parse(URL(string: "nearprivatechat://chat/new?route=verified&research=true")!))
        XCTAssertEqual(verified.route, .verified)
        XCTAssertTrue(verified.researchMode)

        XCTAssertNil(AppDeepLinkAction.parse(URL(string: "nearprivatechat://auth?token=abc&state=nonce-1")!))
        XCTAssertNil(AppDeepLinkAction.parse(URL(string: "https://private.near.ai/c/conv_123")!))
    }

    func testConversationItemDecodesSharedAuthorMetadata() throws {
        let payload = Data("""
        {
          "type": "message",
          "id": "msg-1",
          "response_id": "resp-1",
          "next_response_ids": [],
          "created_at": 1700000000,
          "status": "completed",
          "role": "user",
          "content": [{"type": "input_text", "text": "Hello"}],
          "model": "zai-org/GLM-5.1-FP8",
          "metadata": {
            "author_id": "user-123",
            "author_name": "Alex Rivera"
          }
        }
        """.utf8)

        let item = try JSONDecoder().decode(ConversationItem.self, from: payload)

        XCTAssertEqual(item.metadata?.authorID, "user-123")
        XCTAssertEqual(item.metadata?.authorName, "Alex Rivera")
    }

    func testChatMessageAuthorMetadataIsTrimmedForDisplay() {
        let message = ChatMessage(
            id: "msg-1",
            role: .user,
            text: "Hello",
            model: nil,
            createdAt: Date(timeIntervalSince1970: 1_000),
            status: "completed",
            responseID: nil,
            isStreaming: false,
            metadata: MessageMetadata(authorID: " user-123 ", authorName: "  Alex Rivera  ")
        )

        XCTAssertEqual(message.authorID, "user-123")
        XCTAssertEqual(message.authorName, "Alex Rivera")
        XCTAssertEqual(message.authorDisplayLabel, "Alex Rivera")
    }

    func testChatMessageAuthorDisplayFallsBackToCompactAuthorID() {
        let message = ChatMessage(
            id: "msg-2",
            role: .assistant,
            text: "Hi",
            model: "zai-org/GLM-5.1-FP8",
            createdAt: Date(timeIntervalSince1970: 2_000),
            status: "completed",
            responseID: nil,
            isStreaming: false,
            metadata: MessageMetadata(
                authorID: "near-user-account-1234567890abcdef",
                authorName: nil
            )
        )

        XCTAssertEqual(message.compactAuthorID, "near-user-...abcdef")
        XCTAssertEqual(message.authorDisplayLabel, "near-user-...abcdef")
    }

    func testShareStoreShowsSharedAuthorNamesOnlyWhenNeeded() {
        XCTAssertFalse(ShareStore.shouldShowSharedAuthorNames(sharedPreview: nil, shareInfo: nil))

        let ownedEmptyShare = ConversationSharesListResponse(
            isOwner: true,
            canShare: true,
            canWrite: true,
            shares: [],
            owner: nil
        )
        XCTAssertFalse(ShareStore.shouldShowSharedAuthorNames(sharedPreview: nil, shareInfo: ownedEmptyShare))

        let publicShare = ConversationShareInfo(
            id: "share-1",
            conversationID: "conv-1",
            permission: "read",
            shareType: "public",
            recipient: nil,
            groupID: nil,
            orgEmailPattern: nil,
            publicToken: "token",
            createdAt: nil,
            updatedAt: nil
        )
        let ownedPublicShare = ConversationSharesListResponse(
            isOwner: true,
            canShare: true,
            canWrite: true,
            shares: [publicShare],
            owner: nil
        )
        XCTAssertTrue(ShareStore.shouldShowSharedAuthorNames(sharedPreview: nil, shareInfo: ownedPublicShare))
    }


    func testSharedPreviewEnablesAuthorNamesWithoutShareSheetState() {
        XCTAssertFalse(ShareStore.shouldShowSharedAuthorNames(sharedPreview: nil, shareInfo: nil))

        let snapshot = SharedConversationSnapshot(
            conversation: ConversationSummary(
                id: "conv-shared",
                createdAt: 1_700_000_000,
                metadata: ConversationMetadata(title: "Shared", pinnedAt: nil, archivedAt: nil, importedAt: nil, rootResponseID: nil)
            ),
            messages: [],
            source: "https://private.near.ai/c/conv-shared",
            canWrite: false,
            loadedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(ShareStore.shouldShowSharedAuthorNames(sharedPreview: snapshot, shareInfo: nil))
    }

    func testAuthCallbackRequiresActiveState() {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)
        let url = URL(string: "nearprivatechat://auth?token=session-token&state=nonce-1")!

        XCTAssertThrowsError(try api.parseAuthCallback(url))
    }
}
