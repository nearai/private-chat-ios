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
        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: URLError(.timedOut))
        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: URLError(.networkConnectionLost))
        XCTAssertFalse(monitor.isTripped(.nearPrivate))
    }

    @MainActor
    func testSuccessAndManualResetClearRestriction() {
        let monitor = RouteHealthMonitor()
        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: Self.restrictedError)
        XCTAssertTrue(monitor.isTripped(.nearPrivate))

        monitor.recordSuccess(modelID: "Qwen/Qwen3.5-122B")
        XCTAssertFalse(monitor.isTripped(.nearPrivate))
        XCTAssertNotNil(monitor.restrictionNotice(for: .nearPrivate) == nil ? "ok" : nil)

        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: Self.restrictedError)
        XCTAssertTrue(monitor.isTripped(.nearPrivate))
        monitor.resetRoute(.nearPrivate)
        XCTAssertFalse(monitor.isTripped(.nearPrivate))
    }

    @MainActor
    func testRestrictionNoticeNamesProxyOptionForPrivateRoute() throws {
        let monitor = RouteHealthMonitor()
        monitor.recordFailure(modelID: "zai-org/GLM-5.1-FP8", error: Self.restrictedError)
        let notice = try XCTUnwrap(monitor.restrictionNotice(for: .nearPrivate))
        XCTAssertTrue(notice.localizedCaseInsensitiveContains("privacy proxy"))
        XCTAssertNil(monitor.restrictionNotice(for: .nearCloud))
    }

    func testTransportFailureMessageNeverEmitsNSErrorDump() {
        let mapped = MessageRepository.transportFailureMessage(URLError(.networkConnectionLost))
        XCTAssertEqual(mapped, "Connection dropped mid-answer — retry. Your prompt is kept.")
        let raw = "Error Domain=NSURLErrorDomain Code=-1005 \"The network connection was lost.\" UserInfo={_kCFStreamErrorCodeKey=53}"
        let display = MessageRepository.displayFailureMessage(raw)
        XCTAssertFalse(display.contains("Error Domain"))
        XCTAssertFalse(display.contains("kCFStream"))
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

        // Council member + synthesis survive; the council user turn also
        // survives (batch-tagged), alongside the remote user item.
        XCTAssertTrue(merged.contains(where: { $0.id == member.id }))
        XCTAssertTrue(merged.contains(where: { $0.id == synthesis.id }))
        XCTAssertTrue(merged.contains(where: { $0.id == remoteUser.id }))
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
