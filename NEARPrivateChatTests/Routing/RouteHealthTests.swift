import XCTest
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    private static let restrictedError = APIError.status(403, "Access temporarily restricted. Please try again later.")

    @MainActor
    func testRestrictedErrorTripsBreakerWithExponentialCooldown() {
        let monitor = RouteHealthMonitor()
        var nowValue = Date(timeIntervalSince1970: 1_800_000_000)
        monitor.now = { nowValue }

        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: Self.restrictedError)
        XCTAssertTrue(monitor.isTripped(.nearPrivate))
        XCTAssertFalse(monitor.isTripped(.nearCloud))

        // First trip: 60s cooldown — still tripped at +59s, clear at +61s.
        nowValue = nowValue.addingTimeInterval(59)
        XCTAssertTrue(monitor.isTripped(.nearPrivate))
        nowValue = nowValue.addingTimeInterval(2)
        XCTAssertFalse(monitor.isTripped(.nearPrivate))

        // Second consecutive trip doubles the cooldown to 120s.
        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: Self.restrictedError)
        nowValue = nowValue.addingTimeInterval(90)
        XCTAssertTrue(monitor.isTripped(.nearPrivate))
        nowValue = nowValue.addingTimeInterval(31)
        XCTAssertFalse(monitor.isTripped(.nearPrivate))
    }

    @MainActor
    func testPlanTimeoutAndTransportErrorsDoNotTripBreaker() {
        let monitor = RouteHealthMonitor()
        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: APIError.status(402, "not available in your plan"))
        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: APIError.status(403, "Access denied"))
        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: APIError.status(403, "Model is not available in your plan"))
        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: URLError(.timedOut))
        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: URLError(.networkConnectionLost))
        XCTAssertFalse(monitor.isTripped(.nearPrivate))
    }

    func testOnlyAuthAndRateLimitForbiddenErrorsTripRouteBreaker() {
        XCTAssertFalse(RouteHealthMonitor.isRestrictedClassError(APIError.status(403, "Access denied")))
        XCTAssertFalse(RouteHealthMonitor.isRestrictedClassError(APIError.status(403, "Model is not available in your plan")))
        XCTAssertTrue(RouteHealthMonitor.isRestrictedClassError(APIError.status(403, "Access temporarily restricted. Please try again later.")))
        XCTAssertTrue(RouteHealthMonitor.isRestrictedClassError(APIError.status(403, "Missing authorization header")))
        XCTAssertTrue(RouteHealthMonitor.isRestrictedClassError(APIError.status(429, "Too many requests")))
    }

    func testExplicitRateLimitFailureDetectsQuotaSignals() {
        XCTAssertTrue(RouteHealthMonitor.isExplicitRateLimitFailure(APIError.status(403, "Access temporarily restricted. Please try again later.")))
        XCTAssertTrue(RouteHealthMonitor.isExplicitRateLimitFailure(APIError.status(429, "")))
        XCTAssertTrue(RouteHealthMonitor.isExplicitRateLimitFailure(APIError.status(403, "Private route is rate-limited for this session. Wait for the cooldown, or use the privacy proxy only for this turn. If it keeps failing after cooldown, sign out and back in.")))
        XCTAssertFalse(RouteHealthMonitor.isExplicitRateLimitFailure(APIError.status(403, "The private route is busy right now. Retry private, or use the privacy proxy for this turn.")))
        XCTAssertFalse(RouteHealthMonitor.isExplicitRateLimitFailure(APIError.status(403, "Missing authorization header")))
    }

    @MainActor
    func testManualResetDoesNotBypassActiveExplicitRateLimit() {
        let monitor = RouteHealthMonitor()
        var nowValue = Date(timeIntervalSince1970: 1_800_000_000)
        monitor.now = { nowValue }

        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: APIError.status(429, "Too many requests"))

        XCTAssertTrue(monitor.isTripped(.nearPrivate))
        XCTAssertFalse(monitor.resetRoute(.nearPrivate))
        XCTAssertTrue(monitor.isTripped(.nearPrivate))

        nowValue = nowValue.addingTimeInterval(RouteHealthMonitor.baseCooldown + 1)
        XCTAssertTrue(monitor.resetRoute(.nearPrivate))
        XCTAssertFalse(monitor.isTripped(.nearPrivate))
    }

    @MainActor
    func testConnectionDiagnosticsTreatsHTTP429AsPrivateRateLimited() {
        let diagnostics = ConnectionDiagnostics()

        diagnostics.record(
            route: .nearPrivate,
            modelID: "zai-org/GLM-5.1-FP8",
            error: APIError.status(429, "Too many requests")
        )

        XCTAssertTrue(diagnostics.privateLooksSessionRateLimited)
    }

    func testTransientBusyFailureExcludesAuthAccessAndExplicitRateLimits() {
        XCTAssertFalse(RouteHealthMonitor.isTransientBusyFailure(APIError.status(403, "Access temporarily restricted. Please try again later.")))
        XCTAssertFalse(RouteHealthMonitor.isTransientBusyFailure(APIError.status(429, "Too many requests")))
        XCTAssertFalse(RouteHealthMonitor.isTransientBusyFailure(APIError.status(403, "Private route is rate-limited for this session. Wait for the cooldown, or use the privacy proxy only for this turn. If it keeps failing after cooldown, sign out and back in.")))
        XCTAssertTrue(RouteHealthMonitor.isTransientBusyFailure(APIError.status(403, "The private route is busy right now. Retry private, or use the privacy proxy for this turn.")))
        XCTAssertTrue(RouteHealthMonitor.isTransientBusyFailure(APIError.status(503, "The private route is temporarily busy.")))
        XCTAssertFalse(RouteHealthMonitor.isTransientBusyFailure(APIError.status(503, "Private route is rate-limited for this session.")))

        XCTAssertFalse(RouteHealthMonitor.isTransientBusyFailure(APIError.status(401, "Missing authorization header")))
        XCTAssertFalse(RouteHealthMonitor.isTransientBusyFailure(APIError.status(403, "Missing authorization header")))
        XCTAssertFalse(RouteHealthMonitor.isTransientBusyFailure(APIError.status(403, "Access denied")))
    }

    func testDisplayFailureMessageDistinguishesPrivateBusyFromRateLimit() {
        let busy = ErrorMessageMapper.displayFailureMessage("The private route is busy right now. Retry private, or use the privacy proxy for this turn.")
        XCTAssertTrue(busy.localizedCaseInsensitiveContains("busy"))
        XCTAssertFalse(busy.localizedCaseInsensitiveContains("rate-limited"))
        XCTAssertFalse(busy.localizedCaseInsensitiveContains("sign out"))

        let limited = ErrorMessageMapper.displayFailureMessage("Access temporarily restricted. Please try again later.")
        XCTAssertTrue(limited.localizedCaseInsensitiveContains("rate-limited"))
        XCTAssertTrue(limited.localizedCaseInsensitiveContains("sign out"))
    }

    func testPrivateProxyRecoveryPolicyRequiresRouteFailureSignal() {
        let privateModelID = ModelOption.nearPrivateDefaultModelID
        let cloudModelID = ModelOption.nearCloudModelID(for: "openai/gpt-5.2")

        XCTAssertFalse(PrivateRouteRecoveryPolicy.shouldOfferPrivacyProxyRetry(
            modelID: privateModelID,
            failureMessage: "Access denied by the NEAR Private API. Sign in again or choose another available model.",
            routeIsTripped: false
        ))
        XCTAssertFalse(PrivateRouteRecoveryPolicy.shouldOfferPrivacyProxyRetry(
            modelID: cloudModelID,
            failureMessage: "The private route is busy right now. Retry private, or use the privacy proxy for this turn.",
            routeIsTripped: true
        ))
        XCTAssertTrue(PrivateRouteRecoveryPolicy.shouldOfferPrivacyProxyRetry(
            modelID: privateModelID,
            failureMessage: "The private route is busy right now. Retry private, or use the privacy proxy for this turn.",
            routeIsTripped: false
        ))
        XCTAssertTrue(PrivateRouteRecoveryPolicy.shouldOfferPrivacyProxyRetry(
            modelID: privateModelID,
            failureMessage: "Access denied",
            routeIsTripped: true
        ))
    }

    @MainActor
    func testSuccessClearsRestrictionAndManualResetCannotBypassExplicitRateLimit() {
        let monitor = RouteHealthMonitor()
        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: Self.restrictedError)
        XCTAssertTrue(monitor.isTripped(.nearPrivate))

        monitor.recordSuccess(modelID: "Qwen/Qwen3.5-122B")
        XCTAssertFalse(monitor.isTripped(.nearPrivate))
        XCTAssertNotNil(monitor.restrictionNotice(for: .nearPrivate) == nil ? "ok" : nil)

        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: Self.restrictedError)
        XCTAssertTrue(monitor.isTripped(.nearPrivate))
        XCTAssertFalse(monitor.resetRoute(.nearPrivate))
        XCTAssertTrue(monitor.isTripped(.nearPrivate))
    }

    @MainActor
    func testRestrictionNoticeNamesProxyOptionForPrivateRoute() throws {
        let monitor = RouteHealthMonitor()
        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: Self.restrictedError)
        let notice = try XCTUnwrap(monitor.restrictionNotice(for: .nearPrivate))
        XCTAssertTrue(notice.localizedCaseInsensitiveContains("privacy proxy"))
        XCTAssertTrue(notice.localizedCaseInsensitiveContains("cooldown"))
        XCTAssertFalse(notice.localizedCaseInsensitiveContains("retry private"))
        XCTAssertTrue(notice.localizedCaseInsensitiveContains("sign out"))
        XCTAssertFalse(notice.localizedCaseInsensitiveContains("retrying automatically"))
        XCTAssertNil(monitor.restrictionNotice(for: .nearCloud))
    }

    func testAuthFailureIsDistinguishedFromRateLimit() {
        // 401 → auth. A 403 with rate-limit wording → NOT auth. A 403 with
        // auth wording → auth.
        XCTAssertTrue(RouteHealthMonitor.isAuthFailure(APIError.status(401, "")))
        XCTAssertFalse(RouteHealthMonitor.isAuthFailure(APIError.status(403, "Access temporarily restricted")))
        XCTAssertTrue(RouteHealthMonitor.isAuthFailure(APIError.status(403, "Missing authorization header")))
        XCTAssertTrue(RouteHealthMonitor.isAuthFailure(APIError.status(403, "Missing bearer token")))
        XCTAssertTrue(RouteHealthMonitor.isAuthFailure(APIError.status(403, "Token rejected for private route")))
        XCTAssertTrue(RouteHealthMonitor.isAuthFailure(APIError.status(401, "invalid or expired authentication token")))
    }

    func testDisplayFailureMessageMapsRejectedSessionToAuthRecovery() {
        let missingBearer = ErrorMessageMapper.displayFailureMessage("Missing bearer token")
        XCTAssertTrue(missingBearer.localizedCaseInsensitiveContains("Authentication is missing or expired"))
        XCTAssertFalse(missingBearer.localizedCaseInsensitiveContains("rate-limited"))

        let rejected = ErrorMessageMapper.displayFailureMessage("Token rejected for private route")
        XCTAssertTrue(rejected.localizedCaseInsensitiveContains("Sign in again"))
        XCTAssertFalse(rejected.localizedCaseInsensitiveContains("busy"))
    }

    @MainActor
    func testReWrappedPrivateAuthNoticeDoesNotTripAgentBreaker() throws {
        // The agent pipeline fails fast on an open private breaker by
        // re-throwing restrictionNotice as APIError.status(403, notice). The
        // wrapped 403 must still classify as an auth failure, or the agent
        // breaker trips and the user sees generic "temporarily busy" copy for
        // what is actually a sign-in problem.
        let monitor = RouteHealthMonitor()
        monitor.recordFailure(
            modelID: "zai-org/GLM-5.1-FP8",
            error: APIError.status(401, "invalid or expired authentication token")
        )
        XCTAssertTrue(monitor.isTripped(.nearPrivate))
        let notice = try XCTUnwrap(monitor.restrictionNotice(for: .nearPrivate))
        let rewrapped = APIError.status(403, notice)
        XCTAssertTrue(RouteHealthMonitor.isAuthFailure(rewrapped))

        // recordFailure's auth-only-trips-private guard must swallow the
        // re-wrapped 403 for the agent route.
        monitor.recordFailure(modelID: ModelOption.ironclawMobileModelID, error: rewrapped)
        XCTAssertFalse(monitor.isTripped(.ironclawMobile))
    }

    @MainActor
    func testAuthFailureNoticeSaysSignInNotBusy() throws {
        let monitor = RouteHealthMonitor()
        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: APIError.status(401, "Missing authorization header"))
        XCTAssertTrue(monitor.isTripped(.nearPrivate))
        let notice = try XCTUnwrap(monitor.restrictionNotice(for: .nearPrivate))
        XCTAssertTrue(notice.localizedCaseInsensitiveContains("sign"))
        XCTAssertFalse(notice.localizedCaseInsensitiveContains("temporarily busy"))
    }

    @MainActor
    func testRateLimitNoticeStillSaysBusyNotSignIn() throws {
        let monitor = RouteHealthMonitor()
        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: Self.restrictedError)
        let notice = try XCTUnwrap(monitor.restrictionNotice(for: .nearPrivate))
        XCTAssertTrue(notice.localizedCaseInsensitiveContains("rate-limited"))
        XCTAssertFalse(notice.localizedCaseInsensitiveContains("isn't authenticated"))
    }

    @MainActor
    func testBusyNoticeDoesNotCallBusyRouteRateLimited() throws {
        let monitor = RouteHealthMonitor()
        monitor.recordFailure(
            modelID: "zai-org/GLM-5.1-FP8",
            error: APIError.status(403, "The private route is busy right now. Retry private, or use the privacy proxy for this turn.")
        )
        let notice = try XCTUnwrap(monitor.restrictionNotice(for: .nearPrivate))
        XCTAssertTrue(notice.localizedCaseInsensitiveContains("busy"))
        XCTAssertTrue(notice.localizedCaseInsensitiveContains("privacy proxy"))
        XCTAssertFalse(notice.localizedCaseInsensitiveContains("rate-limited"))
    }

    @MainActor
    func testCloudAuthFailureDoesNotTripCloudBreaker() {
        // A missing/stale NEAR Cloud key throws a local 401 before any network
        // call; tripping the cloud breaker would lock the route for 60s even
        // after the user fixes the key. Only private auth failures trip.
        let monitor = RouteHealthMonitor()
        let cloudModelID = ModelOption.nearCloudModelID(for: "openai/gpt-5.2")
        monitor.recordFailure(modelID: cloudModelID, error: APIError.status(401, "Connect NEAR AI Cloud in Account to use GPT-5.2."))
        XCTAssertFalse(monitor.isTripped(.nearCloud))

        // A cloud 403 rate-limit-class failure still trips.
        monitor.recordFailure(modelID: cloudModelID, error: APIError.status(403, "Access temporarily restricted"))
        XCTAssertTrue(monitor.isTripped(.nearCloud))
    }

    func testTransportFailureMessageNeverEmitsNSErrorDump() {
        let mapped = MessageRepository.transportFailureMessage(URLError(.networkConnectionLost))
        XCTAssertEqual(mapped, "Connection dropped mid-answer — retry. Your prompt is kept.")
        XCTAssertEqual(ErrorMessageMapper.transportFailureMessage(URLError(.networkConnectionLost)), mapped)
        let raw = "Error Domain=NSURLErrorDomain Code=-1005 \"The network connection was lost.\" UserInfo={_kCFStreamErrorCodeKey=53}"
        let display = ErrorMessageMapper.displayFailureMessage(raw)
        XCTAssertFalse(display.contains("Error Domain"))
        XCTAssertFalse(display.contains("kCFStream"))
        XCTAssertEqual(MessageRepository.displayFailureMessage(raw), display)
    }

    func testMergePreservesCouncilBatchWithoutExternalTurn() {
        let remoteUser = ChatMessage(
            id: "remote-user", role: .user, text: "compare the models", model: nil,
            createdAt: Date(timeIntervalSince1970: 100), status: "completed", responseID: nil, isStreaming: false
        )
        var member = ChatMessage(
            id: "local-council-0-abc", role: .assistant, text: "Answer A", model: "zai-org/GLM-5.1-FP8",
            createdAt: Date(timeIntervalSince1970: 101), status: "completed", responseID: "resp-a", isStreaming: false
        )
        member.councilBatchID = "council-1"
        var synthesis = ChatMessage(
            id: "local-council-synthesis-abc", role: .assistant, text: "Synthesis", model: ModelOption.llmCouncilSynthesisModelID,
            createdAt: Date(timeIntervalSince1970: 102), status: "completed", responseID: nil, isStreaming: false
        )
        synthesis.councilBatchID = "council-1"
        var localUser = ChatMessage(
            id: "local-user-abc", role: .user, text: "compare the models", model: nil,
            createdAt: Date(timeIntervalSince1970: 100), status: "completed", responseID: nil, isStreaming: false
        )
        localUser.councilBatchID = "council-1"

        let merged = MessageRepository.mergedMessages(
            remoteMessages: [remoteUser],
            localCache: [localUser, member, synthesis]
        )

        // Council member + synthesis survive. The remote user turn already
        // carries the prompt, so the local batch user is not duplicated.
        XCTAssertTrue(merged.contains(where: { $0.id == member.id }))
        XCTAssertTrue(merged.contains(where: { $0.id == synthesis.id }))
        XCTAssertTrue(merged.contains(where: { $0.id == remoteUser.id }))
        XCTAssertFalse(merged.contains(where: { $0.id == localUser.id }))
    }

    func testMergeDropsOrphanedCouncilUserWhenServerHasPrompt() {
        let remoteUser = ChatMessage(
            id: "remote-user", role: .user, text: "What is happening in Iran", model: nil,
            createdAt: Date(timeIntervalSince1970: 100), status: "completed", responseID: nil, isStreaming: false
        )
        var staleCouncilUser = ChatMessage(
            id: "local-user-stale-council", role: .user, text: "What is happening in Iran", model: nil,
            createdAt: Date(timeIntervalSince1970: 99), status: "completed", responseID: nil, isStreaming: false
        )
        staleCouncilUser.councilBatchID = "removed-council-batch"

        let merged = MessageRepository.mergedMessages(
            remoteMessages: [remoteUser],
            localCache: [staleCouncilUser]
        )

        XCTAssertEqual(merged.map(\.id), [remoteUser.id])
    }

    func testMergeStillDropsCompletedPrivateNonCouncilLocalAssistant() {
        let remote = ChatMessage(
            id: "server-1", role: .assistant, text: "Answer", model: "zai-org/GLM-5.1-FP8",
            createdAt: Date(timeIntervalSince1970: 100), status: "completed", responseID: "resp-1", isStreaming: false
        )
        let localCopy = ChatMessage(
            id: "local-assistant-dup", role: .assistant, text: "Answer", model: "zai-org/GLM-5.1-FP8",
            createdAt: Date(timeIntervalSince1970: 100), status: "completed", responseID: "resp-1", isStreaming: false
        )
        let merged = MessageRepository.mergedMessages(remoteMessages: [remote], localCache: [localCopy])
        XCTAssertEqual(merged.map(\.id), ["server-1"])
    }

    func testMergePreservesLocalSourcesOnRemoteAssistantWithSameResponseID() {
        let remote = ChatMessage(
            id: "server-1", role: .assistant, text: "Answer", model: "zai-org/GLM-5.1-FP8",
            createdAt: Date(timeIntervalSince1970: 100), status: "completed", responseID: "resp-1", isStreaming: false
        )
        var localCopy = ChatMessage(
            id: "local-assistant-dup", role: .assistant, text: "Answer", model: "zai-org/GLM-5.1-FP8",
            createdAt: Date(timeIntervalSince1970: 100), status: "completed", responseID: "resp-1", isStreaming: false
        )
        let source = WebSearchSource(
            type: "news",
            url: "https://example.com/ai-news",
            title: "AI news today",
            publishedAt: "June 13, 2026",
            snippet: nil
        )
        localCopy.searchQuery = "AI news today"
        localCopy.sources = [source]

        let merged = MessageRepository.mergedMessages(remoteMessages: [remote], localCache: [localCopy])

        XCTAssertEqual(merged.map(\.id), ["server-1"])
        XCTAssertEqual(merged.first?.searchQuery, "AI news today")
        XCTAssertEqual(merged.first?.sources, [source])
    }

    func testMergePreservesCancelledTurnsAndDedupesUserByText() {
        let remoteUser = ChatMessage(
            id: "server-user", role: .user, text: "long question", model: nil,
            createdAt: Date(timeIntervalSince1970: 100), status: "completed", responseID: nil, isStreaming: false
        )
        let localUserDup = ChatMessage(
            id: "local-user-dup", role: .user, text: "long question", model: nil,
            createdAt: Date(timeIntervalSince1970: 100), status: "completed", responseID: nil, isStreaming: false
        )
        let cancelled = ChatMessage(
            id: "local-assistant-stopped", role: .assistant, text: "partial answer…", model: "zai-org/GLM-5.1-FP8",
            createdAt: Date(timeIntervalSince1970: 101), status: "cancelled", responseID: nil, isStreaming: false
        )
        let merged = MessageRepository.mergedMessages(
            remoteMessages: [remoteUser],
            localCache: [localUserDup, cancelled]
        )
        XCTAssertTrue(merged.contains(where: { $0.id == cancelled.id }))
        XCTAssertEqual(merged.filter { $0.role == .user }.count, 1)
    }

    @MainActor
    func testBriefingBackoffScheduleAndDueGating() async {
        XCTAssertEqual(BriefingStore.retryBackoff(afterConsecutiveFailures: 1), 15 * 60)
        XCTAssertEqual(BriefingStore.retryBackoff(afterConsecutiveFailures: 2), 30 * 60)
        XCTAssertEqual(BriefingStore.retryBackoff(afterConsecutiveFailures: 3), 60 * 60)
        XCTAssertEqual(BriefingStore.retryBackoff(afterConsecutiveFailures: 9), 6 * 3600)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("briefings.json")
        let briefing = Briefing(
            title: "NEAR price", prompt: "p", schedule: .everyNHours(1),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let store = BriefingStore(briefings: [briefing], fileURL: fileURL) { _ in .failed("busy") }

        let runTime = Date(timeIntervalSince1970: 1_800_010_000)
        await store.run(briefing, now: runTime)

        let updated = try! XCTUnwrap(store.briefings.first)
        XCTAssertEqual(updated.consecutiveFailureCount, 1)
        XCTAssertEqual(updated.nextRetryAt, runTime.addingTimeInterval(15 * 60))

        // Within the backoff window the briefing is NOT due; after it, it is.
        XCTAssertFalse(store.dueBriefings(now: runTime.addingTimeInterval(60)).contains(where: { $0.id == briefing.id }))
        XCTAssertTrue(store.dueBriefings(now: runTime.addingTimeInterval(16 * 60)).contains(where: { $0.id == briefing.id }))

        // A successful run clears the backoff.
        store.runner = { _ in .delivered(MessageWidget(kind: .generic, title: "x", note: "y")) }
        await store.run(briefing, now: runTime.addingTimeInterval(16 * 60))
        let recovered = try! XCTUnwrap(store.briefings.first)
        XCTAssertEqual(recovered.consecutiveFailureCount, 0)
        XCTAssertNil(recovered.nextRetryAt)
    }

    func testBriefingDecodesLegacyJSONWithoutBackoffFields() throws {
        let modern = Briefing(title: "Legacy", prompt: "p", schedule: .daily(hour: 8, minute: 0))
        let data = try JSONEncoder().encode(modern)
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "consecutiveFailureCount")
        dict.removeValue(forKey: "nextRetryAt")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Briefing.self, from: legacyData)
        XCTAssertEqual(decoded.consecutiveFailureCount, 0)
        XCTAssertNil(decoded.nextRetryAt)
    }

    func testSynthesisPromptCapsTotalBudgetAcrossMembers() {
        let longText = String(repeating: "a", count: 6_000)
        let four = (1...4).map { ("Model \($0)", longText) }
        let prompt = CouncilStreamService.synthesisPrompt(
            originalPrompt: "q",
            routedPrompt: "q",
            responses: four
        )
        // 4 members → 3k per member, so the responses section stays ≤ ~12k.
        XCTAssertLessThan(prompt.count, 14_000)
    }
}
