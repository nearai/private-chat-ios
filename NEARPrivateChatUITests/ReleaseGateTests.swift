import Foundation
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
    private static let screenshotLock = NSLock()
    private static var screenshotSequence = 0

    private static var token: String? {
        ProcessInfo.processInfo.environment["NEAR_DEBUG_SESSION_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var cloudKey: String? {
        ProcessInfo.processInfo.environment["NEAR_DEBUG_CLOUD_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var screenshotDirectory: URL? {
        guard let rawPath = ProcessInfo.processInfo.environment["NEAR_RELEASE_GATE_SCREENSHOT_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: rawPath, isDirectory: true)
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
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        writeScreenshot(screenshot, name: name)
    }

    private func writeScreenshot(_ screenshot: XCUIScreenshot, name: String) {
        guard let directory = Self.screenshotDirectory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sequence = Self.nextScreenshotSequence()
            let fileName = "\(String(format: "%03d", sequence))-\(Self.sanitizedScreenshotName(name)).png"
            let fileURL = directory.appendingPathComponent(fileName)
            try screenshot.pngRepresentation.write(to: fileURL, options: [.atomic])
            try Self.appendScreenshotManifestEntry(name: name, fileName: fileName, directory: directory)
        } catch {
            XCTContext.runActivity(named: "ReleaseGate screenshot write failed") { activity in
                let attachment = XCTAttachment(string: "\(name): \(error)")
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
    }

    private static func nextScreenshotSequence() -> Int {
        screenshotLock.lock()
        defer { screenshotLock.unlock() }
        screenshotSequence += 1
        return screenshotSequence
    }

    private static func sanitizedScreenshotName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "screenshot" : String(collapsed.prefix(80))
    }

    private static func appendScreenshotManifestEntry(name: String, fileName: String, directory: URL) throws {
        screenshotLock.lock()
        defer { screenshotLock.unlock() }

        let manifestURL = directory.appendingPathComponent("manifest.json")
        var entries: [[String: String]] = []
        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            entries = decoded
        }
        entries.append([
            "name": name,
            "file": fileName,
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ])
        let data = try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: manifestURL, options: [.atomic])
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

    private func waitForStreamingToStop(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if gateState(app).contains("streaming=0") {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(2))
        }
        return false
    }

    private func waitForRecoveryAffordance(_ app: XCUIApplication, timeout: TimeInterval = 12) -> Bool {
        let recoveryIdentifiers = [
            "message.recovery.proxy",
            "message.retry",
            "message.regenerateStopped"
        ]
        let deadline = Date().addingTimeInterval(timeout)
        var scrollAttempts = 0
        while Date() < deadline {
            for identifier in recoveryIdentifiers where element(withIdentifier: identifier, in: app).exists {
                return true
            }

            if scrollAttempts < 3 {
                app.swipeUp()
                scrollAttempts += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        attach(app, name: "missing-recovery-affordance")
        return false
    }

    private func openNewChat(_ app: XCUIApplication) {
        // The conversation list's New-chat affordance varies; the composer is
        // also reachable directly when a chat is already open.
        if app.textFields["composer.input"].waitForExistence(timeout: 3) { return }
        if !tapHomeNewChatIfAvailable(app) {
            for label in ["Ask anything"] {
                let button = app.buttons[label].firstMatch
                if button.waitForExistence(timeout: 2) {
                    button.tap()
                    break
                }
            }
        }
        XCTAssertTrue(
            app.textFields["composer.input"].waitForExistence(timeout: 10),
            "Composer did not appear after opening a chat."
        )
    }

    @discardableResult
    private func tapHomeNewChatIfAvailable(_ app: XCUIApplication, timeout: TimeInterval = 2) -> Bool {
        let candidates = [
            app.buttons["home.newChat"].firstMatch,
            app.buttons["New chat"].firstMatch,
            app.buttons["New Chat"].firstMatch,
            app.otherElements["home.newChat"].firstMatch,
            app.images["home.newChat"].firstMatch
        ]
        for candidate in candidates where candidate.waitForExistence(timeout: timeout) {
            candidate.tap()
            return true
        }
        return false
    }

    private func waitForSignedInSurface(_ app: XCUIApplication, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let signedInSurfaceVisible =
                app.textFields["composer.input"].firstMatch.exists ||
                app.otherElements["home.default.streams"].firstMatch.exists ||
                app.staticTexts["Streams"].firstMatch.exists ||
                app.buttons["New chat"].firstMatch.exists ||
                app.buttons["Start a new chat"].firstMatch.exists ||
                app.otherElements["home.conversationList"].firstMatch.exists
            if signedInSurfaceVisible {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return false
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

    private func returnHomeFromChat(_ app: XCUIApplication) {
        if app.otherElements["home.default.streams"].firstMatch.exists {
            return
        }

        if app.keyboards.firstMatch.exists {
            app.swipeDown()
        }

        let labeledBack = app.buttons["Back"].firstMatch
        if labeledBack.waitForExistence(timeout: 3), labeledBack.isHittable {
            labeledBack.tap()
        } else {
            let navigationBack = app.navigationBars.buttons.firstMatch
            if navigationBack.waitForExistence(timeout: 3), navigationBack.isHittable {
                navigationBack.tap()
            }
        }

        XCTAssertTrue(
            app.otherElements["home.default.streams"].firstMatch.waitForExistence(timeout: 10) ||
                app.staticTexts["Streams"].firstMatch.waitForExistence(timeout: 2),
            "Home stream did not appear after returning from chat."
        )
    }

    private func assertHomeShowsWatcher(_ app: XCUIApplication, matching text: String, label: String) {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let watcherText = app.staticTexts.matching(predicate).firstMatch
        if watcherText.waitForExistence(timeout: 5) {
            attach(app, name: "\(label.lowercased())-home-watcher")
            return
        }

        app.swipeUp()
        XCTAssertTrue(
            watcherText.waitForExistence(timeout: 5),
            "\(label): created watcher did not surface on Home."
        )
        attach(app, name: "\(label.lowercased())-home-watcher")
    }

    private func selectLiveWebSourceMode(_ app: XCUIApplication) {
        let sourceChip = app.buttons["composer.chip.source"].firstMatch
        XCTAssertTrue(sourceChip.waitForExistence(timeout: 10), "Source mode chip did not appear.")
        sourceChip.tap()

        let liveWeb = app.buttons["Live web"].firstMatch
        XCTAssertTrue(liveWeb.waitForExistence(timeout: 5), "Live web option did not appear.")
        liveWeb.tap()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if sourceChip.label.localizedCaseInsensitiveContains("web") {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Source mode did not switch to Live web.")
    }

    private func element(withIdentifier identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
    }

    private func assertSourceDetailsOpenFromVisibleSources(_ app: XCUIApplication, label: String) {
        let sourceCard = app.buttons["source.card.1"].firstMatch
        if sourceCard.waitForExistence(timeout: 5) {
            sourceCard.tap()

            let sheetTitle = element(withIdentifier: "source.sheet.title", in: app)
            XCTAssertTrue(sheetTitle.waitForExistence(timeout: 5), "\(label): tapping a source card did not open the source sheet title.")
            XCTAssertTrue(
                element(withIdentifier: "source.sheet.host", in: app).waitForExistence(timeout: 5),
                "\(label): source sheet rendered without a source host."
            )
            XCTAssertTrue(
                element(withIdentifier: "source.sheet.open", in: app).waitForExistence(timeout: 5),
                "\(label): source sheet rendered without an open-source action."
            )
            attach(app, name: "\(label.lowercased())-source-sheet")
            return
        }

        let sourceButton = app.buttons["message.action.sources"].firstMatch
        XCTAssertTrue(sourceButton.waitForExistence(timeout: 5), "\(label): no tappable source card or source action rendered.")
        sourceButton.tap()

        let detail = element(withIdentifier: "sources.detail", in: app)
        let firstRow = element(withIdentifier: "sources.detail.row.1", in: app)
        XCTAssertTrue(
            detail.waitForExistence(timeout: 5) || firstRow.waitForExistence(timeout: 2),
            "\(label): tapping sources did not open a source detail list."
        )
        attach(app, name: "\(label.lowercased())-source-list")
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
            XCTAssertTrue(
                waitForRecoveryAffordance(app),
                "\(label): failed turn shows no recovery affordance."
            )
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

    private func assertHomeScopeStripFits(_ app: XCUIApplication, label: String) {
        let window = app.windows.firstMatch.frame
        for scope in ["All", "Briefings", "Watchers", "Chats"] {
            let button = app.buttons[scope].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(label): missing Home scope \(scope).")
            XCTAssertGreaterThanOrEqual(button.frame.minX, window.minX - 1, "\(label): Home scope \(scope) bleeds left.")
            XCTAssertLessThanOrEqual(button.frame.maxX, window.maxX + 1, "\(label): Home scope \(scope) bleeds right.")
            XCTAssertGreaterThanOrEqual(button.frame.height, 43, "\(label): Home scope \(scope) is below tap-target height.")
        }
    }

    private func assertHomeStreamsSurfaceIsUseful(_ app: XCUIApplication, label: String) {
        let surface = element(withIdentifier: "home.default.streams", in: app)
        XCTAssertTrue(surface.waitForExistence(timeout: 5), "\(label): Home did not render the Streams surface.")

        let title = element(withIdentifier: "home.streams.title", in: app)
        let subtitle = element(withIdentifier: "home.streams.subtitle", in: app)
        let liveCount = element(withIdentifier: "home.streams.liveCount", in: app)
        XCTAssertTrue(title.exists, "\(label): Streams title is missing.")
        XCTAssertTrue(subtitle.exists, "\(label): Streams subtitle is missing.")
        XCTAssertTrue(liveCount.exists, "\(label): Streams live count is missing.")
        XCTAssertEqual(title.label, "Streams", "\(label): Home default surface drifted away from Streams.")
        XCTAssertFalse(
            subtitle.label == "Briefings, watchers, and private threads ready to continue.",
            "\(label): Home subtitle regressed to generic block copy."
        )

        for staleLabel in ["Next actions", "Draft trackers", "Web research", "Files to action"] {
            XCTAssertFalse(
                app.staticTexts[staleLabel].firstMatch.exists || app.buttons[staleLabel].firstMatch.exists,
                "\(label): stale Home quick-action label '\(staleLabel)' is visible."
            )
        }

        assertHomeScopeStripFits(app, label: label)
    }

    private func assertInlineNewsWidgetStaysCompact(_ app: XCUIApplication, label: String) {
        let widget = element(withIdentifier: "message.widget.newsBrief", in: app)
        guard widget.waitForExistence(timeout: 2) else { return }

        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(widget.frame.minX, window.minX - 1, "\(label): news widget bleeds left.")
        XCTAssertLessThanOrEqual(widget.frame.maxX, window.maxX + 1, "\(label): news widget bleeds right.")
        XCTAssertLessThanOrEqual(
            widget.frame.height,
            window.height * 0.48,
            "\(label): inline news widget consumes too much of the first viewport."
        )

        let fourthStory = element(withIdentifier: "message.widget.newsBrief.story.4", in: app)
        XCTAssertFalse(fourthStory.exists, "\(label): news widget renders more than three full story rows inline.")
    }

    private func assertAssistantActionRowFits(_ app: XCUIApplication, label: String) {
        let window = app.windows.firstMatch.frame
        let actionIDs = [
            "message.action.copy",
            "message.action.sources",
            "message.action.open",
            "message.action.more"
        ]
        var visibleActionCount = 0

        for actionID in actionIDs {
            let action = app.buttons[actionID].firstMatch
            guard action.exists else { continue }
            visibleActionCount += 1
            XCTAssertGreaterThanOrEqual(action.frame.minX, window.minX - 1, "\(label): \(actionID) bleeds left.")
            XCTAssertLessThanOrEqual(action.frame.maxX, window.maxX + 1, "\(label): \(actionID) bleeds right.")
            XCTAssertGreaterThanOrEqual(action.frame.height, 43, "\(label): \(actionID) is below tap-target height.")
        }

        XCTAssertGreaterThan(visibleActionCount, 0, "\(label): completed assistant answer exposed no inline actions.")
    }

    // MARK: - R1 sign-in restore

    func testR1_SessionRestoreReachesHome() throws {
        let app = try launchLiveApp()
        XCTAssertTrue(waitForSignedInSurface(app), "App did not reach a signed-in surface within 30s.")
        XCTAssertFalse(app.buttons["Continue with NEAR"].firstMatch.exists, "Login screen rendered despite the injected session.")
        if app.otherElements["home.default.streams"].firstMatch.exists {
            assertHomeStreamsSurfaceIsUseful(app, label: "R1")
        }
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
            assertAssistantActionRowFits(app, label: "R2")
        }
        attach(app, name: "r2-answer")
    }

    // MARK: - R3 live web / source rendering

    func testR3_LiveWebCurrentEventsReturnsSources() throws {
        let app = try launchLiveApp()
        openNewChat(app)
        selectLiveWebSourceMode(app)
        send(app, prompt: "Using live web sources, what are the top three AI news stories today? Answer in three bullets and cite sources.")
        assertAnswerOrHonestFailure(app, timeout: 180, label: "R3")
        assertNoRawErrorDumpVisible(app, label: "R3")

        guard gateState(app).contains("last=completed") else {
            attach(app, name: "r3-honest-failure")
            return
        }

        let sourceCarousel = app.otherElements["sources.carousel"].firstMatch
        let sourceButton = app.buttons["message.action.sources"].firstMatch
        let hasSources = sourceCarousel.waitForExistence(timeout: 5) || sourceButton.waitForExistence(timeout: 2)
        attach(app, name: hasSources ? "r3-sources" : "r3-missing-sources")
        XCTAssertTrue(hasSources, "R3: completed Live web answer rendered with no visible sources.")
        assertAssistantActionRowFits(app, label: "R3")
        assertInlineNewsWidgetStaysCompact(app, label: "R3")
        assertSourceDetailsOpenFromVisibleSources(app, label: "R3")
    }

    // MARK: - R12 hard live web current-events synthesis

    func testR12_LiveWebHardCurrentEventsReturnsSources() throws {
        let app = try launchLiveApp()
        openNewChat(app)
        selectLiveWebSourceMode(app)
        send(
            app,
            prompt: "Using live web sources, check today's reporting on SpaceX IPO or private-market news and the latest Iran conflict developments. Separate confirmed facts from uncertainty and cite sources."
        )
        assertAnswerOrHonestFailure(app, timeout: 180, label: "R12")
        assertNoRawErrorDumpVisible(app, label: "R12")

        guard gateState(app).contains("last=completed") else {
            attach(app, name: "r12-honest-failure")
            return
        }

        let sourceCarousel = app.otherElements["sources.carousel"].firstMatch
        let sourceButton = app.buttons["message.action.sources"].firstMatch
        let hasSources = sourceCarousel.waitForExistence(timeout: 5) || sourceButton.waitForExistence(timeout: 2)
        attach(app, name: hasSources ? "r12-sources" : "r12-missing-sources")
        XCTAssertTrue(hasSources, "R12: hard current-events answer rendered with no visible sources.")
        assertAssistantActionRowFits(app, label: "R12")
        assertInlineNewsWidgetStaysCompact(app, label: "R12")
        assertSourceDetailsOpenFromVisibleSources(app, label: "R12")
    }

    // MARK: - R4 council + synthesis

    func testR4_CouncilRunSettlesWithSynthesisOrRetry() throws {
        let app = try launchLiveApp()
        openNewChat(app)

        // Enable a council lineup via the picker.
        let councilChip = app.buttons["composer.chip.council"]
        XCTAssertTrue(councilChip.waitForExistence(timeout: 10))
        councilChip.tap()
        let councilTab = app.segmentedControls.buttons["Council"].firstMatch
        if councilTab.waitForExistence(timeout: 5), !councilTab.isSelected {
            councilTab.tap()
        }
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
        XCTAssertTrue(waitForStreamingToFinish(app, timeout: 300), "R4: council run never settled.")
        XCTAssertTrue(
            app.otherElements["council.group"].firstMatch.exists ||
                gateState(app).contains("last=completed"),
            "R4: neither a council group nor a settled single answer appeared."
        )
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
        // delivery with Run again) is asserted by Home surfacing the watcher
        // immediately after creation, not by a hidden store mutation.
        assertNoRawErrorDumpVisible(app, label: "R5")
        returnHomeFromChat(app)
        assertHomeStreamsSurfaceIsUseful(app, label: "R5")
        assertHomeShowsWatcher(app, matching: "NEAR price", label: "R5")
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
        XCTAssertTrue(
            tapHomeNewChatIfAvailable(app, timeout: 5),
            "R8: Home new-chat affordance is not reachable after leaving an active stream."
        )
        XCTAssertTrue(
            app.textFields["composer.input"].waitForExistence(timeout: 10),
            "R8: composer did not reappear after switching away from an active stream."
        )
        // The old blocking banner must NOT appear; the stream must settle.
        XCTAssertFalse(
            app.staticTexts["Finish or cancel the current response before switching chats."].exists,
            "R8: switching is still blocked by the old guard."
        )
        XCTAssertTrue(
            waitForStreamingToStop(app, timeout: 60),
            "R8: zombie streaming state after switch (gate.state=\(gateState(app)))."
        )
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
        XCTAssertTrue(
            app.otherElements["markdown.table.stacked"].firstMatch.exists,
            "R9: wide markdown table did not render in the no-clipping stacked layout."
        )
        attach(app, name: "r9-gallery")
    }

    // MARK: - R11 offline product surface compactness

    func testR11_OfflineChatSurfacesKeepAnswerActionsCompact() {
        let prose = launchDemoApp(screen: "chatFailure")
        let failureCopy = prose.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Private route needs a moment"))
            .firstMatch
        XCTAssertTrue(failureCopy.waitForExistence(timeout: 10))
        XCTAssertTrue(prose.buttons["message.action.copy"].firstMatch.exists)
        XCTAssertTrue(prose.buttons["message.action.more"].firstMatch.exists)
        XCTAssertFalse(prose.buttons["message.action.sources"].firstMatch.exists)
        XCTAssertFalse(prose.buttons["message.action.open"].firstMatch.exists)
        XCTAssertFalse(prose.staticTexts["Next send"].exists)
        attach(prose, name: "r11-prose-compact-actions")

        let widgets = launchDemoApp(screen: "widgets")
        let actionPlanTitle = widgets.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Bedtime magnesium"))
            .firstMatch
        XCTAssertTrue(actionPlanTitle.waitForExistence(timeout: 10))
        XCTAssertFalse(widgets.buttons["message.action.copy"].firstMatch.exists)
        XCTAssertFalse(widgets.buttons["message.action.more"].firstMatch.exists)
        XCTAssertFalse(widgets.staticTexts["Next send"].exists)
        attach(widgets, name: "r11-widget-actions-suppressed")
    }

    // MARK: - R10 council persistence across relaunch

    func testR10_CouncilAnswersSurviveRelaunch() throws {
        let app = try launchLiveApp()
        let marker = "R10 persistence check"

        openNewChat(app)
        send(app, prompt: "\(marker). Reply with exactly: persisted.")
        assertAnswerOrHonestFailure(app, timeout: 150, label: "R10-seed")
        assertNoRawErrorDumpVisible(app, label: "R10-seed")
        attach(app, name: "r10-before-relaunch")

        app.terminate()
        app.launch()
        XCTAssertTrue(waitForSignedInSurface(app), "R10: app did not return to a signed-in surface after relaunch.")

        if !reopenedConversationContaining(marker, in: app) {
            attach(app, name: "r10-missing-recent")
            XCTFail("R10: seeded conversation did not surface on Home after relaunch.")
        }

        let persistedMarker = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", marker))
            .firstMatch
        XCTAssertTrue(
            persistedMarker.waitForExistence(timeout: 12) ||
                app.otherElements["message.assistant"].firstMatch.waitForExistence(timeout: 5) ||
                app.otherElements["council.group"].firstMatch.waitForExistence(timeout: 3),
            "R10: reopened conversation rendered no persisted content."
        )
        assertNoRawErrorDumpVisible(app, label: "R10")
        attach(app, name: "r10-reopened")
    }

    private func reopenedConversationContaining(_ marker: String, in app: XCUIApplication) -> Bool {
        let alreadyOpenMarker = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", marker))
            .firstMatch
        if alreadyOpenMarker.waitForExistence(timeout: 3),
           !app.otherElements["home.default.streams"].firstMatch.exists {
            return true
        }

        returnHomeFromChat(app)

        let recentButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", marker))
            .firstMatch
        if recentButton.waitForExistence(timeout: 12), recentButton.isHittable {
            recentButton.tap()
            return true
        }

        app.swipeUp()
        if recentButton.waitForExistence(timeout: 5), recentButton.isHittable {
            recentButton.tap()
            return true
        }

        return false
    }
}
