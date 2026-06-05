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
        XCTAssertTrue(app.buttons["Next actions"].exists || app.staticTexts["Next actions"].exists)
        XCTAssertTrue(app.buttons["Files to actions"].exists || app.staticTexts["Files to actions"].exists)
        XCTAssertTrue(app.buttons["Model GLM 5.1"].exists || app.staticTexts["GLM 5.1"].exists)
        XCTAssertTrue(app.buttons["Configure LLM Council"].exists || app.staticTexts["Council"].exists)
        XCTAssertTrue(app.buttons["Source mode Source"].exists || app.staticTexts["Source"].exists)
    }

    func testModelPickerDemoContainsNoSpeculativeModelNames() throws {
        let app = launchDemo(screen: "models")

        XCTAssertTrue(app.staticTexts["Model"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["NEAR Private model"].exists)
        for banned in [
            "GLM-5.1-FP8",
            "GLM-5.1",
            "GLM 5.1",
            "Qwen 3.7 Max",
            "Claude Opus 4.7",
            "gpt-5.5",
            "qwen3.7-max",
            "kimi-k2.6",
            "gemini-3.5-flash",
            "claude-opus-4-7"
        ] {
            XCTAssertFalse(app.staticTexts[banned].exists, "Speculative model name rendered: \(banned)")
        }
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
}
