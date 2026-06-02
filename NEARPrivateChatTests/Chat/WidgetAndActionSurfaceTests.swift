import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testWebUsePolicyResolutionKeepsLinksPromptSensitive() {
        XCTAssertFalse(ChatWebUsePolicy.whenFreshRequested.resolves(benefitsFromSearch: true, needsFreshFacts: false))
        XCTAssertTrue(ChatWebUsePolicy.whenFreshRequested.resolves(benefitsFromSearch: false, needsFreshFacts: true))
        XCTAssertTrue(ChatWebUsePolicy.whenHelpful.resolves(benefitsFromSearch: true, needsFreshFacts: false))
        XCTAssertFalse(ChatWebUsePolicy.whenHelpful.resolves(benefitsFromSearch: false, needsFreshFacts: false))
    }

    func testWidgetExtractParsesChartBlockAndStripsIt() throws {
        let text = """
        ETH is down on the day.

        ```near-widget
        {"kind":"chart","title":"ETH watcher","follow_up":"Why?","chart":{"label":"ETH / USD","value":"$3,124","delta":"-2.3%","trend":"down","points":[3200,3180,3150,3124]}}
        ```
        """
        let result = MessageWidget.extract(from: text)
        let widget = try XCTUnwrap(result.widget)
        XCTAssertEqual(widget.kind, .chart)
        XCTAssertEqual(widget.chart?.value, "$3,124")
        XCTAssertEqual(widget.chart?.trend, .down)
        XCTAssertEqual(widget.chart?.points.count, 4)
        XCTAssertEqual(widget.followUp, "Why?")
        XCTAssertEqual(result.cleanedText, "ETH is down on the day.")
        XCTAssertFalse(result.cleanedText.contains("near-widget"))
    }

    func testWidgetExtractReturnsNilWhenNoFence() {
        let text = "Just a normal answer with no widget."
        let result = MessageWidget.extract(from: text)
        XCTAssertNil(result.widget)
        XCTAssertEqual(result.cleanedText, text)
    }

    func testWidgetExtractComparisonAcceptsBareStringCells() throws {
        let text = """
        Here is the comparison.

        ```near-widget
        {"kind":"comparison","comparison":{"subtitle":"A vs B","columns":["A","B"],"rows":[{"label":"Speed","cells":["fast","slow"]}]}}
        ```
        """
        let widget = try XCTUnwrap(MessageWidget.extract(from: text).widget)
        XCTAssertEqual(widget.kind, .comparison)
        XCTAssertEqual(widget.comparison?.columns, ["A", "B"])
        XCTAssertEqual(widget.comparison?.rows.first?.cells.first?.text, "fast")
    }

    func testWidgetExtractMalformedJSONLeavesTextIntact() {
        let text = """
        Answer.

        ```near-widget
        {not valid json
        ```
        """
        let result = MessageWidget.extract(from: text)
        XCTAssertNil(result.widget)
        XCTAssertEqual(result.cleanedText, text)
    }

    func testWidgetExtractIgnoresBlockWithNoRenderableBody() {
        let text = """
        Hello.

        ```near-widget
        {"kind":"chart"}
        ```
        """
        let result = MessageWidget.extract(from: text)
        XCTAssertNil(result.widget)
    }

    func testWidgetExtractSkipsInvalidFirstFenceAndParsesSecond() throws {
        let text = """
        Intro.

        ```near-widget
        {broken
        ```

        More.

        ```near-widget
        {"kind":"metric","metric":{"label":"X","value":"42"}}
        ```
        """
        let widget = try XCTUnwrap(MessageWidget.extract(from: text).widget)
        XCTAssertEqual(widget.kind, .metric)
        XCTAssertEqual(widget.metric?.value, "42")
    }

    func testWidgetExtractToleratesInfoStringOnFenceLine() throws {
        let text = "Answer.\n\n```near-widget json\n{\"kind\":\"metric\",\"metric\":{\"label\":\"X\",\"value\":\"7\"}}\n```"
        let widget = try XCTUnwrap(MessageWidget.extract(from: text).widget)
        XCTAssertEqual(widget.metric?.value, "7")
    }

    func testWidgetExtractParsesActionPlanBlockAndStripsIt() throws {
        let text = """
        I found the top actions.

        ```near-widget
        {"kind":"action_plan","title":"Supplement table","action_plan":{"heading":"Schedule preview","summary":"Create these only after confirmation.","actions":[{"title":"Morning supplement tracker","type":"tracker","detail":"Uses Upon Waking rows.","schedule":"daily on waking","source":"AV sheet · Supplements row 12","time":"upon waking","recurrence":"daily","missing_fields":["exact waking time"],"confidence":0.82,"command":"Create a tracker for morning supplements every day","tone":"good"},{"title":"Bedtime calendar block","type":"calendar","detail":"Magnesium before bed needs a time.","schedule":"before bed","command":"Remind me to take magnesium before bed at 10pm","tone":"warn"}]}}
        ```
        """

        let result = MessageWidget.extract(from: text)
        let widget = try XCTUnwrap(result.widget)
        XCTAssertEqual(widget.kind, .actionPlan)
        XCTAssertEqual(widget.title, "Supplement table")
        XCTAssertEqual(widget.actionPlan?.heading, "Schedule preview")
        XCTAssertEqual(widget.actionPlan?.actions.count, 2)
        XCTAssertEqual(widget.actionPlan?.actions.first?.type, "tracker")
        XCTAssertEqual(widget.actionPlan?.actions.first?.source, "AV sheet · Supplements row 12")
        XCTAssertEqual(widget.actionPlan?.actions.first?.time, "upon waking")
        XCTAssertEqual(widget.actionPlan?.actions.first?.recurrence, "daily")
        XCTAssertEqual(widget.actionPlan?.actions.first?.missingFields, ["exact waking time"])
        XCTAssertEqual(widget.actionPlan?.actions.first?.confidence, 0.82)
        XCTAssertEqual(widget.actionPlan?.actions.last?.command, "Remind me to take magnesium before bed at 10pm")
        XCTAssertEqual(result.cleanedText, "I found the top actions.")
    }

    func testResponseInstructionsUseDomainNeutralWidgetSchema() {
        let webInstructions = PrivateChatAPI.responseInstructionsForTesting(webSearchEnabled: true)
        let privateInstructions = PrivateChatAPI.responseInstructionsForTesting(webSearchEnabled: false)
        for instructions in [webInstructions, privateInstructions, PrivateChatAPI.widgetInstructionForTesting] {
            XCTAssertFalse(instructions.contains("ETH / USD"), instructions)
            XCTAssertFalse(instructions.contains("$3,124"), instructions)
            XCTAssertFalse(instructions.contains("-2.3%"), instructions)
            XCTAssertFalse(instructions.contains("Markets"), instructions)
            XCTAssertTrue(instructions.contains("Project progress"), instructions)
            XCTAssertTrue(instructions.contains("Open risks"), instructions)
        }
        XCTAssertTrue(webInstructions.contains("GitHub-flavored tables"))
        XCTAssertTrue(privateInstructions.contains("fenced code blocks with language tags"))
        XCTAssertTrue(privateInstructions.contains("raw JSON outside the sanctioned near-widget block"))
    }

    func testActionSurfacePlannerLeavesPlainFactQuestionsAlone() {
        let text = "what is ephemeral"

        XCTAssertEqual(ActionSurfacePlanner.augmentedPrompt(text: text, attachmentNames: []), text)
    }

    func testActionSurfacePlannerAugmentsHardMobileActionRequests() {
        let prompts = [
            "Analyze this client sheet and turn it into trackers, reminders, and a calendar invite preview.",
            "Deep research this topic from sources and generate a prioritized workflow.",
            "Make this useful: surface what I should care about, what to monitor, and what to do next."
        ]

        for prompt in prompts {
            let augmented = ActionSurfacePlanner.augmentedPrompt(text: prompt, attachmentNames: [])
            XCTAssertTrue(augmented.contains("Action surface contract"), prompt)
            XCTAssertTrue(augmented.contains("Do not narrow this to one workflow"), prompt)
            XCTAssertTrue(augmented.contains("calendar-worthy"), prompt)
            XCTAssertTrue(augmented.contains("highest-leverage next action"), prompt)
            XCTAssertTrue(augmented.contains("near-widget action_plan"), prompt)
        }
    }

    func testWidgetActionItemDoesNotCreateSystemDraftWithoutConcreteTime() {
        let now = Date(timeIntervalSince1970: 1_782_777_600) // 2026-06-30 00:00 UTC
        let calendarAction = WidgetActionItem(
            title: "Supplement follow-up",
            type: "calendar",
            detail: "Date exists, time does not.",
            schedule: nil,
            command: nil,
            source: "supplement sheet",
            date: "2026-07-01",
            time: nil,
            duration: nil,
            recurrence: nil,
            timezone: nil,
            location: nil,
            attendees: [],
            missingFields: ["time"],
            confidence: 0.82,
            tone: nil
        )
        let reminderAction = WidgetActionItem(
            title: "Renew passport",
            type: "reminder",
            detail: "Needs a time before creating a phone reminder.",
            schedule: nil,
            command: "Remind me to renew passport tomorrow",
            source: nil,
            date: nil,
            time: nil,
            duration: nil,
            recurrence: nil,
            timezone: nil,
            location: nil,
            attendees: [],
            missingFields: ["time"],
            confidence: 0.8,
            tone: nil
        )

        XCTAssertNil(calendarAction.systemActionDraft(now: now))
        XCTAssertNil(reminderAction.systemActionDraft(now: now))
    }

    func testHostileProductTrialPrivateChatIOSActionSurfaceContract() throws {
        XCTAssertNil(QuickIntentParser.parse("Weather in Tokyo and remind me to pack an umbrella tomorrow at 7am"))
        guard case let .createTracker(monthly) = QuickIntentParser.parse("Set up a monthly briefing on Anthropic policy updates with source links and calendar-worthy follow-ups") else {
            return XCTFail("Expected monthly briefing to become a scheduled tracker.")
        }
        XCTAssertEqual(monthly.schedule, .monthly(day: 1, hour: 8, minute: 0))
        XCTAssertNil(QuickIntentParser.parse("watch this video and tell me if the creator is wrong"))
        XCTAssertNil(QuickIntentParser.parse("Deep search Claude Code, Xcode release notes, and OpenAI docs; make a tracker only if there is a breaking workflow change; otherwise list dated sources and next actions."))

        guard case let .createReminder(reminder) = QuickIntentParser.parse("remind me to call mom at 5pm") else {
            return XCTFail("A concrete one-time reminder should stay a reminder, not become a recurring tracker.")
        }
        XCTAssertEqual(reminder.title, "call mom")

        guard case let .createTracker(research) = QuickIntentParser.parse("research latest Claude Code release notes every 6 hours and tell me what changed") else {
            return XCTFail("Recurring research should become a custom tracker.")
        }
        XCTAssertEqual(research.kind, .customPrompt)
        XCTAssertEqual(research.schedule, .everyNHours(6))
        XCTAssertTrue(try XCTUnwrap(research.prompt).lowercased().contains("claude code release notes"))

        guard case let .createTracker(weekday) = QuickIntentParser.parse("track vendor SLA changes every Tuesday at 6pm") else {
            return XCTFail("Weekly factual monitoring should become a weekly tracker.")
        }
        XCTAssertEqual(weekday.schedule, .weekly(weekday: 3, hour: 18, minute: 0))

        guard case let .createTracker(routine) = QuickIntentParser.parse("remind me to take creatine every morning at 8 am") else {
            return XCTFail("Concrete recurring routine should become a scheduled tracker.")
        }
        XCTAssertEqual(routine.title, "take creatine")
        XCTAssertEqual(routine.schedule, .daily(hour: 8, minute: 0))
        XCTAssertNil(QuickIntentParser.parse("remind me to take magnesium before bed"))

        let plannerPrompt = ActionSurfacePlanner.augmentedPrompt(
            text: "Extract the supplement table from this file, infer useful actions, create schedule trackers, and preview phone calendar invites.",
            attachmentNames: ["AV- Blueprxnt Client Master Sheet (1).xlsx"]
        )
        XCTAssertTrue(plannerPrompt.contains("Action surface contract"))
        XCTAssertTrue(plannerPrompt.contains("Do not narrow this to one workflow"))
        XCTAssertTrue(plannerPrompt.contains("missing_fields"))
        XCTAssertTrue(plannerPrompt.contains("near-widget action_plan"))
        XCTAssertTrue(plannerPrompt.contains("AV- Blueprxnt Client Master Sheet (1).xlsx"))
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb("Investigate current FDA supplement recalls from dated sources and turn findings into actions."))
        XCTAssertFalse(RoutePlanner.promptNeedsLiveWeb("Use only this attached file, no web, and turn it into actions."))
        let override = RoutePlanner.promptSourcePrivacyOverride(
            for: "Use only this attached file, no web, keep it private.",
            hasAttachments: true
        )
        XCTAssertTrue(override.blocksWeb)
        XCTAssertTrue(override.prefersFileOnly)
        XCTAssertTrue(override.requiresPrivateRoute)

        let now = Date(timeIntervalSince1970: 1_782_777_600) // 2026-06-30 00:00 UTC
        let reminderAction = WidgetActionItem(
            title: "Send the deck",
            type: "task",
            detail: nil,
            schedule: nil,
            command: "Remind me to send the deck 2026-07-01 9:00 AM",
            source: nil,
            date: nil,
            time: nil,
            duration: nil,
            recurrence: nil,
            timezone: nil,
            location: nil,
            attendees: [],
            missingFields: [],
            confidence: nil,
            tone: nil
        )
        XCTAssertEqual(try XCTUnwrap(reminderAction.systemActionDraft(now: now)).kind, .reminder)

        let calendarAction = WidgetActionItem(
            title: "Supplement follow-up",
            type: "calendar",
            detail: nil,
            schedule: nil,
            command: nil,
            source: "Supplementation sheet",
            date: nil,
            time: "2026-07-01 9:30 AM",
            duration: "30 minutes",
            recurrence: nil,
            timezone: nil,
            location: "Phone",
            attendees: [],
            missingFields: [],
            confidence: nil,
            tone: nil
        )
        XCTAssertEqual(try XCTUnwrap(calendarAction.systemActionDraft(now: now)).kind, .calendarEvent)

        let fuzzyAction = WidgetActionItem(
            title: "Bedtime magnesium",
            type: "calendar",
            detail: "Timing is fuzzy.",
            schedule: "before bed",
            command: "Remind me to take magnesium before bed",
            source: nil,
            date: nil,
            time: "before bed",
            duration: nil,
            recurrence: "daily",
            timezone: nil,
            location: nil,
            attendees: [],
            missingFields: ["exact time"],
            confidence: 0.62,
            tone: nil
        )
        XCTAssertNil(fuzzyAction.systemActionDraft(now: now))
    }

    func testFXDoesNotHijackNonCurrencyPrompts() {
        XCTAssertNil(QuickIntentParser.parse("how much do you love me"))
        XCTAssertNil(QuickIntentParser.parse("translate this to spanish"))
        // Control: a real conversion still fires.
        XCTAssertEqual(QuickIntentParser.parse("convert 100 usd to eur"), .fx(amount: 100, from: "USD", to: "EUR"))
    }

    func testWidgetToneDecodesDirectionAliases() throws {
        func tone(_ s: String) throws -> WidgetTone {
            try JSONDecoder().decode(WidgetTone.self, from: Data("\"\(s)\"".utf8))
        }
        // Cohesion: down/negative map to .bad (red, matching the chart card).
        XCTAssertEqual(try tone("down"), .bad)
        XCTAssertEqual(try tone("negative"), .bad)
        XCTAssertEqual(try tone("up"), .good)
        XCTAssertEqual(try tone("partial"), .warn)
    }

    @MainActor
    func testConsumePendingSiriPromptStagesDraftOnce() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set("what is the eth price", forKey: ChatStore.pendingSiriPromptKey)
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))

        XCTAssertTrue(store.consumePendingSiriPrompt(defaults: defaults))
        XCTAssertEqual(store.draft, "what is the eth price")
        // Consumed: the key is cleared and a second call is a no-op.
        XCTAssertNil(defaults.string(forKey: ChatStore.pendingSiriPromptKey))
        XCTAssertFalse(store.consumePendingSiriPrompt(defaults: defaults))
    }
}
