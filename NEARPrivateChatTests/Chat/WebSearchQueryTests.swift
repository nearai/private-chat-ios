import XCTest
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testWebSearchLowSignalFollowUpsAreDetected() {
        XCTAssertTrue(WebGroundingService.isLowSignalFollowUp("try again"))
        XCTAssertTrue(WebGroundingService.isLowSignalFollowUp("run"))
        XCTAssertTrue(WebGroundingService.isLowSignalFollowUp("do the job i asked"))
        XCTAssertTrue(WebGroundingService.isLowSignalFollowUp("more"))
        XCTAssertTrue(WebGroundingService.isLowSignalFollowUp("Where is price"))
    }

    func testWebSearchTopicalQueriesAreNotLowSignalFollowUps() {
        XCTAssertFalse(WebGroundingService.isLowSignalFollowUp("what is happening in Iran"))
        XCTAssertFalse(WebGroundingService.isLowSignalFollowUp("compare oil markets to 2008"))
        XCTAssertFalse(WebGroundingService.isLowSignalFollowUp("what about oil markets"))
    }

    func testWebSearchPromptReusesPreviousSubstantiveUserQuery() {
        let prompt = WebGroundingService.searchPrompt(
            for: "try again",
            priorUserTexts: [
                "again",
                "what is happening in Iran",
                "more"
            ]
        )

        XCTAssertEqual(prompt, "what is happening in Iran")
    }

    func testWebSearchPromptSkipsMetaPhraseWithoutPriorTopic() {
        XCTAssertNil(WebGroundingService.searchPrompt(for: "run", priorUserTexts: ["again", "more"]))
    }

    func testWebSearchPromptKeepsCurrentSubstantiveQuery() {
        XCTAssertEqual(
            WebGroundingService.searchPrompt(
                for: "compare oil markets to 2008",
                priorUserTexts: ["what is happening in Iran"]
            ),
            "compare oil markets to 2008"
        )
    }

    func testWebSearchModeExtractsExplicitNewsAndWebIntent() {
        XCTAssertEqual(WebGroundingService.searchMode(for: "latest news on NEAR"), .newsFirst)
        XCTAssertEqual(WebGroundingService.searchMode(for: "from Google News summarize NEAR"), .newsFirst)
        XCTAssertEqual(WebGroundingService.searchMode(for: "web only NEAR protocol updates"), .webFirst)
        XCTAssertEqual(WebGroundingService.searchMode(for: "not news, use general web for NEAR docs"), .webFirst)
        XCTAssertEqual(WebGroundingService.searchMode(for: "summarize NEAR docs"), .automatic)
    }

    func testWebSearchQueryRemovesModeDirectives() {
        XCTAssertEqual(WebGroundingService.query(from: "from Google News summarize NEAR"), "summarize NEAR")
        XCTAssertEqual(WebGroundingService.query(from: "web only NEAR protocol updates"), "NEAR protocol updates")
    }
}
