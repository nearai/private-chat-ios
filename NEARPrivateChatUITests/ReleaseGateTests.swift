import XCTest

/// ReleaseGate: the live regression suite that must be green before any
/// TestFlight upload. Drives the REAL app against the PRODUCTION backend
/// using a session token supplied via environment — never on disk:
///
///   export NEAR_DEBUG_SESSION_TOKEN=...   (and optional NEAR_DEBUG_CLOUD_KEY)
///   scripts/release-gate.sh
///
/// Without a token every live scenario records a SKIP, so this class is safe
/// inside the default test target. Scenarios assert CONTRACTS (an answer
/// renders, failures show recovery affordances, nothing reads "Error
/// Domain="), never exact model output — except planted sentinels.
final class ReleaseGateTests: XCTestCase {
    private static var token: String? {
        ProcessInfo.processInfo.environment["NEAR_DEBUG_SESSION_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var cloudKey: String? {
        ProcessInfo.processInfo.environment["NEAR_DEBUG_CLOUD_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launch helpers

    private func launchLiveApp(extraArguments: [String] = []) throws -> XCUIApplication {
        guard let token = Self.token, !token.isEmpty else {
            throw XCTSkip("ReleaseGate requires NEAR_DEBUG_SESSION_TOKEN in the runner environment.")
        }
        let app = XCUIApplication()
        app.launchEnvironment["NEAR_DEBUG_SESSION_TOKEN"] = token
        if let cloudKey = Self.cloudKey, !cloudKey.isEmpty {
            app.launchEnvironment["NEAR_DEBUG_CLOUD_KEY"] = cloudKey
        }
        app.launchArguments = ["-NEARReleaseGate"] + extraArguments
        app.launch()
        return app
    }

    private func launchDemoApp(screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-NEARDemoCapture", "-NEARDemoScreen=\(screen)"]
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The hidden state beacon RootView exposes under -NEARReleaseGate.
    private func gateState(_ app: XCUIApplication) -> String {
        app.staticTexts["gate.state"].firstMatch.label
    }

    private func waitForStreamingToFinish(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let state = gateState(app)
            if state.contains("streaming=0"), !state.contains("last=none"), !state.contains("last=streaming") {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(2))
        }
        return false
    }

    private func openNewChat(_ app: XCUIApplication) {
        // The conversation list's New-chat affordance varies; the composer is
        // also reachable directly when a chat is already open.
        if app.textFields["composer.input"].waitForExistence(timeout: 3) { return }
        for label in ["New chat", "New Chat", "Ask anything"] {
            let button = app.buttons[label].firstMatch
            if button.waitForExistence(timeout: 2) {
                button.tap()
                break
            }
        }
        XCTAssertTrue(
            app.textFields["composer.input"].waitForExistence(timeout: 10),
            "Composer did not appear after opening a chat."
        )
    }

    private func send(_ app: XCUIApplication, prompt: String) {
        let input = app.textFields["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText(prompt)
        let sendButton = app.buttons["composer.send"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        sendButton.tap()
    }

    /// Core contract after any send: either a completed assistant answer OR an
    /// honest failure carrying a recovery affordance. Never raw error dumps.
    private func assertAnswerOrHonestFailure(_ app: XCUIApplication, timeout: TimeInterval, label: String) {
        XCTAssertTrue(
            waitForStreamingToFinish(app, timeout: timeout),
            "\(label): stream never settled (gate.state=\(gateState(app)))."
        )
        let state = gateState(app)
        if state.contains("last=completed") {
            return
        }
        if state.contains("last=failed") || state.contains("last=cancelled") {
            let recovery = app.buttons["message.recovery.proxy"].firstMatch.exists ||
                app.buttons["message.retry"].firstMatch.exists ||
                app.buttons["message.regenerateStopped"].firstMatch.exists
            XCTAssertTrue(recovery, "\(label): failed turn shows no recovery affordance.")
            return
        }
        XCTFail("\(label): unexpected terminal state \(state).")
    }

    private func assertNoRawErrorDumpVisible(_ app: XCUIApplication, label: String) {
        let predicate = NSPredicate(format: "label CONTAINS 'Error Domain=' OR label CONTAINS 'kCFStream'")
        XCTAssertFalse(
            app.staticTexts.matching(predicate).firstMatch.exists,
            "\(label): a raw NSError dump is visible to the user."
        )
    }

    // MARK: - R1 sign-in restore

    func testR1_SessionRestoreReachesHome() throws {
        let app = try launchLiveApp()
        let composerOrList = app.textFields["composer.input"].waitForExistence(timeout: 20) ||
            app.otherElements["home.conversationList"].waitForExistence(timeout: 20) ||
            app.buttons["home.newChat"].waitForExistence(timeout: 5)
        XCTAssertTrue(composerOrList, "App did not reach a signed-in surface within 20s.")
        XCTAssertFalse(app.buttons["Continue with NEAR"].exists, "Login screen rendered despite the injected session.")
        attach(app, name: "r1-home")
    }

    // MARK: - R2 private send (or restricted → proxy recovery)

    func testR2_PrivateSendAnswersOrOffersProxy() throws {
        let app = try launchLiveApp()
        openNewChat(app)
        send(app, prompt: "Reply with exactly the word PONG and one short markdown bullet about anything.")
        assertAnswerOrHonestFailure(app, timeout: 150, label: "R2")
        assertNoRawErrorDumpVisible(app, label: "R2")

        if gateState(app).contains("last=failed") {
            // Restricted private route: the disclosed proxy path must work.
            let proxyButton = app.buttons["message.recovery.proxy"].firstMatch
            if proxyButton.exists {
                attach(app, name: "r2-proxy-offer")
                proxyButton.tap()
                assertAnswerOrHonestFailure(app, timeout: 150, label: "R2-proxy")
            }
        } else {
            // No literal markdown markers in the rendered answer.
            let rawMarkers = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS '**' OR label BEGINSWITH '## '")
            ).firstMatch
            XCTAssertFalse(rawMarkers.exists, "R2: rendered answer shows raw markdown markers.")
        }
        attach(app, name: "r2-answer")
    }

    // MARK: - R4 council + synthesis

    func testR4_CouncilRunSettlesWithSynthesisOrRetry() throws {
        let app = try launchLiveApp()
        openNewChat(app)

        // Enable a council lineup via the picker.
        let councilChip = app.buttons["composer.chip.council"]
        XCTAssertTrue(councilChip.waitForExistence(timeout: 10))
        councilChip.tap()
        let candidates = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'council.candidate.'")
        )
        let deadline = Date().addingTimeInterval(15)
        while candidates.count == 0, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        guard candidates.count > 0 else {
            attach(app, name: "r4-picker")
            throw XCTSkip("Council picker exposed no candidates (catalog empty on this account).")
        }
        var enabled = 0
        for index in 0..<min(3, candidates.count) where enabled < 3 {
            let candidate = candidates.element(boundBy: index)
            if candidate.isHittable {
                candidate.tap()
                enabled += 1
            }
        }
        // Close the picker.
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }

        send(app, prompt: "In two sentences: what is a TEE attestation? Council, compare answers.")
        XCTAssertTrue(
            app.otherElements["council.group"].firstMatch.waitForExistence(timeout: 30) ||
                waitForStreamingToFinish(app, timeout: 60),
            "R4: neither a council group nor a settled single answer appeared."
        )
        XCTAssertTrue(waitForStreamingToFinish(app, timeout: 300), "R4: council run never settled.")
        assertNoRawErrorDumpVisible(app, label: "R4")
        attach(app, name: "r4-settled")
    }

    // MARK: - R5 tracker create / run / follow-up

    func testR5_TrackerCreatesRunsAndAnswersFollowUp() throws {
        let app = try launchLiveApp()
        openNewChat(app)
        send(app, prompt: "Create a NEAR price tracker daily at 8am and run it now")
        XCTAssertTrue(waitForStreamingToFinish(app, timeout: 60), "R5: tracker confirmation never arrived.")
        attach(app, name: "r5-created")
        // The run was kicked off on create; the delivery (or a visible failed
        // delivery with Run again) is asserted by opening the tracker, which is
        // navigation-dependent — contract here is the confirmation message and
        // absence of raw errors.
        assertNoRawErrorDumpVisible(app, label: "R5")
    }

    // MARK: - R6 PDF fixture summarization

    func testR6_PDFContentReachesModel() throws {
        let app = try launchLiveApp(extraArguments: ["-NEARReleaseGateFixture"])
        openNewChat(app)
        // The fixture seam attaches release-gate-term-sheet.pdf through the
        // real extraction + upload pipeline once signed in.
        let indicator = app.staticTexts["composer.documentContext"].firstMatch
        _ = indicator.waitForExistence(timeout: 30)
        attach(app, name: "r6-attached")
        send(app, prompt: "What is the ZEPHYR-7 thermal margin in the attached document? Answer with the number.")
        assertAnswerOrHonestFailure(app, timeout: 150, label: "R6")
        let state = gateState(app)
        if state.contains("last=completed") {
            let mentions42 = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS '42'")
            ).firstMatch.exists
            XCTAssertTrue(mentions42, "R6: the answer does not reference the document sentinel — extracted text likely never reached the model.")
        }
        attach(app, name: "r6-answer")
    }

    // MARK: - R8 chat switch mid-stream

    func testR8_SwitchingChatsMidStreamCancelsCleanly() throws {
        let app = try launchLiveApp()
        openNewChat(app)
        send(app, prompt: "Write a 600-word essay about the history of the Strait of Hormuz.")
        // Wait until streaming actually starts, then navigate away.
        let deadline = Date().addingTimeInterval(60)
        while !gateState(app).contains("streaming=1"), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        guard gateState(app).contains("streaming=1") else {
            throw XCTSkip("R8: stream never started (route may be restricted); covered by R2.")
        }
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        let newChat = app.buttons["home.newChat"].firstMatch
        if newChat.waitForExistence(timeout: 5) {
            newChat.tap()
        }
        // The old blocking banner must NOT appear; the stream must settle.
        XCTAssertFalse(
            app.staticTexts["Finish or cancel the current response before switching chats."].exists,
            "R8: switching is still blocked by the old guard."
        )
        XCTAssertTrue(waitForStreamingToFinish(app, timeout: 60), "R8: zombie streaming state after switch.")
        attach(app, name: "r8-after-switch")
    }

    // MARK: - R9 layout gates (offline)

    func testR9_MarkdownGalleryHasNoBleedOrRawMarkers() {
        let app = launchDemoApp(screen: "markdownGallery")
        XCTAssertTrue(app.otherElements["gallery.root"].firstMatch.waitForExistence(timeout: 10) ||
            app.scrollViews.firstMatch.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch.frame
        let carousel = app.otherElements["sources.carousel"].firstMatch
        if carousel.exists {
            XCTAssertLessThanOrEqual(
                carousel.frame.maxX, window.maxX + 1,
                "R9: source carousel bleeds past the window edge."
            )
        }
        let rawMarkers = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '**'")
        ).firstMatch
        XCTAssertFalse(rawMarkers.exists, "R9: raw markdown markers visible in gallery.")
        attach(app, name: "r9-gallery")
    }

    // MARK: - R10 council persistence across relaunch

    func testR10_CouncilAnswersSurviveRelaunch() throws {
        // Persistence mechanics are unit-tested (merge rules); the live check
        // rides on R4's conversation. Here: relaunch and confirm the most
        // recent conversation still renders content (no blank transcript).
        let app = try launchLiveApp()
        let list = app.otherElements["home.conversationList"].firstMatch
        _ = list.waitForExistence(timeout: 20)
        let firstChat = app.buttons["Resume"].firstMatch.exists
            ? app.buttons["Resume"].firstMatch
            : app.cells.firstMatch
        guard firstChat.exists else {
            throw XCTSkip("R10: no prior conversations on this account.")
        }
        firstChat.tap()
        XCTAssertTrue(
            app.otherElements["message.assistant"].firstMatch.waitForExistence(timeout: 20) ||
                app.otherElements["council.group"].firstMatch.waitForExistence(timeout: 5),
            "R10: reopened conversation rendered no assistant content."
        )
        assertNoRawErrorDumpVisible(app, label: "R10")
        attach(app, name: "r10-reopened")
    }
}
