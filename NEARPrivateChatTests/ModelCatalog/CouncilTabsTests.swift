import XCTest
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testCouncilSynthesisSectionsSplitFullFourSectionSynthesis() {
        let sections = CouncilSynthesisSections.split("""
        ## Direct answer
        Ship the tabbed answer.

        ## What the council agrees on
        The synthesis should lead.

        ## Disagreements or uncertainty
        One model wanted more sources.

        ## Recommended next step
        Validate the focused UI tests.
        """)

        XCTAssertEqual(sections.count, 4)
        XCTAssertEqual(CouncilSynthesisSections.text(in: sections, for: .directAnswer), "Ship the tabbed answer.")
        XCTAssertEqual(CouncilSynthesisSections.text(in: sections, for: .agreement), "The synthesis should lead.")
        XCTAssertEqual(CouncilSynthesisSections.text(in: sections, for: .disagreement), "One model wanted more sources.")
        XCTAssertEqual(CouncilSynthesisSections.text(in: sections, for: .nextStep), "Validate the focused UI tests.")
    }

    func testCouncilSynthesisSectionsSplitMissingRecommendedNextStep() {
        let sections = CouncilSynthesisSections.split("""
        ## Direct answer
        Use the settled Council answer.

        ## What the council agrees on
        Tabs make comparison clearer.

        ## Disagreements or uncertainty
        The member details differ.
        """)

        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections.map(\.kind), [.directAnswer, .agreement, .disagreement])
        XCTAssertEqual(CouncilSynthesisSections.text(in: sections, for: .nextStep), "")
    }

    func testCouncilSynthesisSectionsPlacesPreambleInDirectAnswer() {
        let sections = CouncilSynthesisSections.split("""
        Start with this plain-language summary.

        ## What the council agrees on
        All models support the same answer.
        """)

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(
            CouncilSynthesisSections.text(in: sections, for: .directAnswer),
            "Start with this plain-language summary."
        )
        XCTAssertEqual(
            CouncilSynthesisSections.text(in: sections, for: .agreement),
            "All models support the same answer."
        )
    }

    func testCouncilAnswerTabModelBuildsSynthesisMembersAndSources() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let sources = [
            WebSearchSource(type: "web", url: "https://example.com/a", title: "Source A", publishedAt: nil, snippet: nil),
            WebSearchSource(type: "web", url: "https://example.com/b", title: "Source B", publishedAt: nil, snippet: nil)
        ]
        let messages = [
            councilMessage(
                id: "synthesis",
                text: "## Direct answer\nUse tabs.",
                model: ModelOption.llmCouncilSynthesisModelID,
                createdAt: createdAt.addingTimeInterval(3),
                sources: [sources[0]]
            ),
            councilMessage(
                id: "model-a",
                text: "A",
                model: "ModelA",
                createdAt: createdAt,
                sources: [sources[0]]
            ),
            councilMessage(
                id: "model-b",
                text: "B",
                model: "ModelB",
                createdAt: createdAt.addingTimeInterval(1),
                sources: [sources[1]]
            )
        ]

        let model = CouncilAnswerTabModel.build(from: messages)

        XCTAssertEqual(model.tabs.map(\.label), ["Synthesis", "ModelA", "ModelB", "Sources"])
        XCTAssertEqual(model.defaultTabID, "synthesis")
        XCTAssertEqual(model.sources.map(\.url), ["https://example.com/a", "https://example.com/b"])
        XCTAssertEqual(model.sourceAttributions["https://example.com/a"], ["ModelA"])
        XCTAssertEqual(model.sourceAttributions["https://example.com/b"], ["ModelB"])
    }

    func testCouncilAnswerTabModelDedupesSourceAttributionsPerModel() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let source = WebSearchSource(type: "web", url: "https://example.com/a", title: "Source A", publishedAt: nil, snippet: nil)
        let messages = [
            councilMessage(
                id: "model-a",
                text: "A",
                model: "ModelA",
                createdAt: createdAt,
                sources: [source, source]
            ),
            councilMessage(
                id: "model-b",
                text: "B",
                model: "ModelB",
                createdAt: createdAt.addingTimeInterval(1),
                sources: [source]
            )
        ]

        let model = CouncilAnswerTabModel.build(from: messages)

        XCTAssertEqual(model.sources.map(\.url), ["https://example.com/a"])
        XCTAssertEqual(model.sourceAttributions["https://example.com/a"], ["ModelA", "ModelB"])
    }

    func testCouncilAnswerTabModelDefaultsToFirstMemberWithoutSynthesis() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let messages = [
            councilMessage(id: "model-a", text: "A", model: "ModelA", createdAt: createdAt),
            councilMessage(id: "model-b", text: "B", model: "ModelB", createdAt: createdAt.addingTimeInterval(1))
        ]

        let model = CouncilAnswerTabModel.build(from: messages)

        XCTAssertEqual(model.tabs.map(\.label), ["ModelA", "ModelB"])
        XCTAssertEqual(model.defaultTabID, "model-model-a")
    }

    func testCouncilAnswerTabCompactsLongModelLabelsForVisibleTabs() {
        XCTAssertEqual(CouncilAnswerTab.compactModelLabel("zai-org/GLM-5.1-FP8"), "GLM 5.1")
        XCTAssertEqual(CouncilAnswerTab.compactModelLabel("Qwen/Qwen3.6-35B-A3B-FP8"), "Qwen 3.6")
        XCTAssertEqual(CouncilAnswerTab.compactModelLabel("Qwen3-VL-30B-A3B-Instruct"), "Qwen VL")
        XCTAssertEqual(CouncilAnswerTab.compactModelLabel("Claude Sonnet 4.6"), "Sonnet 4.6")
        XCTAssertEqual(CouncilAnswerTab.compactModelLabel("Small Model"), "Small Model")
    }

    func testCouncilAnswerTabKeepsFullModelLabelForAccessibility() {
        let tab = CouncilAnswerTab.model(
            messageID: "model-a",
            label: "Qwen/Qwen3.6-35B-A3B-FP8"
        )

        XCTAssertEqual(tab.label, "Qwen/Qwen3.6-35B-A3B-FP8")
        XCTAssertEqual(tab.displayLabel, "Qwen 3.6")
    }

    private func councilMessage(
        id: String,
        text: String,
        model: String,
        createdAt: Date,
        sources: [WebSearchSource] = []
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            role: .assistant,
            text: text,
            model: model,
            createdAt: createdAt,
            status: "completed",
            responseID: id,
            councilBatchID: "batch-1",
            isStreaming: false,
            sources: sources
        )
    }
}
