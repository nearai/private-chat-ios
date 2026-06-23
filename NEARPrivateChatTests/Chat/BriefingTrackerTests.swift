import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testBriefingDecodesLegacyJSONWithoutKind() throws {
        // Simulate a briefings.json written before `kind`/`accountID` existed.
        let modern = Briefing(title: "Legacy", prompt: "p", schedule: .daily(hour: 8, minute: 0))
        let data = try JSONEncoder().encode(modern)
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "kind")
        dict.removeValue(forKey: "accountID")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(Briefing.self, from: legacyData)
        XCTAssertEqual(decoded.kind, .customPrompt)
        XCTAssertNil(decoded.accountID)
        XCTAssertEqual(decoded.title, "Legacy")
    }

    func testBriefingScheduleProducesRepeatingNotificationTriggers() throws {
        let daily = BriefingSchedule.daily(hour: 8, minute: 30).notificationTriggers()
        XCTAssertEqual(daily.count, 1)
        let dailyTrigger = try XCTUnwrap(daily.first as? UNCalendarNotificationTrigger)
        XCTAssertTrue(dailyTrigger.repeats)
        XCTAssertEqual(dailyTrigger.dateComponents.hour, 8)
        XCTAssertEqual(dailyTrigger.dateComponents.minute, 30)

        // Weekdays expand to one weekly trigger per business day (Mon–Fri = 2…6).
        let weekdays = BriefingSchedule.weekdays(hour: 7, minute: 0).notificationTriggers()
        XCTAssertEqual(weekdays.count, 5)
        let weekdaySet = Set(weekdays.compactMap { ($0 as? UNCalendarNotificationTrigger)?.dateComponents.weekday })
        XCTAssertEqual(weekdaySet, Set(2...6))

        let weekly = BriefingSchedule.weekly(weekday: 3, hour: 9, minute: 15).notificationTriggers()
        XCTAssertEqual(try XCTUnwrap(weekly.first as? UNCalendarNotificationTrigger).dateComponents.weekday, 3)

        let monthly = BriefingSchedule.monthly(day: 15, hour: 10, minute: 45).notificationTriggers()
        let monthlyTrigger = try XCTUnwrap(monthly.first as? UNCalendarNotificationTrigger)
        XCTAssertTrue(monthlyTrigger.repeats)
        XCTAssertEqual(monthlyTrigger.dateComponents.day, 15)
        XCTAssertEqual(monthlyTrigger.dateComponents.hour, 10)
        XCTAssertEqual(monthlyTrigger.dateComponents.minute, 45)

        let biweekly = BriefingSchedule.biweekly(weekday: 4, hour: 11, minute: 0).notificationTriggers()
        let biweeklyTrigger = try XCTUnwrap(biweekly.first as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(biweeklyTrigger.timeInterval, 14 * 24 * 3600, accuracy: 1)
        XCTAssertTrue(biweeklyTrigger.repeats)

        let hourly = BriefingSchedule.everyNHours(6).notificationTriggers()
        let hourlyTrigger = try XCTUnwrap(hourly.first as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(hourlyTrigger.timeInterval, 6 * 3600, accuracy: 1)
        XCTAssertTrue(hourlyTrigger.repeats)
    }

    func testBriefingKindDecodesUnknownAsCustomPrompt() throws {
        let data = try XCTUnwrap("\"someFutureKind\"".data(using: .utf8))
        let kind = try JSONDecoder().decode(BriefingKind.self, from: data)
        XCTAssertEqual(kind, .customPrompt)
        XCTAssertFalse(kind.isLiveData)
        XCTAssertTrue(BriefingKind.ethPrice.isLiveData)
    }

    func testBriefingComparatorEvaluatesAndSummarizes() {
        XCTAssertTrue(BriefingComparator.below.evaluate(1_900, 2_000))
        XCTAssertFalse(BriefingComparator.below.evaluate(2_100, 2_000))
        XCTAssertTrue(BriefingComparator.above.evaluate(2_100, 2_000))
        let condition = BriefingCondition(coinID: "ethereum", symbol: "ETH", comparator: .below, threshold: 2_000)
        XCTAssertTrue(condition.isSatisfied(by: 1_950))
        XCTAssertFalse(condition.isSatisfied(by: 2_050))
        XCTAssertTrue(condition.summary.contains("ETH"))
        XCTAssertTrue(condition.summary.contains("below"))
    }

    func testBriefingConditionCodableRoundTripAndBackCompat() throws {
        let condition = BriefingCondition(coinID: "ethereum", symbol: "ETH", comparator: .below, threshold: 2_000)
        let briefing = Briefing(title: "ETH alert", prompt: "", schedule: .everyNHours(3),
                                kind: .cryptoPrice, accountID: "ethereum", condition: condition)
        let decoded = try JSONDecoder().decode(Briefing.self, from: JSONEncoder().encode(briefing))
        XCTAssertEqual(decoded.condition, condition)
        XCTAssertTrue(decoded.isConditional)

        // A plain briefing omits the condition key (back-compat) and decodes nil.
        let plain = Briefing(title: "News", prompt: "p", schedule: .daily(hour: 8, minute: 0), kind: .dailyNews)
        let plainData = try JSONEncoder().encode(plain)
        XCTAssertFalse(String(decoding: plainData, as: UTF8.self).contains("condition"))
        let plainDecoded = try JSONDecoder().decode(Briefing.self, from: plainData)
        XCTAssertNil(plainDecoded.condition)
        XCTAssertFalse(plainDecoded.isConditional)
    }

    func testQuickIntentParsesListTrackers() {
        XCTAssertEqual(QuickIntentParser.parse("what are you tracking"), .listTrackers)
        XCTAssertEqual(QuickIntentParser.parse("show my alerts"), .listTrackers)
        XCTAssertEqual(QuickIntentParser.parse("list my trackers"), .listTrackers)
        // Ambiguous "watching/monitoring" prompts are no longer hijacked.
        XCTAssertNotEqual(QuickIntentParser.parse("what are you watching on tv tonight"), .listTrackers)
    }

    func testTrackerListFormatter() {
        XCTAssertTrue(TrackerListFormatter.summary(for: []).contains("any automations yet"))

        let alert = Briefing(title: "ETH alert", prompt: "", schedule: .everyNHours(3),
                             kind: .cryptoPrice, accountID: "ethereum",
                             condition: BriefingCondition(coinID: "ethereum", symbol: "ETH",
                                                          comparator: .below, threshold: 2_000))
        let news = Briefing(title: "Daily news", prompt: "p", schedule: .daily(hour: 8, minute: 0), kind: .dailyNews)
        let paused = Briefing(title: "Old watch", prompt: "p", schedule: .daily(hour: 9, minute: 0),
                              isPaused: true, kind: .customPrompt)
        let summary = TrackerListFormatter.summary(for: [alert, news, paused])
        XCTAssertTrue(summary.contains("(3)"))
        XCTAssertTrue(summary.contains("ETH alert"))
        XCTAssertTrue(summary.contains("alerts when"))
        XCTAssertTrue(summary.contains("Daily news"))
        XCTAssertTrue(summary.contains("paused"))
        // Active trackers are listed before paused ones.
        let ethIndex = try? XCTUnwrap(summary.range(of: "ETH alert")).lowerBound
        let pausedIndex = try? XCTUnwrap(summary.range(of: "Old watch")).lowerBound
        if let ethIndex, let pausedIndex { XCTAssertTrue(ethIndex < pausedIndex) }
    }

    func testReminderParserExtractsTitleAndFutureDate() {
        let r = QuickIntentParser.parseReminder("remind me to call mom at 5pm", original: "remind me to call mom at 5pm")
        XCTAssertEqual(r?.title, "call mom")
        if let r { XCTAssertGreaterThan(r.date, Date()) } else { XCTFail("expected reminder") }

        let r2 = QuickIntentParser.parseReminder("set a reminder to submit the report friday at 9am",
                                                 original: "set a reminder to submit the report friday at 9am")
        XCTAssertTrue(r2?.title.contains("submit the report") ?? false)

        // A date between the trigger and the task doesn't garble the title —
        // leading connectors left by the removed date are stripped.
        let r3 = QuickIntentParser.parseReminder("remind me at 3pm to email the team",
                                                 original: "remind me at 3pm to email the team")
        XCTAssertEqual(r3?.title, "email the team")

        // No time → not a scheduled reminder (let the model handle it).
        XCTAssertNil(QuickIntentParser.parseReminder("remind me to stretch", original: "remind me to stretch"))
        XCTAssertNil(QuickIntentParser.parseReminder("remind me to renew passport tomorrow",
                                                     original: "remind me to renew passport tomorrow"))
        // Question-shaped "remind me…" stays a model question.
        XCTAssertNil(QuickIntentParser.parseReminder("remind me why the sky is blue", original: "remind me why the sky is blue"))
    }

    func testQuickIntentParsesReminder() {
        guard case let .createReminder(reminder) = QuickIntentParser.parse("remind me to call mom at 5pm") else {
            return XCTFail("Expected a reminder intent.")
        }
        XCTAssertEqual(reminder.title, "call mom")
    }

    func testQuickIntentParsesOpenEndedTracker() {
        // The agentic-OS case: any subject (no built-in feed) becomes a
        // web-grounded recurring tracker.
        guard case let .createTracker(rolex) = QuickIntentParser.parse("track the price of a Rolex GMT Master II every morning") else {
            return XCTFail("Expected an open-ended tracker.")
        }
        XCTAssertEqual(rolex.kind, .customPrompt)
        XCTAssertEqual(rolex.title, "Rolex GMT Master II")          // case preserved
        XCTAssertEqual(rolex.schedule, .daily(hour: 8, minute: 0))
        XCTAssertTrue((rolex.prompt ?? "").contains("Rolex GMT Master II"))
        XCTAssertTrue((rolex.prompt ?? "").lowercased().contains("web search"))

        // Works without an explicit schedule (defaults to daily).
        guard case let .createTracker(spx) = QuickIntentParser.parse("watch the S&P 500 level") else {
            return XCTFail("Expected a tracker without an explicit schedule.")
        }
        XCTAssertEqual(spx.kind, .customPrompt)

        // No info cue → not a tracker (stays a model question).
        if case .createTracker = QuickIntentParser.parse("watch this video") {
            XCTFail("A non-informational 'watch' must not become a tracker.")
        }
        // A bare to-do reminder is not a tracker.
        if case .createTracker = QuickIntentParser.parse("remind me to stretch daily") {
            XCTFail("A to-do must not become a tracker.")
        }
        // The "watch out" idiom in a statement must not become a tracker.
        if case .createTracker = QuickIntentParser.parse("watch out, the price went up today") {
            XCTFail("'watch out' is not a tracking command.")
        }
    }

    func testHardRecurringWorkflowPromptsBecomeActionableTrackers() throws {
        guard case let .createTracker(rolex) = QuickIntentParser.parse("Track the price of a Rolex GMT-Master II every morning at 8am.") else {
            return XCTFail("Expected a Rolex market-price watcher.")
        }
        XCTAssertEqual(rolex.kind, .customPrompt)
        XCTAssertEqual(rolex.schedule, .daily(hour: 8, minute: 0))
        XCTAssertTrue(rolex.title.localizedCaseInsensitiveContains("Rolex"))
        XCTAssertTrue(try XCTUnwrap(rolex.prompt).localizedCaseInsensitiveContains("web search"))

        guard case let .createTracker(rolexWithInstruction) = QuickIntentParser.parse("Track the price of a Rolex GMT-Master II every morning at 8am. Use web search, lead with the current market price and as-of date.") else {
            return XCTFail("Expected an open-ended tracker with extra instructions.")
        }
        XCTAssertEqual(rolexWithInstruction.title, "Rolex GMT-Master II")
        XCTAssertFalse(rolexWithInstruction.confirmation.localizedCaseInsensitiveContains("use web search"))

        guard case let .createTracker(release) = QuickIntentParser.parse("Monitor Apple Vision Pro 2 release date updates every Monday at 9am.") else {
            return XCTFail("Expected a product-release watcher.")
        }
        XCTAssertEqual(release.kind, .customPrompt)
        XCTAssertEqual(release.schedule, .weekly(weekday: 2, hour: 9, minute: 0))
        XCTAssertEqual(release.title, "Apple Vision Pro 2 release date")
        XCTAssertTrue(try XCTUnwrap(release.prompt).localizedCaseInsensitiveContains("release date"))

        guard case let .createTracker(aiDigest) = QuickIntentParser.parse("Create a daily AI news digest every morning at 8am with sources and anything that needs attention.") else {
            return XCTFail("Expected an AI news digest briefing.")
        }
        XCTAssertEqual(aiDigest.kind, .customPrompt)
        XCTAssertEqual(aiDigest.schedule, .daily(hour: 8, minute: 0))
        XCTAssertEqual(aiDigest.title, "AI news digest")
        XCTAssertTrue(aiDigest.confirmation.contains("Briefing"))
        XCTAssertTrue(try XCTUnwrap(aiDigest.prompt).localizedCaseInsensitiveContains("ai news digest"))
    }

    @MainActor
    func testSendDraftCreatesHardRecurringWorkflowWithoutPrivateRoute() throws {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        var created: Briefing?
        store.onCreateTracker = { created = $0 }
        store.draft = "Create a daily AI news digest every morning at 8am with sources and anything that needs attention."

        store.sendDraft()

        let briefing = try XCTUnwrap(created)
        XCTAssertEqual(briefing.kind, .customPrompt)
        XCTAssertEqual(briefing.title, "AI news digest")
        XCTAssertEqual(briefing.schedule, .daily(hour: 8, minute: 0))
        XCTAssertTrue(briefing.prompt.localizedCaseInsensitiveContains("ai news digest"))
        XCTAssertFalse(store.isStreaming)
        XCTAssertTrue(store.messages.last?.text.contains("Created a tracker") == true)
    }

    func testQuickIntentParsesTrackThat() {
        XCTAssertEqual(QuickIntentParser.parse("track that"), .trackLast(schedule: .daily(hour: 8, minute: 0)))
        XCTAssertEqual(QuickIntentParser.parse("track that daily"), .trackLast(schedule: .daily(hour: 8, minute: 0)))
        XCTAssertEqual(QuickIntentParser.parse("keep an eye on that"), .trackLast(schedule: .daily(hour: 8, minute: 0)))
        XCTAssertEqual(QuickIntentParser.parse("watch it every morning"), .trackLast(schedule: .daily(hour: 8, minute: 0)))
        // A pronoun WITH a subject is a normal tracker, not "track that".
        if case .trackLast = QuickIntentParser.parse("track that bitcoin price") { XCTFail("has a subject → normal tracker") }
        if case .trackLast = QuickIntentParser.parse("track the price of a Rolex") { XCTFail("has a subject → open-ended tracker") }
    }


    @MainActor
    func testTrackThatCreatesTrackerFromPriorQuestion() {
        let chatStore = ChatStore(api: PrivateChatAPI(configuration: .production))
        var created: Briefing?
        chatStore.onCreateTracker = { created = $0 }
        // Seed a prior question (a synchronous math intent appends a user message).
        chatStore.draft = "what is 5 plus 5"
        chatStore.sendDraft()
        // "track that" builds a tracker from that prior question.
        chatStore.draft = "track that"
        chatStore.sendDraft()
        XCTAssertEqual(created?.kind, .customPrompt)
        XCTAssertEqual(created?.title, "5 plus 5")
        XCTAssertTrue((created?.prompt ?? "").contains("5 plus 5"))
    }

    func testBriefDigestComposesTrackersAndMarket() {
        let rolex = Briefing(title: "Rolex GMT Master II", prompt: "p", schedule: .daily(hour: 8, minute: 0),
                             latestResult: MessageWidget(kind: .metric, metric: WidgetMetric(value: "$14,800")),
                             kind: .customPrompt)
        let paused = Briefing(title: "Old watch", prompt: "p", schedule: .daily(hour: 9, minute: 0),
                              isPaused: true, kind: .customPrompt)
        let theBrief = Briefing(title: "Daily brief", prompt: "", schedule: .daily(hour: 8, minute: 0), kind: .dailyBrief)
        let widget = BriefDigest.compose(trackers: [rolex, paused, theBrief], market: [("ETH", "$2,019")])

        XCTAssertEqual(widget.kind, .comparison)
        let labels = widget.comparison?.rows.map(\.label) ?? []
        XCTAssertTrue(labels.contains("Rolex GMT Master II"))
        XCTAssertTrue(labels.contains("ETH"))
        XCTAssertFalse(labels.contains("Old watch"))   // paused excluded
        XCTAssertFalse(labels.contains("Daily brief"))  // the brief itself excluded
        let rolexRow = widget.comparison?.rows.first { $0.label == "Rolex GMT Master II" }
        XCTAssertEqual(rolexRow?.cells.first?.text, "$14,800")
    }


    @MainActor
    func testTrackThisFollowUpStagesComposerInsteadOfCreatingImmediately() {
        let chatStore = ChatStore(api: PrivateChatAPI(configuration: .production))
        var created: Briefing?
        chatStore.onCreateTracker = { created = $0 }
        // Widget follow-ups are staged so the user can review the command before
        // creating a tracker or automation.
        chatStore.composeWidgetFollowUp("Track ETH price")
        XCTAssertNil(created)
        XCTAssertEqual(chatStore.draft, "Track ETH price")
        // A normal follow-up just prefills the composer (no tracker).
        var created2: Briefing?
        chatStore.onCreateTracker = { created2 = $0 }
        chatStore.composeWidgetFollowUp("Why is it moving?")
        XCTAssertNil(created2)
        XCTAssertEqual(chatStore.draft, "Why is it moving?")
    }


    @MainActor
    func testTrackThatWithoutPriorCreatesNothing() {
        let chatStore = ChatStore(api: PrivateChatAPI(configuration: .production))
        var created: Briefing?
        chatStore.onCreateTracker = { created = $0 }
        chatStore.draft = "track that"
        chatStore.sendDraft()
        XCTAssertNil(created) // nothing asked yet → asks for a subject, makes no tracker
    }

    func testActionSurfacePlannerAugmentsAttachedScheduleRequests() {
        let prompt = ActionSurfacePlanner.augmentedPrompt(
            text: "Extract the supplement table and make a schedule tracker with calendar invites.",
            attachmentNames: ["AV- Blueprxnt Client Master Sheet (1).xlsx"]
        )

        XCTAssertTrue(prompt.contains("AV- Blueprxnt Client Master Sheet (1).xlsx"))
        XCTAssertTrue(prompt.contains("trackers/briefings"))
        XCTAssertTrue(prompt.contains("calendar-worthy"))
        XCTAssertTrue(prompt.contains("Create a tracker for"))
        XCTAssertTrue(prompt.contains("Do not narrow this to one workflow"))
        XCTAssertTrue(prompt.contains("structured fields"))
        XCTAssertTrue(prompt.contains("missing_fields"))
        XCTAssertTrue(prompt.contains("near-widget action_plan"))
    }

    func testWidgetActionItemCreatesCalendarDraftOnlyWithConcreteDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_782_777_600) // 2026-06-30 00:00 UTC
        let action = WidgetActionItem(
            title: "Client supplement check-in",
            type: "calendar",
            detail: "Review the new supplement schedule.",
            schedule: nil,
            command: nil,
            source: "supplements.csv row 4",
            date: "2026-07-01",
            time: "9:30 AM",
            duration: "45 minutes",
            recurrence: "weekly",
            timezone: nil,
            location: "Phone",
            attendees: [],
            missingFields: [],
            confidence: 0.91,
            tone: nil
        )

        let draft = try XCTUnwrap(action.systemActionDraft(now: now, calendar: calendar))

        XCTAssertEqual(draft.kind, .calendarEvent)
        XCTAssertEqual(draft.title, "Client supplement check-in")
        XCTAssertEqual(draft.endDate?.timeIntervalSince(draft.startDate), 45 * 60)
        XCTAssertEqual(draft.location, "Phone")
        XCTAssertEqual(draft.recurrence, "weekly")
        XCTAssertTrue(draft.notes?.contains("supplements.csv row 4") ?? false)
    }

    func testWidgetActionItemParsesISOCalendarInvite() throws {
        let now = Date(timeIntervalSince1970: 1_782_777_600) // 2026-06-30 00:00 UTC
        let action = WidgetActionItem(
            title: "Dermatologist follow-up",
            type: "calendar invite",
            detail: "Confirm supplement interaction risk after lab results.",
            schedule: nil,
            command: nil,
            source: "Supplementation sheet",
            date: "2026-07-01T09:30:00-04:00",
            time: nil,
            duration: "1.5 hours",
            recurrence: nil,
            timezone: "America/New_York",
            location: "Phone",
            attendees: ["client@example.com"],
            missingFields: [],
            confidence: 0.93,
            tone: nil
        )

        let draft = try XCTUnwrap(action.systemActionDraft(now: now))

        XCTAssertEqual(draft.kind, .calendarEvent)
        XCTAssertEqual(draft.title, "Dermatologist follow-up")
        XCTAssertEqual(draft.endDate?.timeIntervalSince(draft.startDate), 90 * 60)
        XCTAssertEqual(draft.location, "Phone")
        XCTAssertEqual(draft.attendees, ["client@example.com"])
        XCTAssertTrue(draft.notes?.contains("Timezone: America/New_York") == true)
    }

    func testWidgetActionItemDoesNotCreateCalendarDraftForFuzzyTiming() {
        let action = WidgetActionItem(
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
            missingFields: ["exact bedtime"],
            confidence: 0.7,
            tone: nil
        )

        XCTAssertNil(action.systemActionDraft(now: Date(timeIntervalSince1970: 1_783_036_800)))
    }

    func testWidgetActionItemUsesTimeFieldForConcreteCalendarDate() throws {
        let now = Date(timeIntervalSince1970: 1_782_777_600) // 2026-06-30 00:00 UTC
        let action = WidgetActionItem(
            title: "Send deck review",
            type: "calendar",
            detail: nil,
            schedule: nil,
            command: nil,
            source: nil,
            date: nil,
            time: "2026-07-01 9:30 AM",
            duration: "30 minutes",
            recurrence: nil,
            timezone: nil,
            location: nil,
            attendees: [],
            missingFields: [],
            confidence: nil,
            tone: nil
        )

        let draft = try XCTUnwrap(action.systemActionDraft(now: now))

        XCTAssertEqual(draft.kind, .calendarEvent)
        XCTAssertEqual(draft.title, "Send deck review")
    }

    func testWidgetActionItemUsesProvidedTimezoneForConcreteCalendarDate() throws {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = Date(timeIntervalSince1970: 1_782_777_600) // 2026-06-30 00:00 UTC
        let action = WidgetActionItem(
            title: "NY check-in",
            type: "calendar",
            detail: nil,
            schedule: nil,
            command: nil,
            source: nil,
            date: "2026-07-01",
            time: "9:30 AM",
            duration: "30 minutes",
            recurrence: nil,
            timezone: "America/New_York",
            location: nil,
            attendees: [],
            missingFields: [],
            confidence: nil,
            tone: nil
        )

        let draft = try XCTUnwrap(action.systemActionDraft(now: now, calendar: utcCalendar))
        let expected = ISO8601DateFormatter().date(from: "2026-07-01T13:30:00Z")

        XCTAssertEqual(draft.startDate, expected)
        XCTAssertEqual(draft.timezone, "America/New_York")
    }

    func testWidgetActionItemRejectsStaleExplicitCalendarDate() {
        let action = WidgetActionItem(
            title: "Past check-in",
            type: "calendar",
            detail: nil,
            schedule: nil,
            command: nil,
            source: nil,
            date: "2026-05-01",
            time: "9:00 AM",
            duration: nil,
            recurrence: nil,
            timezone: nil,
            location: nil,
            attendees: [],
            missingFields: [],
            confidence: nil,
            tone: nil
        )

        XCTAssertNil(action.systemActionDraft(now: Date(timeIntervalSince1970: 1_783_036_800)))
    }

    func testWidgetActionItemCreatesGenericTrackerDraft() throws {
        let action = WidgetActionItem(
            title: "Supplement timing",
            type: "tracker",
            detail: "Track supplement timing from the extracted table.",
            schedule: "every morning at 8 am",
            command: "Create a tracker for supplement timing every morning at 8 am",
            source: "Supplementation sheet row 12",
            date: nil,
            time: "8 am",
            duration: nil,
            recurrence: "daily",
            timezone: nil,
            location: nil,
            attendees: [],
            missingFields: [],
            confidence: 0.86,
            tone: nil
        )

        let draft = try XCTUnwrap(action.appActionDraft())

        XCTAssertTrue(draft.isReady)
        XCTAssertEqual(draft.title, "Supplement timing")
        XCTAssertEqual(draft.schedule, .daily(hour: 8, minute: 0))
        XCTAssertTrue(draft.prompt.contains("Supplementation sheet row 12"))
        XCTAssertTrue(draft.prompt.contains("Run this recurring tracker"))
    }

    func testWidgetActionItemBlocksTrackerDraftWithFuzzyRoutine() throws {
        let action = WidgetActionItem(
            title: "Bedtime magnesium",
            type: "tracker",
            detail: "Timing is fuzzy.",
            schedule: "before bed",
            command: "Create a tracker for bedtime magnesium before bed",
            source: nil,
            date: nil,
            time: "before bed",
            duration: nil,
            recurrence: nil,
            timezone: nil,
            location: nil,
            attendees: [],
            missingFields: ["exact time"],
            confidence: 0.7,
            tone: nil
        )

        let draft = try XCTUnwrap(action.appActionDraft())

        XCTAssertFalse(draft.isReady)
        XCTAssertTrue(draft.missingFields.contains("exact time"))
        XCTAssertTrue(draft.missingFields.contains("recurrence"))
    }


    @MainActor
    func testChatStoreCreatesTrackerFromWidgetActionCard() throws {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        var created: Briefing?
        store.onCreateTracker = { created = $0 }
        let action = WidgetActionItem(
            title: "Supplement timing",
            type: "tracker",
            detail: "Track supplement timing from the extracted table.",
            schedule: "every morning at 8 am",
            command: "Create a tracker for supplement timing every morning at 8 am",
            source: "Supplementation sheet row 12",
            date: nil,
            time: "8 am",
            duration: nil,
            recurrence: "daily",
            timezone: nil,
            location: nil,
            attendees: [],
            missingFields: [],
            confidence: 0.86,
            tone: nil
        )

        store.createTracker(fromWidgetAction: action)

        let briefing = try XCTUnwrap(created)
        XCTAssertEqual(briefing.kind, .customPrompt)
        XCTAssertEqual(briefing.schedule, .daily(hour: 8, minute: 0))
        XCTAssertTrue(briefing.prompt.contains("Supplementation sheet row 12"))
        XCTAssertTrue(store.messages.last?.text.contains("Created a tracker") == true)
    }

    @MainActor
    func testChatStoreCreatesEscalatingTrackersFromGeneratedActionCards() throws {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        var created: [Briefing] = []
        store.onCreateTracker = { created.append($0) }

        let actions = [
            WidgetActionItem(
                title: "Rolex Submariner price",
                type: "tracker",
                detail: "Watch secondary-market price changes and explain what moved.",
                schedule: "every Monday at 9am",
                command: "Create a tracker for Rolex Submariner price every Monday at 9am",
                source: "Action card · watch market",
                date: nil,
                time: "9am",
                duration: nil,
                recurrence: "weekly",
                timezone: nil,
                location: nil,
                attendees: [],
                missingFields: [],
                confidence: 0.88,
                tone: nil
            ),
            WidgetActionItem(
                title: "Apple Vision Pro 2 release date",
                type: "watcher",
                detail: "Look for credible release-date changes and pre-order timing.",
                schedule: "every weekday at 7am",
                command: "Watch for Apple Vision Pro 2 release date updates every weekday at 7am",
                source: "Action card · product launch",
                date: nil,
                time: "7am",
                duration: nil,
                recurrence: "weekdays",
                timezone: nil,
                location: nil,
                attendees: [],
                missingFields: [],
                confidence: 0.9,
                tone: nil
            ),
            WidgetActionItem(
                title: "AI news digest",
                type: "digest",
                detail: "Summarize AI product launches, model releases, safety updates, and funding news.",
                schedule: "every morning at 8am",
                command: "Create an AI news digest every morning at 8am",
                source: "Action card · news workflow",
                date: nil,
                time: "8am",
                duration: nil,
                recurrence: "daily",
                timezone: nil,
                location: nil,
                attendees: [],
                missingFields: [],
                confidence: 0.91,
                tone: nil
            )
        ]

        actions.forEach { store.createTracker(fromWidgetAction: $0) }

        XCTAssertEqual(created.count, 3)
        XCTAssertEqual(created.map(\.kind), [.customPrompt, .customPrompt, .customPrompt])
        XCTAssertEqual(created[0].schedule, .weekly(weekday: 2, hour: 9, minute: 0))
        XCTAssertTrue(created[0].prompt.contains("Rolex Submariner price"))
        XCTAssertTrue(created[0].prompt.contains("Action card · watch market"))
        XCTAssertEqual(created[1].schedule, .weekdays(hour: 7, minute: 0))
        XCTAssertTrue(created[1].prompt.contains("Apple Vision Pro 2 release date"))
        XCTAssertEqual(created[2].schedule, .daily(hour: 8, minute: 0))
        XCTAssertTrue(created[2].prompt.contains("AI news digest"))
        XCTAssertEqual(store.messages.filter { $0.text.contains("Created a tracker") }.count, 3)
    }


    @MainActor
    func testChatStoreStagesFuzzyWidgetTrackerInsteadOfCreatingIt() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        var created: Briefing?
        store.onCreateTracker = { created = $0 }
        let action = WidgetActionItem(
            title: "Bedtime magnesium",
            type: "tracker",
            detail: "Timing is fuzzy.",
            schedule: "before bed",
            command: "Create a tracker for bedtime magnesium before bed",
            source: nil,
            date: nil,
            time: "before bed",
            duration: nil,
            recurrence: nil,
            timezone: nil,
            location: nil,
            attendees: [],
            missingFields: ["exact time"],
            confidence: 0.7,
            tone: nil
        )

        store.createTracker(fromWidgetAction: action)

        XCTAssertNil(created)
        XCTAssertEqual(store.draft, "Create a tracker for bedtime magnesium before bed")
        XCTAssertTrue(store.messages.isEmpty)
    }

    func testQuickIntentParsesTracker() throws {
        let intent = QuickIntentParser.parse(
            "create a tracker to tell me the eth price every morning at 8 am using council"
        )
        guard case let .createTracker(spec) = intent else {
            return XCTFail("Expected a createTracker intent, got \(String(describing: intent)).")
        }
        XCTAssertEqual(spec.kind, .cryptoPrice)
        XCTAssertEqual(spec.subject, "ethereum")
        XCTAssertEqual(spec.schedule, .daily(hour: 8, minute: 0))
        // A price is a single deterministic value — council is ignored here.
        XCTAssertFalse(spec.council)
    }

    func testQuickIntentParsesResearchAndWatchForRecurringTrackers() throws {
        let researchIntent = QuickIntentParser.parse(
            "research latest Claude Code release notes every 6 hours and tell me what changed"
        )
        guard case let .createTracker(researchSpec) = researchIntent else {
            return XCTFail("Expected a recurring research tracker, got \(String(describing: researchIntent)).")
        }
        XCTAssertEqual(researchSpec.kind, .customPrompt)
        XCTAssertEqual(researchSpec.schedule, .everyNHours(6))
        XCTAssertTrue(try XCTUnwrap(researchSpec.prompt).lowercased().contains("claude code release notes"))

        let watchIntent = QuickIntentParser.parse(
            "watch for new arxiv papers about TEE attestation every weekday at 7am"
        )
        guard case let .createTracker(watchSpec) = watchIntent else {
            return XCTFail("Expected a watch-for recurring tracker, got \(String(describing: watchIntent)).")
        }
        XCTAssertEqual(watchSpec.kind, .customPrompt)
        XCTAssertEqual(watchSpec.schedule, .weekdays(hour: 7, minute: 0))
        XCTAssertTrue(try XCTUnwrap(watchSpec.prompt).lowercased().contains("arxiv papers"))
    }

    func testQuickIntentParsesWeekdayRecurringTracker() throws {
        let intent = QuickIntentParser.parse("track vendor SLA changes every Tuesday at 6pm")
        guard case let .createTracker(spec) = intent else {
            return XCTFail("Expected weekly recurring tracker, got \(String(describing: intent)).")
        }

        XCTAssertEqual(spec.kind, .customPrompt)
        XCTAssertEqual(spec.schedule, .weekly(weekday: 3, hour: 18, minute: 0))
        XCTAssertTrue(try XCTUnwrap(spec.prompt).lowercased().contains("vendor sla changes"))
    }

    func testQuickIntentRecurringReminderBecomesScheduledTracker() throws {
        let intent = QuickIntentParser.parse("remind me to take creatine every morning at 8 am")
        guard case let .createTracker(spec) = intent else {
            return XCTFail("Expected recurring reminder to become a scheduled tracker, got \(String(describing: intent)).")
        }

        XCTAssertEqual(spec.kind, .customPrompt)
        XCTAssertEqual(spec.schedule, .daily(hour: 8, minute: 0))
        XCTAssertEqual(spec.title, "take creatine")
        XCTAssertTrue(try XCTUnwrap(spec.prompt).contains("Recurring reminder: take creatine"))
        XCTAssertNil(QuickIntentParser.parse("remind me to take magnesium before bed"))
    }

    func testBriefingBuilderPlannerCreatesGenericRecurringDraft() throws {
        let plan = BriefingBuilderPlanner.plan(from: "check Claude Code release notes every 6 hours")

        XCTAssertEqual(plan.draft.kind, .customPrompt)
        XCTAssertEqual(plan.draft.schedule, .everyNHours(6))
        XCTAssertEqual(plan.draft.title, "Claude Code release notes")
        XCTAssertTrue(plan.draft.prompt.contains("Claude Code release notes"))
        XCTAssertTrue(plan.reply.contains("Every 6h"))
    }

    func testBriefingBuilderPlannerCanStageOpenEndedActionBriefing() {
        let plan = BriefingBuilderPlanner.plan(
            from: "Brief me on client supplement actions every morning"
        )

        XCTAssertEqual(plan.draft.kind, .customPrompt)
        XCTAssertEqual(plan.draft.schedule, .daily(hour: 8, minute: 0))
        // Tracker titles are intentionally title-cased (first letter upper, rest
        // case-preserved) by QuickIntentTrackerParser; the prompt keeps the
        // verbatim lowercased subject.
        XCTAssertEqual(plan.draft.title, "Client supplement actions")
        XCTAssertTrue(plan.draft.prompt.contains("client supplement actions"))
        XCTAssertTrue(plan.draft.prompt.contains("calendar-worthy"))
        XCTAssertTrue(plan.reply.contains("Daily"))
    }

    func testBriefingBuilderPlannerRoutesDataWorkflowsThroughModel() throws {
        let price = BriefingBuilderPlanner.plan(from: "create an ETH price tracker every morning")
        XCTAssertEqual(price.draft.kind, .customPrompt)
        XCTAssertNil(price.draft.accountID)
        XCTAssertTrue(price.draft.prompt.contains("Run this recurring workflow through chat"))
        XCTAssertTrue(price.draft.prompt.contains("hardcoded defaults"))
        XCTAssertTrue(price.draft.prompt.contains("ETH"))

        let news = BriefingBuilderPlanner.plan(from: "create a daily news tracker every morning")
        XCTAssertEqual(news.draft.kind, .customPrompt)
        XCTAssertNil(news.draft.accountID)
        XCTAssertTrue(news.draft.prompt.lowercased().contains("top news"))

        let watchlist = BriefingBuilderPlanner.plan(from: "track ETH, NEAR and Tesla every morning")
        XCTAssertEqual(watchlist.draft.kind, .customPrompt)
        XCTAssertNil(watchlist.draft.accountID)
        XCTAssertTrue(watchlist.draft.prompt.contains("ETH"))
        XCTAssertTrue(watchlist.draft.prompt.contains("TSLA"))
    }

    func testEscalatingGenerativeTrackerMatrixCoversPricesReleasesAndDigest() throws {
        guard case let .createTracker(tokenPrice) = QuickIntentParser.parse("track NEAR token price every morning at 8am") else {
            return XCTFail("Expected a NEAR token price tracker.")
        }
        XCTAssertEqual(tokenPrice.kind, .cryptoPrice)
        XCTAssertEqual(tokenPrice.subject, "near")
        XCTAssertEqual(tokenPrice.schedule, .daily(hour: 8, minute: 0))

        guard case let .createTracker(watchPrice) = QuickIntentParser.parse("track the price of a Rolex Submariner every Monday at 9am") else {
            return XCTFail("Expected an arbitrary watch-price tracker.")
        }
        XCTAssertEqual(watchPrice.kind, .customPrompt)
        XCTAssertEqual(watchPrice.schedule, .weekly(weekday: 2, hour: 9, minute: 0))
        XCTAssertTrue(try XCTUnwrap(watchPrice.prompt).contains("Rolex Submariner"))
        XCTAssertTrue(try XCTUnwrap(watchPrice.prompt).lowercased().contains("web search"))

        guard case let .createTracker(releaseMonitor) = QuickIntentParser.parse("watch for Apple Vision Pro 2 release date updates every weekday at 7am") else {
            return XCTFail("Expected a product-release monitor.")
        }
        XCTAssertEqual(releaseMonitor.kind, .customPrompt)
        XCTAssertEqual(releaseMonitor.title, "Apple Vision Pro 2 release date")
        XCTAssertEqual(releaseMonitor.schedule, .weekdays(hour: 7, minute: 0))
        XCTAssertTrue(try XCTUnwrap(releaseMonitor.prompt).lowercased().contains("release date"))
        XCTAssertTrue(try XCTUnwrap(releaseMonitor.prompt).lowercased().contains("apple vision pro 2"))

        guard case let .createTracker(releaseMonitorWithCondition) = QuickIntentParser.parse("Watch for Apple Vision Pro 2 release date updates every weekday at 7am and tell me if preorder timing changes.") else {
            return XCTFail("Expected a product-release monitor with condition cue.")
        }
        XCTAssertEqual(releaseMonitorWithCondition.title, "Apple Vision Pro 2 release date")
        let releasePrompt = try XCTUnwrap(releaseMonitorWithCondition.prompt)
        XCTAssertTrue(releasePrompt.contains("Run this recurring task: Apple Vision Pro 2 release date. Watch for preorder timing changes."))
        XCTAssertFalse(releasePrompt.contains("updates and tell me"))

        guard case let .createTracker(aiDigest) = QuickIntentParser.parse("create an AI news digest daily at 8am") else {
            return XCTFail("Expected an AI news digest tracker.")
        }
        XCTAssertEqual(aiDigest.kind, .customPrompt)
        XCTAssertEqual(aiDigest.title, "AI news digest")
        XCTAssertEqual(aiDigest.schedule, .daily(hour: 8, minute: 0))
        let digestPrompt = try XCTUnwrap(aiDigest.prompt).lowercased()
        XCTAssertTrue(digestPrompt.contains("ai news"))
        XCTAssertTrue(digestPrompt.contains("digest"))

        guard case let .createTracker(productReleaseDigest) = QuickIntentParser.parse("Create an AI product release digest every weekday at 8am covering model launches, developer tools, safety updates, and pricing changes.") else {
            return XCTFail("Expected a product-release digest tracker.")
        }
        XCTAssertEqual(productReleaseDigest.title, "AI product release digest")
        XCTAssertEqual(productReleaseDigest.schedule, .weekdays(hour: 8, minute: 0))

        let generatedAction = WidgetActionItem(
            title: "AI news digest",
            type: "digest",
            detail: "Summarize AI product launches, model releases, safety updates, and funding news.",
            schedule: "every morning at 8 am",
            command: "Create an AI news digest every morning at 8 am",
            source: "Generated action card",
            date: nil,
            time: "8 am",
            duration: nil,
            recurrence: "daily",
            timezone: nil,
            location: nil,
            attendees: [],
            missingFields: [],
            confidence: 0.91,
            tone: nil
        )
        let draft = try XCTUnwrap(generatedAction.appActionDraft())
        XCTAssertTrue(draft.isReady)
        XCTAssertEqual(draft.kind, .tracker)
        XCTAssertEqual(draft.schedule, .daily(hour: 8, minute: 0))
        XCTAssertTrue(draft.prompt.contains("AI news digest"))
        XCTAssertTrue(draft.prompt.contains("Generated action card"))
    }

    func testEscalatingCurrentEventAndRegulatoryWorkflowsStayUserGrounded() throws {
        guard case let .createTracker(currentDigest) = QuickIntentParser.parse("Create a daily digest at 8am for SpaceX IPO, Iran war peace-talks status, and AI model releases with links.") else {
            return XCTFail("Expected a current-event digest tracker.")
        }
        XCTAssertEqual(currentDigest.kind, .customPrompt)
        XCTAssertEqual(currentDigest.schedule, .daily(hour: 8, minute: 0))
        XCTAssertFalse(currentDigest.title.localizedCaseInsensitiveContains("daily"))
        let currentPrompt = try XCTUnwrap(currentDigest.prompt).lowercased()
        XCTAssertTrue(currentPrompt.contains("spacex ipo"))
        XCTAssertTrue(currentPrompt.contains("iran war"))
        XCTAssertTrue(currentPrompt.contains("ai model releases"))

        guard case let .createTracker(governanceMonitor) = QuickIntentParser.parse("Track NEAR token unlock schedule and governance votes every Monday at noon.") else {
            return XCTFail("Expected a token/governance monitor.")
        }
        XCTAssertEqual(governanceMonitor.kind, .customPrompt)
        XCTAssertEqual(governanceMonitor.schedule, .weekly(weekday: 2, hour: 12, minute: 0))
        XCTAssertEqual(governanceMonitor.title, "NEAR token unlock schedule and governance votes")
        XCTAssertTrue(try XCTUnwrap(governanceMonitor.prompt).localizedCaseInsensitiveContains("web search"))

        guard case let .createTracker(regulatoryWatch) = QuickIntentParser.parse("Watch for FDA GLP-1 safety label changes every weekday at 7am.") else {
            return XCTFail("Expected a regulatory watch tracker.")
        }
        XCTAssertEqual(regulatoryWatch.kind, .customPrompt)
        XCTAssertEqual(regulatoryWatch.schedule, .weekdays(hour: 7, minute: 0))
        XCTAssertEqual(regulatoryWatch.title, "FDA GLP-1 safety label changes")
        XCTAssertTrue(try XCTUnwrap(regulatoryWatch.prompt).localizedCaseInsensitiveContains("fda glp-1"))
    }

    func testQuickIntentDoesNotCreateTrackerWithoutSubject() {
        // No trackable subject → falls through to the model, not an ETH default.
        XCTAssertNil(QuickIntentParser.parse("remind me to stretch every morning"))
        // Account tracker with no id → asks for the account instead of
        // scheduling a fetch that can never resolve.
        XCTAssertEqual(
            QuickIntentParser.parse("set up a daily briefing for my near account every weekday at 7am"),
            .requestNearAccountTracker(schedule: .weekdays(hour: 7, minute: 0))
        )
    }

    func testQuickIntentTopicNewsTrackerBecomesWebGroundedPrompt() throws {
        let intent = QuickIntentParser.parse("track global politics news every morning at 8am")
        guard case let .createTracker(spec) = intent else {
            return XCTFail("Expected a createTracker intent, got \(String(describing: intent)).")
        }
        XCTAssertEqual(spec.kind, .customPrompt)
        XCTAssertEqual(spec.schedule, .daily(hour: 8, minute: 0))
        let prompt = try XCTUnwrap(spec.prompt).lowercased()
        XCTAssertTrue(prompt.contains("global politics"), "Prompt should carry the topic: \(prompt)")
        XCTAssertTrue(prompt.contains("web search"), "Topic news should be web-grounded: \(prompt)")
    }

    func testQuickIntentBareNewsTrackerStaysGenericFeed() throws {
        let intent = QuickIntentParser.parse("create a daily news tracker every morning")
        guard case let .createTracker(spec) = intent else {
            return XCTFail("Expected a createTracker intent, got \(String(describing: intent)).")
        }
        XCTAssertEqual(spec.kind, .dailyNews)
    }

    func testQuickIntentVerboseTopicBriefingKeepsUserPromptNotGenericFeed() throws {
        // The user's real phrasing that used to become a generic BBC daily-news
        // feed at 9am, discarding "global politics". It must instead become a
        // web-grounded custom-prompt briefing that carries the topic.
        let intent = QuickIntentParser.parse(
            "can you create a global politics briefing at 9 am every morning that pulls from top politics news and surfaces it please"
        )
        guard case let .createTracker(spec) = intent else {
            return XCTFail("Expected a createTracker intent, got \(String(describing: intent)).")
        }
        XCTAssertEqual(spec.kind, .customPrompt, "Topic briefing must not collapse to the generic dailyNews feed.")
        XCTAssertEqual(spec.schedule, .daily(hour: 9, minute: 0))
        let prompt = try XCTUnwrap(spec.prompt).lowercased()
        XCTAssertTrue(prompt.contains("global politics"), "Prompt should keep the topic: \(prompt)")
    }


    @MainActor
    func testCryptoPriceTrackerWithoutSubjectReturnsNilNotEthereum() async {
        // INPUT-DISCARD: a nil-subject cryptoPrice tracker must NOT silently
        // present Ethereum's price as if it were the tracked coin.
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        let briefing = Briefing(title: "x", prompt: "p", schedule: .daily(hour: 8, minute: 0), kind: .cryptoPrice)
        let outcome = await store.runBriefing(briefing)
        if case let .delivered(widget) = outcome {
            XCTFail("A nil-subject cryptoPrice tracker must not deliver a widget, got \(widget).")
        }
    }

    func testTopicNewsTrackerSurvivesStopwordSubstrings() throws {
        // Regression: "sand mining" must not be rejected by an "and" substring
        // match — the topic-cleanliness check is token-based.
        let intent = QuickIntentParser.parse("track sand mining news every morning")
        guard case let .createTracker(spec) = intent else {
            return XCTFail("Expected createTracker, got \(String(describing: intent)).")
        }
        XCTAssertEqual(spec.kind, .customPrompt)
        let prompt = try XCTUnwrap(spec.prompt).lowercased()
        XCTAssertTrue(prompt.contains("sand mining"), "topic preserved: \(prompt)")
    }

    func testChartTimeframeParsingForTrackerThreadReplies() {
        // A chart-timeframe follow-up maps to the CoinGecko days/label so a price
        // tracker thread can render a REAL historical chart instead of prose.
        func assertTF(_ input: String, _ days: String, _ label: String, line: UInt = #line) {
            guard let tf = QuickIntentParser.parseChartTimeframe(input) else {
                return XCTFail("Expected a timeframe for: \(input)", line: line)
            }
            XCTAssertEqual(tf.days, days, line: line)
            XCTAssertEqual(tf.label, label, line: line)
        }
        assertTF("show me the 1 year chart", "365", "1Y")
        assertTF("6 month chart", "180", "6M")
        assertTF("show me the 30 day history", "30", "1M")
        assertTF("all time chart", "max", "all time")
        // Not chart requests → nil (fall through to a prose answer).
        XCTAssertNil(QuickIntentParser.parseChartTimeframe("why is it up today"))
        XCTAssertNil(QuickIntentParser.parseChartTimeframe("what's driving this"))
        XCTAssertNil(QuickIntentParser.parseChartTimeframe("how did it do this month")) // no chart cue
    }

    func testStockTrackerCreation() throws {
        guard case let .createTracker(spec) = QuickIntentParser.parse("track Tesla stock every morning") else {
            return XCTFail("Expected a stock tracker.")
        }
        XCTAssertEqual(spec.kind, .stockPrice)
        XCTAssertEqual(spec.subject, "TSLA")
        guard case let .createTracker(nvda) = QuickIntentParser.parse("watch $NVDA daily") else {
            return XCTFail("Expected a stock tracker for $NVDA.")
        }
        XCTAssertEqual(nvda.kind, .stockPrice)
        XCTAssertEqual(nvda.subject, "NVDA")
    }

    func testWatchlistTrackerCreation() throws {
        guard case let .createTracker(spec) = QuickIntentParser.parse("track ETH, NEAR and Tesla every morning") else {
            return XCTFail("Expected a watchlist tracker.")
        }
        XCTAssertEqual(spec.kind, .watchlist)
        let parts = spec.subject?.split(separator: "|").map(String.init) ?? []
        XCTAssertEqual(parts.count, 3)
        XCTAssertTrue(spec.subject?.contains("stock:TSLA") == true, spec.subject ?? "nil")
    }


    @MainActor
    func testTrackerSteeringPinSnoozeAndSort() {
        let now = Date()
        let pastCreated = now.addingTimeInterval(-86_400 * 2)
        let a = Briefing(title: "A", prompt: "p", schedule: .daily(hour: 8, minute: 0), createdAt: pastCreated, kind: .dailyNews)
        let b = Briefing(title: "B", prompt: "p", schedule: .daily(hour: 8, minute: 0), createdAt: pastCreated, kind: .dailyNews)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("steer-\(UUID().uuidString).json")
        let store = BriefingStore(briefings: [a, b], fileURL: tempURL)
        // Both are due (createdAt is 2 days ago).
        XCTAssertEqual(store.dueBriefings(now: now).count, 2)
        // Pin B → it sorts to the top.
        store.setPinned(b, true)
        XCTAssertEqual(store.briefings.first?.id, b.id)
        // Snooze A → no longer due; B still due.
        store.snooze(a, days: 1)
        let due = store.dueBriefings(now: now)
        XCTAssertFalse(due.contains { $0.id == a.id })
        XCTAssertTrue(due.contains { $0.id == b.id })
        // End the snooze → A is due again.
        store.unsnooze(a)
        XCTAssertTrue(store.dueBriefings(now: now).contains { $0.id == a.id })
    }


    @MainActor
    func testCreateTrackerPromptLandsBriefingInStore() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("briefings-\(UUID().uuidString).json")
        let briefingStore = BriefingStore(briefings: [], fileURL: tempFile, runner: { _ in .failed(nil) })
        let chatStore = ChatStore(api: PrivateChatAPI(configuration: .production))
        chatStore.onCreateTracker = { [weak briefingStore] briefing in
            briefingStore?.add(briefing)
        }

        chatStore.draft = "create a tracker to tell me the eth price every morning at 8 am using council"
        chatStore.sendDraft()

        XCTAssertEqual(briefingStore.briefings.count, 1)
        let landed = try XCTUnwrap(briefingStore.briefings.first)
        XCTAssertEqual(landed.kind, .customPrompt)
        XCTAssertNil(landed.accountID)
        XCTAssertEqual(landed.schedule, .daily(hour: 8, minute: 0))
        XCTAssertEqual(landed.title, "ETH price")
        XCTAssertTrue(landed.prompt.contains("Run this recurring workflow through chat"))
        XCTAssertTrue(landed.prompt.contains("ETH"))
        XCTAssertFalse(landed.council)

        try? FileManager.default.removeItem(at: tempFile)
    }

    @MainActor
    func testProductionTrackerPersistenceDoesNotAutoRunNewTracker() async throws {
        final class RunCounter: @unchecked Sendable {
            var count = 0
        }

        let counter = RunCounter()
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("briefings-\(UUID().uuidString).json")
        let briefingStore = BriefingStore(briefings: [], fileURL: tempFile) { _ in
            counter.count += 1
            return .failed("Tracker should not run immediately after creation.")
        }
        let chatStore = ChatStore(api: PrivateChatAPI(configuration: .production))
        AppEnvironment.configureTrackerPersistence(chatStore: chatStore, briefingStore: briefingStore)

        chatStore.draft = "Track Nintendo Switch 2 OLED release date, preorder timing, and launch price every Friday at 9am with current sources; alert me if the date changes."
        chatStore.sendDraft()

        try await Task.sleep(nanoseconds: 150_000_000)

        let landed = try XCTUnwrap(briefingStore.briefings.first)
        XCTAssertEqual(counter.count, 0)
        XCTAssertNil(landed.lastFailureAt)
        XCTAssertNil(landed.lastFailureMessage)
        XCTAssertEqual(landed.status, .scheduled)
        XCTAssertEqual(chatStore.trackersProvider?().map(\.id), [landed.id])

        try? FileManager.default.removeItem(at: tempFile)
    }

    func testTrackerHistoryParsesValuesAndBuildsChart() throws {
        XCTAssertEqual(TrackerHistory.numericValue(from: "$14,500"), 14_500)
        XCTAssertEqual(TrackerHistory.numericValue(from: "$2.3M"), 2_300_000)
        XCTAssertEqual(try XCTUnwrap(TrackerHistory.numericValue(from: "1,234.50")), 1_234.5, accuracy: 0.001)
        XCTAssertNil(TrackerHistory.numericValue(from: "no number here"))

        // sampleDisplay prefers chart → metric → a $-number in the note.
        XCTAssertEqual(TrackerHistory.sampleDisplay(from: MessageWidget(kind: .metric, metric: WidgetMetric(value: "$14,500"))), "$14,500")
        XCTAssertEqual(TrackerHistory.sampleDisplay(from: MessageWidget(kind: .generic, note: "Currently about $14,800 as of today.")), "$14,800")

        // <2 samples → no chart; ≥2 → a chart over the values.
        let one = [TrackerSample(date: Date(), value: 14_000, display: "$14,000")]
        XCTAssertNil(TrackerHistory.chartWidget(title: "Rolex", history: one))
        let two = one + [TrackerSample(date: Date(), value: 14_800, display: "$14,800")]
        let chart = try XCTUnwrap(TrackerHistory.chartWidget(title: "Rolex", history: two))
        XCTAssertEqual(chart.kind, .chart)
        XCTAssertEqual(chart.chart?.points, [14_000, 14_800])
        XCTAssertEqual(chart.chart?.value, "$14,800")
        XCTAssertEqual(chart.chart?.trend, .up)

        // Significant-move detection: only a move ≥ threshold counts.
        XCTAssertNil(TrackerHistory.significantMove(in: one))            // <2 points
        let smallMove = [TrackerSample(date: Date(), value: 100, display: "$100"),
                         TrackerSample(date: Date(), value: 101, display: "$101")] // +1%
        XCTAssertNil(TrackerHistory.significantMove(in: smallMove, threshold: 0.03))
        let bigMove = [TrackerSample(date: Date(), value: 100, display: "$100"),
                       TrackerSample(date: Date(), value: 110, display: "$110")] // +10%
        XCTAssertEqual(try XCTUnwrap(TrackerHistory.significantMove(in: bigMove, threshold: 0.03)), 0.10, accuracy: 0.001)

        // Notification body surfaces the value + move (not a generic "ready").
        let body = TrackerHistory.notificationBody(history: two, fallback: chart)
        XCTAssertTrue(body.contains("$14,800"))
        XCTAssertTrue(body.contains("%"))
        // One sample → just the value; no history → the widget's headline value.
        XCTAssertEqual(TrackerHistory.notificationBody(history: one, fallback: chart), "$14,000")
        XCTAssertEqual(TrackerHistory.notificationBody(history: [], fallback: MessageWidget(kind: .metric, metric: WidgetMetric(value: "$2,019"))), "$2,019")
    }


    @MainActor
    func testConditionalBriefingPausesAfterFiringButPlainKeepsRunning() async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("briefings-\(UUID().uuidString).json")
        let alert = Briefing(title: "ETH alert", prompt: "", schedule: .everyNHours(3),
                             kind: .cryptoPrice, accountID: "ethereum",
                             condition: BriefingCondition(coinID: "ethereum", symbol: "ETH",
                                                          comparator: .below, threshold: 2_000))
        let plain = Briefing(title: "News", prompt: "p", schedule: .daily(hour: 8, minute: 0), kind: .dailyNews)
        let store = BriefingStore(briefings: [alert, plain], fileURL: tempFile,
                                  runner: { _ in .delivered(MessageWidget(kind: .generic, title: "x", note: "y")) })

        // A conditional alert that delivers a result is one-shot: it auto-pauses.
        await store.run(alert)
        let firedAlert = try XCTUnwrap(store.briefings.first { $0.id == alert.id })
        XCTAssertNotNil(firedAlert.latestResult)
        XCTAssertTrue(firedAlert.isPaused)

        // A plain recurring briefing keeps running after a result.
        await store.run(plain)
        let ranPlain = try XCTUnwrap(store.briefings.first { $0.id == plain.id })
        XCTAssertNotNil(ranPlain.latestResult)
        XCTAssertFalse(ranPlain.isPaused)

        try? FileManager.default.removeItem(at: tempFile)
    }

    func testBriefingDetailCopyIsWatcherAware() {
        let watcher = Briefing(
            title: "Rolex GMT-Master II Pepsi market prices Toronto",
            prompt: "Track Rolex prices with current sources and alert me below $15,000.",
            schedule: .weekly(weekday: 2, hour: 9, minute: 0),
            kind: .customPrompt
        )
        let briefing = Briefing(
            title: "AI news digest",
            prompt: "Summarize the top AI news every morning.",
            schedule: .daily(hour: 8, minute: 0),
            kind: .customPrompt
        )
        let pausedWatcher = Briefing(
            title: watcher.title,
            prompt: watcher.prompt,
            schedule: watcher.schedule,
            isPaused: true,
            kind: .customPrompt
        )

        XCTAssertEqual(BriefingDetailCopy.itemName(for: watcher), "watcher")
        XCTAssertEqual(BriefingDetailCopy.runAccessibilityLabel(for: watcher, isRunning: false), "Run now watcher")
        XCTAssertEqual(BriefingDetailCopy.runAccessibilityLabel(for: watcher, isRunning: true), "Running watcher")
        XCTAssertEqual(BriefingDetailCopy.pauseTitle(for: watcher), "Pause watcher")
        XCTAssertEqual(BriefingDetailCopy.pauseTitle(for: pausedWatcher), "Resume watcher")
        XCTAssertEqual(BriefingDetailCopy.planText(for: watcher), "Private watcher")
        XCTAssertEqual(BriefingDetailCopy.lastRunTitle(for: watcher), "Last checked")

        XCTAssertEqual(BriefingDetailCopy.itemName(for: briefing), "briefing")
        XCTAssertEqual(BriefingDetailCopy.runAccessibilityLabel(for: briefing, isRunning: false), "Run now briefing")
        XCTAssertEqual(BriefingDetailCopy.pauseTitle(for: briefing), "Pause briefing")
        XCTAssertEqual(BriefingDetailCopy.planText(for: briefing), "Private briefing")
        XCTAssertEqual(BriefingDetailCopy.lastRunTitle(for: briefing), "Last delivered")
    }

    func testThreadedBriefingMapsPendingWatcherAsVisualState() throws {
        let watcher = Briefing(
            title: "Rolex tracker",
            prompt: "Watch Rolex GMT-Master II Pepsi market prices and alert me when prices move.",
            schedule: .daily(hour: 8, minute: 0),
            kind: .customPrompt
        )

        let delivery = try XCTUnwrap(ThreadedBriefingView.deliveries(for: watcher).first)

        XCTAssertTrue(delivery.isPending)
        XCTAssertEqual(delivery.itemKind, .watcher)
        XCTAssertEqual(delivery.title, "Scheduled watcher")
        XCTAssertEqual(delivery.time, "—")
        XCTAssertEqual(delivery.body, "No check yet. The first result will appear here after the next scheduled run.")
        XCTAssertFalse(delivery.unread)
        XCTAssertNil(delivery.sourceStatusText)
        XCTAssertNil(delivery.widget)
    }

    func testThreadedBriefingMapsPendingBriefingAsVisualState() throws {
        let briefing = Briefing(
            title: "AI news digest",
            prompt: "Create an AI news digest every morning.",
            schedule: .daily(hour: 8, minute: 0),
            kind: .dailyNews
        )

        let delivery = try XCTUnwrap(ThreadedBriefingView.deliveries(for: briefing).first)

        XCTAssertTrue(delivery.isPending)
        XCTAssertEqual(delivery.itemKind, .briefing)
        XCTAssertEqual(delivery.title, "Scheduled briefing")
        XCTAssertEqual(delivery.body, "No delivery yet. The first brief will appear here after the next scheduled run.")
        XCTAssertFalse(delivery.unread)
        XCTAssertNil(delivery.sourceStatusText)
        XCTAssertNil(delivery.widget)
    }

    func testPendingDeliveryPresentationNormalizesLegacyPlainPendingBriefing() {
        let delivery = BriefingDelivery(
            dayLabel: "Today",
            time: "pending",
            title: "Tue 23 Jun · briefing",
            body: "No delivery yet — it will appear here after the next scheduled run.",
            itemKind: .briefing
        )

        let presentation = ThreadPendingDeliveryPresentation(delivery: delivery)

        XCTAssertEqual(presentation.title, "Scheduled briefing")
        XCTAssertEqual(presentation.body, "First brief scheduled. Delivery appears here after the next run.")
        XCTAssertEqual(presentation.statusLabel, "Scheduled")
        XCTAssertEqual(presentation.visualLabel, "BRIEF")
    }

    func testThreadedBriefingMapsPausedNeverRunAsPausedNotPending() throws {
        let briefing = Briefing(
            title: "AI news digest",
            prompt: "Create an AI news digest every morning.",
            schedule: .daily(hour: 8, minute: 0),
            isPaused: true,
            kind: .dailyNews
        )

        let delivery = try XCTUnwrap(ThreadedBriefingView.deliveries(for: briefing).first)

        XCTAssertFalse(delivery.isPending)
        XCTAssertEqual(delivery.title, "Paused briefing")
        XCTAssertEqual(delivery.body, "Paused. Resume this briefing when you want scheduled deliveries to continue.")
        XCTAssertFalse(delivery.unread)
        XCTAssertNil(delivery.widget)
    }


    @MainActor
    func testBriefingRunRecordsFailureStatusAndTimezone() async throws {
        let briefing = Briefing(
            title: "Supplement schedule",
            prompt: "Extract supplement rows and create reminders.",
            schedule: .daily(hour: 21, minute: 0),
            createdAt: Date(timeIntervalSince1970: 1_770_000_000),
            timeZoneIdentifier: "America/New_York"
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("briefings.json")
        let store = BriefingStore(briefings: [briefing], fileURL: fileURL) { _ in .failed(nil) }

        await store.run(briefing)

        let updated = try XCTUnwrap(store.briefings.first)
        XCTAssertEqual(updated.status, .failed)
        XCTAssertEqual(updated.timeZoneIdentifier, "America/New_York")
        XCTAssertNotNil(updated.lastFailureAt)
        XCTAssertEqual(updated.lastFailureMessage, "Run failed before producing a result.")
        XCTAssertNil(updated.lastRunAt)
        XCTAssertEqual(BriefingStore.widgetSummary(for: updated), "Run failed before producing a result.")
        XCTAssertEqual(updated.scheduleCalendar.timeZone.identifier, "America/New_York")

        let delivery = try XCTUnwrap(ThreadedBriefingView.deliveries(for: updated).first)
        XCTAssertNil(delivery.headline)
        XCTAssertEqual(delivery.body, "Run failed before producing a result.")
        XCTAssertEqual(delivery.summary, "Run failed before producing a result.")
        XCTAssertEqual(delivery.title, "The 9:00pm run didn't start")
        XCTAssertTrue(delivery.isFailure)
        XCTAssertNotEqual(delivery.time, "—")
    }

    @MainActor
    func testBriefingRunCarriesSpecificFailureMessageAndQuietRunClearsIt() async throws {
        let briefing = Briefing(
            title: "NEAR price",
            prompt: "Track the NEAR price.",
            schedule: .daily(hour: 8, minute: 0)
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("briefings.json")
        let restrictedCopy = "Private route is rate-limited for this session. Wait for the cooldown, or use the privacy proxy only for this turn. If it keeps failing after cooldown, sign out and back in."

        final class OutcomeBox: @unchecked Sendable { var outcome: BriefingRunOutcome = .quiet }
        let box = OutcomeBox()
        let store = BriefingStore(briefings: [briefing], fileURL: fileURL) { _ in box.outcome }

        // A failed run surfaces the specific route error, not a generic line.
        box.outcome = .failed(restrictedCopy)
        await store.run(briefing)
        var updated = try XCTUnwrap(store.briefings.first)
        XCTAssertEqual(updated.status, .failed)
        XCTAssertEqual(updated.lastFailureMessage, restrictedCopy)
        let failedDelivery = try XCTUnwrap(ThreadedBriefingView.deliveries(for: updated).first)
        XCTAssertTrue(failedDelivery.isFailure)
        XCTAssertEqual(failedDelivery.body, restrictedCopy)
        XCTAssertEqual(failedDelivery.title, "The 8:00am run didn't start")
        // The reason must ride in summary for the failure card.
        XCTAssertEqual(failedDelivery.summary, restrictedCopy)

        // A quiet check (e.g. an alert whose condition wasn't met) is NOT a
        // failure: it clears the stale failure record instead of re-recording it.
        box.outcome = .quiet
        await store.run(briefing)
        updated = try XCTUnwrap(store.briefings.first)
        XCTAssertNil(updated.lastFailureAt)
        XCTAssertNil(updated.lastFailureMessage)
        XCTAssertNotEqual(updated.status, .failed)
        let quietDelivery = try XCTUnwrap(ThreadedBriefingView.deliveries(for: updated).first)
        XCTAssertFalse(quietDelivery.isFailure)
    }

    func testBriefingFailureCopyDistinguishesSignInFailuresFromRouteAdvice() throws {
        let signInFailure = Briefing(
            title: "Research brief",
            prompt: "Research saved topic.",
            schedule: .daily(hour: 8, minute: 0),
            lastFailureAt: Date(timeIntervalSince1970: 1_783_036_800),
            lastFailureMessage: "Could not start a private conversation for this run. Check your connection or sign in again, then run it now."
        )
        let signInDelivery = try XCTUnwrap(ThreadedBriefingView.deliveries(for: signInFailure).first)
        XCTAssertEqual(
            signInDelivery.summary,
            "The plan wasn't signed in when the brief was due. Re-run now, or check the plan's sign-in to resume the schedule."
        )

        let routeFailureText = "Private route is rate-limited for this session. Wait for the cooldown, or use the privacy proxy only for this turn. If it keeps failing after cooldown, sign out and back in."
        let routeFailure = Briefing(
            title: "NEAR price",
            prompt: "Track price.",
            schedule: .daily(hour: 8, minute: 0),
            lastFailureAt: Date(timeIntervalSince1970: 1_783_036_800),
            lastFailureMessage: routeFailureText
        )
        let routeDelivery = try XCTUnwrap(ThreadedBriefingView.deliveries(for: routeFailure).first)
        XCTAssertEqual(routeDelivery.summary, routeFailureText)
    }

    func testThreadedBriefingFailureDeliveryMapsRawBackendFailure() throws {
        let rawFailure = "OpenAI API error: API error: error sending request for url (https://cloud-api.near.ai/v1/responses)"
        let briefing = Briefing(
            title: "Private route smoke test",
            prompt: "Check whether the private route works.",
            schedule: .daily(hour: 8, minute: 0),
            lastFailureAt: Date(timeIntervalSince1970: 1_783_036_800),
            lastFailureMessage: rawFailure
        )

        let delivery = try XCTUnwrap(ThreadedBriefingView.deliveries(for: briefing).first)

        XCTAssertTrue(delivery.isFailure)
        XCTAssertEqual(delivery.summary, "Can't reach the private backend right now — retry in a moment.")
        XCTAssertFalse((delivery.summary ?? "").contains("OpenAI API error"))
        XCTAssertFalse((delivery.summary ?? "").contains("cloud-api.near.ai"))
    }

    func testThreadedBriefingMapsNewsWidgetSourcesIntoDeliveryFooter() throws {
        let widget = MessageWidget(
            kind: .newsBrief,
            title: "AI news digest",
            newsBrief: WidgetNewsBrief(
                heading: "Today · 2 stories",
                stories: [
                    WidgetNewsStory(
                        title: "Model release shipped",
                        tag: "AI",
                        sources: [
                            WidgetNewsSource(label: "T", color: "#000000", domain: "techcrunch.com"),
                            WidgetNewsSource(label: "A", color: "#ff7e1c", domain: "axios.com")
                        ]
                    ),
                    WidgetNewsStory(
                        title: "Safety update posted",
                        tag: "Policy",
                        sources: [
                            WidgetNewsSource(label: "A", color: "#ff7e1c", domain: "axios.com")
                        ]
                    )
                ]
            )
        )
        let briefing = Briefing(
            title: "AI news digest",
            prompt: "Create an AI news digest daily at 8am with links.",
            schedule: .daily(hour: 8, minute: 0),
            lastRunAt: Date(timeIntervalSince1970: 1_783_036_800),
            latestResult: widget,
            kind: .customPrompt
        )

        let delivery = try XCTUnwrap(ThreadedBriefingView.deliveries(for: briefing).first)

        XCTAssertEqual(delivery.sources.map(\.letter), ["T", "A"])
        XCTAssertEqual(delivery.sources.map(\.colorHex), ["#000000", "#ff7e1c"])
        XCTAssertEqual(delivery.sources.map(\.faviconDomain), ["techcrunch.com", "axios.com"])
        XCTAssertEqual(delivery.sources.map(\.allowsNetworkFavicon), [true, true])
        XCTAssertNil(delivery.sourceStatusText)
    }

    func testThreadedBriefingMapsNewsStoryURLAsSourceEvidence() throws {
        let widget = MessageWidget(
            kind: .newsBrief,
            title: "Daily briefing",
            newsBrief: WidgetNewsBrief(
                heading: "Today · 1 story",
                stories: [
                    WidgetNewsStory(
                        title: "Iran talks resume",
                        tag: "World",
                        sources: [],
                        url: "https://www.reuters.com/world/middle-east/iran-talks-resume/"
                    )
                ]
            )
        )
        let briefing = Briefing(
            title: "AI news digest",
            prompt: "Create a daily news digest with links.",
            schedule: .daily(hour: 8, minute: 0),
            lastRunAt: Date(timeIntervalSince1970: 1_783_036_800),
            latestResult: widget,
            kind: .dailyNews
        )

        let delivery = try XCTUnwrap(ThreadedBriefingView.deliveries(for: briefing).first)

        XCTAssertEqual(delivery.sources.map(\.letter), ["R"])
        XCTAssertEqual(delivery.sources.map(\.faviconDomain), ["reuters.com"])
        XCTAssertEqual(delivery.sources.map(\.allowsNetworkFavicon), [true])
        XCTAssertNil(delivery.sourceStatusText)
    }

    func testThreadedBriefingMarksWebGroundedChartDeliveryAsCurrentSourceRun() throws {
        let widget = MessageWidget(
            kind: .chart,
            title: "Rolex GMT-Master II",
            chart: WidgetChart(
                label: "Steel GMT-Master II secondary market",
                value: "~$20,200",
                delta: "+67% over retail",
                trend: .up,
                points: [18_700, 19_200, 20_200],
                caption: "Steel refs trade 60-75% above retail"
            )
        )
        let briefing = Briefing(
            title: "Rolex GMT-Master II",
            prompt: "Using web search, find the latest Rolex GMT-Master II market price with current sources and report it concisely.",
            schedule: .daily(hour: 8, minute: 0),
            lastRunAt: Date(timeIntervalSince1970: 1_783_036_800),
            latestResult: widget,
            kind: .customPrompt
        )

        let delivery = try XCTUnwrap(ThreadedBriefingView.deliveries(for: briefing).first)

        XCTAssertTrue(delivery.sources.isEmpty)
        XCTAssertEqual(delivery.sourceStatusText, "Current-source run")
    }
}
