import XCTest

final class NEARPrivateChatUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNewChatDemoShowsPrivateRouteAndActionChips() throws {
        let app = launchDemo(screen: "chatStarters")

        XCTAssertTrue(app.staticTexts["New chat"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["NEAR Private"].exists)
        XCTAssertTrue(app.staticTexts["What do you want to ask?"].exists)
        XCTAssertTrue(app.staticTexts["Sources as needed"].exists)
        XCTAssertTrue(app.staticTexts["Agent tools"].exists)
        XCTAssertTrue(app.buttons["Next actions"].exists || app.staticTexts["Next actions"].exists)
        XCTAssertTrue(app.buttons["Files to actions"].exists || app.staticTexts["Files to actions"].exists)
        XCTAssertTrue(app.buttons["Model GLM 5.1"].exists || app.staticTexts["GLM 5.1"].exists)
        XCTAssertTrue(app.buttons["Configure LLM Council"].exists || app.staticTexts["Council"].exists)
        XCTAssertTrue(app.buttons["Source mode Source"].exists || app.staticTexts["Source"].exists)
    }

    func testModelPickerDemoShowsRealModelNames() throws {
        let app = launchDemo(screen: "models")

        XCTAssertTrue(app.staticTexts["Model"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["SINGLE MODEL ROUTE"].exists)
        XCTAssertTrue(app.staticTexts["GLM 5.1"].exists)
        XCTAssertTrue(app.staticTexts["Claude Opus 4.7"].exists)
        XCTAssertTrue(app.staticTexts["GPT-5.5"].exists)
        XCTAssertTrue(app.staticTexts["Qwen3.7 Max"].exists)
        XCTAssertTrue(app.staticTexts["DeepSeek V4 Flash"].exists)
        XCTAssertTrue(app.staticTexts["Qwen3.5 122B A10B"].exists)
        XCTAssertTrue(button(containing: "GLM 5.1", in: app).exists)
        XCTAssertTrue(button(containing: "DeepSeek V4 Flash", in: app).exists)
        XCTAssertTrue(button(containing: "Claude Opus 4.7", in: app).exists)
        XCTAssertTrue(button(containing: "GPT-5.5", in: app).exists)
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
            "GLM-5.1-FP8"
        ] {
            XCTAssertFalse(app.staticTexts[banned].exists, "Stale model name rendered: \(banned)")
        }
    }

    func testCouncilPickerDemoShowsPrivateAndCloudCouncilChoices() throws {
        let app = launchDemo(screen: "council")

        XCTAssertTrue(app.staticTexts["Council"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["CHOOSE COUNCIL MODELS"].exists)
        XCTAssertTrue(app.staticTexts["NEAR PRIVATE COUNCIL MODELS"].exists)
        XCTAssertTrue(app.staticTexts["NEAR AI CLOUD COUNCIL MODELS"].exists)
        XCTAssertTrue(button(containing: "GLM 5.1", in: app).exists)
        XCTAssertTrue(button(containing: "DeepSeek V4 Flash", in: app).exists)
        XCTAssertTrue(button(containing: "Claude Opus 4.7", in: app).exists)
        XCTAssertTrue(button(containing: "GPT-5.5", in: app).exists)
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(button(containing: "Qwen3.7 Max", in: app).exists)
        XCTAssertFalse(app.staticTexts["NEAR Private model"].exists)
        XCTAssertFalse(app.staticTexts["NEAR AI Cloud model A"].exists)
        XCTAssertFalse(app.staticTexts["NEAR AI Cloud model B"].exists)
    }

    func testNearCloudDemoUsesExplicitCloudModelNames() throws {
        let app = launchDemo(screen: "cloudModels")

        XCTAssertTrue(app.staticTexts["NEAR AI Cloud"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Claude Opus 4.7"].exists)
        XCTAssertTrue(app.staticTexts["GPT-5.5"].exists)
        XCTAssertTrue(app.staticTexts["Qwen3.7 Max"].exists)
        XCTAssertTrue(app.staticTexts["Kimi K2.6"].exists)
        XCTAssertTrue(app.staticTexts["Claude Sonnet 4.6"].exists)
        XCTAssertTrue(app.staticTexts["Claude Opus 4.6"].exists)
        XCTAssertFalse(app.staticTexts["GPT OSS 120B"].exists)
        XCTAssertFalse(app.staticTexts["Gemini 2.5 Pro"].exists)
        XCTAssertFalse(app.staticTexts["GPT 4.1"].exists)
        XCTAssertFalse(app.staticTexts["O3"].exists)
        XCTAssertFalse(app.staticTexts["O4 Mini"].exists)
        XCTAssertTrue(app.staticTexts["Frontier OpenAI model through the NEAR AI Cloud privacy proxy."].exists)
        XCTAssertTrue(app.staticTexts["Frontier Anthropic model through the NEAR AI Cloud privacy proxy."].exists)
        XCTAssertTrue(app.staticTexts["Current Qwen frontier model through the NEAR AI Cloud privacy proxy."].exists)
        XCTAssertFalse(app.staticTexts["Independent model A"].exists)
        XCTAssertFalse(app.staticTexts["Independent model B"].exists)
        XCTAssertFalse(app.staticTexts["NEAR AI Cloud model A"].exists)
        XCTAssertFalse(app.staticTexts["NEAR AI Cloud model B"].exists)
        XCTAssertFalse(app.staticTexts["Cloud model through NEAR Cloud privacy proxy."].exists)
    }

    func testHomeDemoPromptCaptureKeepsProjectContextReadable() throws {
        let app = launchDemo(screen: "home")

        XCTAssertTrue(app.staticTexts["Start from one prompt"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["IronClaw Reborn Plan context is active. Ask, research, prove, or hand off."].exists)
        XCTAssertTrue(app.staticTexts["IronClaw Reborn Plan context active"].exists || app.staticTexts["IronClaw Reborn Plan"].exists)
        XCTAssertTrue(app.staticTexts["Add prompt first"].exists)
        XCTAssertFalse(app.staticTexts["Type to prepare"].exists)
        XCTAssertFalse(app.staticTexts["1 model selected"].exists)
        XCTAssertFalse(app.staticTexts["Enable the default multi-model lineup."].exists)
        XCTAssertTrue(app.buttons["Show All"].exists)
        XCTAssertTrue(app.buttons["Show Workflows"].exists)
        XCTAssertTrue(app.buttons["Show Agents"].exists)
        XCTAssertTrue(app.buttons["Show Projects"].exists)
        XCTAssertTrue(app.buttons["Brief project"].exists)
        XCTAssertTrue(app.buttons["Context to actions"].exists)
        XCTAssertTrue(app.buttons["Draft trackers"].exists)
        XCTAssertTrue(app.buttons["Sources & proof"].exists)
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
}
