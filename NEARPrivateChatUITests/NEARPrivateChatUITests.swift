import XCTest

final class NEARPrivateChatUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNewChatDemoShowsPrivateRouteAndActionChips() throws {
        let app = launchDemo(screen: "chatStarters")

        XCTAssertTrue(app.staticTexts["New chat"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["What do you want to ask?"].exists)
        XCTAssertTrue(app.buttons["Ask"].exists || app.staticTexts["Ask"].exists)
        XCTAssertTrue(app.buttons["Use files"].exists || app.staticTexts["Use files"].exists)
        XCTAssertTrue(app.buttons["Model GLM 5.1"].exists || app.staticTexts["GLM 5.1"].exists)
        XCTAssertTrue(app.buttons["Configure LLM Council"].exists || app.staticTexts["Council"].exists)
        XCTAssertTrue(app.buttons["Source mode Auto"].exists || app.staticTexts["Auto"].exists)
        XCTAssertFalse(app.staticTexts["Private chat · sources stay explicit"].exists)
        XCTAssertFalse(app.staticTexts["Council route"].exists)
    }

    func testModelPickerDemoShowsRealModelNames() throws {
        let app = launchDemo(screen: "models")

        XCTAssertTrue(app.staticTexts["Model"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["GLM 5.1"].exists)
        XCTAssertTrue(button(containing: "GLM 5.1", in: app).exists)
        XCTAssertFalse(app.staticTexts["NEAR Private model"].exists)
        XCTAssertFalse(app.staticTexts["NEAR AI Cloud model A"].exists)
        XCTAssertFalse(app.staticTexts["Private reasoning model A"].exists)
        XCTAssertFalse(app.staticTexts["Private reasoning model B"].exists)
        for banned in [
            "GPT OSS 120B",
            "OpenAI GPT-4.1",
            "GPT 4.1",
            "OpenAI o3",
            "O3",
            "OpenAI o4 Mini",
            "O4 Mini",
            "Gemini 2.5 Pro",
            "GLM-5.1-FP8",
            "Claude Opus 4.7",
            "GPT-5.5",
            "Qwen3.7 Max"
        ] {
            XCTAssertFalse(app.staticTexts[banned].exists, "Stale model name rendered: \(banned)")
        }
    }

    func testModelPickerCanSelectCloudRouteDistinctFromPrivate() throws {
        let app = launchDemo(screen: "models")

        XCTAssertTrue(app.staticTexts["Model"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Private is the default route. Cloud routes use your NEAR AI Cloud key when connected."].exists)
        XCTAssertFalse(app.staticTexts["Private is always available. Cloud routes need a NEAR AI Cloud key."].exists)

        let privateRow = button(containing: "GLM 5.1", in: app)
        XCTAssertTrue(privateRow.exists)
        XCTAssertTrue(privateRow.label.contains("Current"))

        let cloudRow = button(containing: "Claude Sonnet 4.6", in: app)
        XCTAssertTrue(cloudRow.exists)
        cloudRow.tap()

        XCTAssertTrue(cloudRow.label.contains("Current"))
        XCTAssertFalse(privateRow.label.contains("Current"))
    }

    func testCouncilPickerDemoShowsPrivateAndCloudCouncilChoices() throws {
        let app = launchDemo(screen: "council")

        XCTAssertTrue(app.staticTexts["Council"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["CHOOSE COUNCIL MODELS"].exists)
        XCTAssertTrue(app.staticTexts["NEAR PRIVATE COUNCIL MODELS"].exists)
        XCTAssertTrue(app.staticTexts["NEAR AI CLOUD COUNCIL MODELS"].exists)
        XCTAssertTrue(button(containing: "GLM 5.1", in: app).exists)
        XCTAssertTrue(button(containing: "Claude Sonnet 4.6", in: app).exists)
        XCTAssertTrue(button(containing: "Claude Opus 4.6", in: app).exists)
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(button(containing: "Qwen 3.6", in: app).exists)
        XCTAssertFalse(app.staticTexts["NEAR Private model"].exists)
        XCTAssertFalse(app.staticTexts["NEAR AI Cloud model A"].exists)
        XCTAssertFalse(app.staticTexts["NEAR AI Cloud model B"].exists)
        XCTAssertFalse(button(containing: "Qwen3.7 Max", in: app).exists)
    }

    func testNearCloudDemoUsesExplicitCloudModelNames() throws {
        let app = launchDemo(screen: "cloudModels")

        XCTAssertTrue(app.staticTexts["NEAR AI Cloud"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Claude Sonnet 4.6"].exists)
        XCTAssertTrue(app.staticTexts["Claude Opus 4.6"].exists)
        XCTAssertTrue(app.staticTexts["Qwen 3.6 35B A3B FP8"].exists)
        XCTAssertTrue(app.staticTexts["Qwen 3.6 27B FP8"].exists)
        XCTAssertFalse(app.staticTexts["GPT OSS 120B"].exists)
        XCTAssertFalse(app.staticTexts["Gemini 2.5 Pro"].exists)
        XCTAssertFalse(app.staticTexts["GPT 4.1"].exists)
        XCTAssertFalse(app.staticTexts["O3"].exists)
        XCTAssertFalse(app.staticTexts["O4 Mini"].exists)
        XCTAssertFalse(app.staticTexts["Claude Opus 4.7"].exists)
        XCTAssertFalse(app.staticTexts["GPT-5.5"].exists)
        XCTAssertFalse(app.staticTexts["Qwen3.7 Max"].exists)
        XCTAssertTrue(app.staticTexts["Anthropic long-context model through the NEAR AI Cloud privacy proxy."].exists)
        XCTAssertTrue(app.staticTexts["Anthropic coding and agent model through the NEAR AI Cloud privacy proxy."].exists)
        XCTAssertTrue(app.staticTexts["Qwen reasoning model through the NEAR AI Cloud privacy proxy."].exists)
        XCTAssertFalse(app.staticTexts["Independent model A"].exists)
        XCTAssertFalse(app.staticTexts["Independent model B"].exists)
        XCTAssertFalse(app.staticTexts["NEAR AI Cloud model A"].exists)
        XCTAssertFalse(app.staticTexts["NEAR AI Cloud model B"].exists)
        XCTAssertFalse(app.staticTexts["Cloud model through NEAR Cloud privacy proxy."].exists)
    }

    func testHomeDemoPromptCaptureKeepsProjectContextReadable() throws {
        let app = launchDemo(screen: "home")

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["All"].exists || app.staticTexts["All"].exists)
        XCTAssertTrue(app.buttons["Briefings"].exists || app.staticTexts["Briefings"].exists)
        XCTAssertTrue(app.buttons["Watchers"].exists || app.staticTexts["Watchers"].exists)
        XCTAssertTrue(app.buttons["Chats"].exists || app.staticTexts["Chats"].exists)
        XCTAssertTrue(app.textFields["Ask privately."].exists || app.staticTexts["Ask privately."].exists)
        XCTAssertTrue(app.staticTexts["IronClaw Reborn Plan context active"].exists || app.staticTexts["IronClaw Reborn Plan"].exists)
        XCTAssertFalse(app.staticTexts["Add prompt first"].exists)
        XCTAssertFalse(app.staticTexts["Project context loaded. Council and Agent routes ready."].exists)
        XCTAssertFalse(app.staticTexts["Project context loaded. Agent route ready."].exists)
        XCTAssertFalse(app.staticTexts["1 Project / Council / Agent"].exists)
        XCTAssertFalse(app.staticTexts["Type to prepare"].exists)
        XCTAssertFalse(app.staticTexts["1 model selected"].exists)
        XCTAssertFalse(app.staticTexts["Enable the default multi-model lineup."].exists)
        XCTAssertFalse(app.buttons["Show All"].exists)
        XCTAssertFalse(app.buttons["Show Workflows"].exists)
        XCTAssertFalse(app.buttons["Show Agents"].exists)
        XCTAssertFalse(app.buttons["Show Projects"].exists)
        XCTAssertFalse(app.buttons["Brief project"].exists)
        XCTAssertFalse(app.buttons["Context to actions"].exists)
        XCTAssertFalse(app.buttons["Draft trackers"].exists)
        XCTAssertFalse(app.buttons["Sources & proof"].exists)
        XCTAssertFalse(app.buttons["More home actions"].exists)
    }

    func testHomeDemoDefaultSurfaceStaysStreamFocused() throws {
        let app = launchDemo(screen: "home")

        XCTAssertTrue(app.staticTexts["Streams"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["home.default.streams"].exists)
        // The scope strip renders one filter chip per scope (Briefings / Watchers
        // / Chats), each a button whose accessibility label is the full scope
        // title. Cards use singular type prefixes ("Briefing ·", "Watcher ·",
        // "Answer ·"), so the chip is the reliable per-scope button.
        XCTAssertGreaterThanOrEqual(buttonCount(containing: "Chats", in: app), 1)
        XCTAssertGreaterThanOrEqual(buttonCount(containing: "Briefings", in: app), 1)
        XCTAssertGreaterThanOrEqual(buttonCount(containing: "Watchers", in: app), 1)
        // Stream-focused means actual feed cards are present (each card label
        // carries a " · " metadata separator), not an empty or expanded surface.
        XCTAssertGreaterThanOrEqual(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " · ")).count,
            2
        )
        XCTAssertTrue(app.buttons["Briefings"].exists || app.staticTexts["Briefings"].exists)
        XCTAssertTrue(app.buttons["Watchers"].exists || app.staticTexts["Watchers"].exists)
        XCTAssertTrue(app.buttons["Chats"].exists || app.staticTexts["Chats"].exists)
        XCTAssertFalse(app.staticTexts["Projects"].exists)
        XCTAssertFalse(app.staticTexts["Project matches"].exists)
        XCTAssertFalse(app.staticTexts["Chat history"].exists)
        XCTAssertFalse(app.staticTexts["Shared With Me"].exists)
        XCTAssertFalse(app.staticTexts["Archived chats"].exists)
        XCTAssertFalse(app.staticTexts["Archived projects"].exists)
    }

    func testReasoningEffortSheetUsesGroupedControls() throws {
        let app = launchDemo(screen: "chatStarters")

        XCTAssertTrue(app.staticTexts["New chat"].waitForExistence(timeout: 8))
        let reasoningButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reasoning effort")).firstMatch
        XCTAssertTrue(reasoningButton.waitForExistence(timeout: 4))
        reasoningButton.tap()

        XCTAssertTrue(app.staticTexts["Reasoning effort"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Current: Auto"].exists)
        XCTAssertTrue(app.buttons["reasoning.effort.automatic"].exists)
        XCTAssertTrue(app.buttons["reasoning.effort.low"].exists)
        XCTAssertTrue(app.buttons["reasoning.effort.medium"].exists)
        XCTAssertTrue(app.buttons["reasoning.effort.high"].exists)
        XCTAssertTrue(app.buttons["reasoning.advanced-settings"].exists)
        XCTAssertFalse(app.buttons["Auto effort"].exists)
    }

    func testPrivateRouteFailureKeepsRetryPrimaryAndProxySecondary() throws {
        let app = launchDemo(screen: "chatFailure")

        let failureCopy = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Private route needs a moment"))
            .firstMatch
        XCTAssertTrue(failureCopy.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Retry private when the route cools down")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Retry private"].exists)
        XCTAssertFalse(app.buttons["Use privacy proxy"].exists)
        XCTAssertFalse(app.buttons["Use proxy once"].exists)
        XCTAssertTrue(app.buttons["Add Cloud key"].exists || app.buttons["Use Cloud once"].exists)
    }

    private func launchDemo(screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-NEARDemoCapture",
            "-NEARDemoScreen=\(screen)"
        ]
        app.launch()
        return app
    }

    private func button(containing label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    private func buttonCount(containing label: String, in app: XCUIApplication) -> Int {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).count
    }
}
