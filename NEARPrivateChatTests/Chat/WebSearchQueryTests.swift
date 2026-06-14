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
        XCTAssertEqual(WebGroundingService.searchMode(for: "Using live web sources, what are the top three AI news stories today?"), .newsFirst)
        XCTAssertEqual(WebGroundingService.searchMode(for: "web only NEAR protocol updates"), .webFirst)
        XCTAssertEqual(WebGroundingService.searchMode(for: "not news, use general web for NEAR docs"), .webFirst)
        XCTAssertEqual(WebGroundingService.searchMode(for: "summarize NEAR docs"), .automatic)
    }

    func testWebSearchQueryRemovesModeDirectives() {
        XCTAssertEqual(WebGroundingService.query(from: "from Google News summarize NEAR"), "summarize NEAR")
        XCTAssertEqual(WebGroundingService.query(from: "web only NEAR protocol updates"), "NEAR protocol updates")
    }

    func testWebSearchQueryKeepsSubstanceAfterLiveWebDirective() {
        XCTAssertEqual(
            WebGroundingService.query(
                from: "Using live web sources, what are the top three AI news stories today? Answer in three bullets and cite sources."
            ),
            "AI news today"
        )
    }

    func testWebSearchQueryCleansHardMultiTopicCurrentEventsPrompt() {
        let prompt = "Using live web sources, check today's reporting on SpaceX IPO or private-market news and the latest Iran conflict developments. Separate confirmed facts from uncertainty and cite sources."

        XCTAssertEqual(
            WebGroundingService.query(from: prompt),
            "SpaceX IPO or private-market news and the latest Iran conflict developments"
        )
    }

    func testWebSearchQueriesExpandHardMultiTopicCurrentEventsPrompt() {
        let prompt = "Using live web sources, check today's reporting on SpaceX IPO or private-market news and the latest Iran conflict developments. Separate confirmed facts from uncertainty and cite sources."

        XCTAssertEqual(
            WebGroundingService.queries(from: prompt),
            [
                "SpaceX IPO or private-market news and the latest Iran conflict developments",
                "SpaceX IPO private market news",
                "Iran conflict developments"
            ]
        )
    }

    func testWebSearchQueriesStaySingleForSimpleNewsPrompt() {
        XCTAssertEqual(
            WebGroundingService.queries(
                from: "Using live web sources, what are the top three AI news stories today? Answer in three bullets and cite sources."
            ),
            ["AI news today"]
        )
    }

    func testSourceSearchDisplaySplitsMultiQueryProvenance() {
        let display = SourceSearchDisplay(
            query: "SpaceX IPO or private-market news and the latest Iran conflict developments | SpaceX IPO private market news | Iran conflict developments"
        )

        XCTAssertEqual(
            display.queries,
            [
                "SpaceX IPO or private-market news and the latest Iran conflict developments",
                "SpaceX IPO private market news",
                "Iran conflict developments"
            ]
        )
        XCTAssertEqual(
            display.summary,
            "SpaceX IPO or private-market news and the latest Iran conflict developments · SpaceX IPO private market news · Iran conflict developments"
        )
    }

    func testSourceSearchDisplayRemovesAgentMissionBoilerplate() {
        let display = SourceSearchDisplay(
            query: "Agent Mission: Research: Mission brief from phone: latest AI news\nExecution contract: cite sources"
        )

        XCTAssertEqual(display.queries, ["latest AI news"])
        XCTAssertEqual(display.summary, "latest AI news")
    }
}
