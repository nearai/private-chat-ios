import XCTest
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    @MainActor
    func testDiagnosticsRecordsRealStatusAndMessage() {
        let diagnostics = ConnectionDiagnostics()
        diagnostics.record(
            route: .nearPrivate,
            modelID: "session-probe",
            error: APIError.status(401, "Missing authorization header")
        )
        let outcome = diagnostics.lastPrivateOutcome
        XCTAssertEqual(outcome?.statusCode, 401)
        XCTAssertEqual(outcome?.message, "Missing authorization header")
        XCTAssertEqual(outcome?.statusLabel, "HTTP 401")
        XCTAssertEqual(outcome?.succeeded, false)
    }

    @MainActor
    func testDiagnosticsPrivateLooksUnauthenticatedOnlyWhenCloudWorks() {
        let diagnostics = ConnectionDiagnostics()
        // Private 403 with auth wording, cloud succeeded → it's the private
        // session, not the network or the account.
        diagnostics.record(route: .nearPrivate, modelID: "glm", error: APIError.status(403, "Missing authorization header"))
        diagnostics.recordSuccess(route: .nearCloud, modelID: "gpt")
        XCTAssertTrue(diagnostics.privateLooksUnauthenticated)

        // A transport error (no status) is not an auth signature.
        diagnostics.reset()
        diagnostics.record(route: .nearPrivate, modelID: "glm", error: URLError(.notConnectedToInternet))
        XCTAssertFalse(diagnostics.privateLooksUnauthenticated)
    }

    @MainActor
    func testDiagnosticsRateLimit403IsNotUnauthenticated() {
        let diagnostics = ConnectionDiagnostics()
        // A 403 rate limit is not an auth failure — the unauthenticated banner
        // (remedy: sign back in) must not show for it even when cloud works.
        diagnostics.record(
            route: .nearPrivate,
            modelID: "glm",
            error: APIError.status(403, "Access temporarily restricted. Please try again later.")
        )
        diagnostics.recordSuccess(route: .nearCloud, modelID: "gpt")
        XCTAssertEqual(diagnostics.lastPrivateOutcome?.wasAuthFailure, false)
        XCTAssertFalse(diagnostics.privateLooksUnauthenticated)
    }

    @MainActor
    func testDiagnosticsOutcomeCarriesAuthFailureClassification() {
        let diagnostics = ConnectionDiagnostics()
        diagnostics.record(route: .nearPrivate, modelID: "session-probe", error: APIError.status(401, "no token"))
        XCTAssertEqual(diagnostics.lastPrivateOutcome?.wasAuthFailure, true)
        diagnostics.recordSuccess(route: .nearPrivate, modelID: "session-probe")
        XCTAssertEqual(diagnostics.lastPrivateOutcome?.wasAuthFailure, false)
        XCTAssertFalse(diagnostics.privateLooksUnauthenticated)
    }

    @MainActor
    func testDiagnosticsIgnoresCancellation() {
        let diagnostics = ConnectionDiagnostics()
        // A user cancellation is not a route outcome — recording it would put
        // a phantom failure on the raw-truth screen.
        diagnostics.record(route: .nearPrivate, modelID: "glm", error: CancellationError())
        XCTAssertNil(diagnostics.lastPrivateOutcome)
        diagnostics.record(route: .nearPrivate, modelID: "glm", error: URLError(.cancelled))
        XCTAssertNil(diagnostics.lastPrivateOutcome)
    }

    func testContextBlockFallsBackToOpeningChunksForGenericQuestion() throws {
        // A summary-style question shares no keywords with the body. Before the
        // fix this returned nil and the model saw only the filename.
        let document = String(repeating: "The quarterly revenue figures and margins are detailed herein. ", count: 60)
        let block = try XCTUnwrap(
            DocumentChunker.contextBlock(for: "summarize this please", in: [document], topK: 4)
        )
        XCTAssertTrue(block.contains("quarterly revenue"))
    }

    func testContextBlockStillRanksByKeywordWhenPresent() throws {
        let docs = [
            "Section about gardening and soil composition for tomatoes.",
            "The settlement amount is ZEPHYR-7 and the closing date is March."
        ]
        let block = try XCTUnwrap(
            DocumentChunker.contextBlock(for: "what is the settlement amount", in: docs, topK: 2)
        )
        XCTAssertTrue(block.contains("ZEPHYR-7"))
    }
}
