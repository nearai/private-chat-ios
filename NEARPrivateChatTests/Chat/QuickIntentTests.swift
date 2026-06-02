import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testQuickIntentParsesPriceQuestions() {
        XCTAssertEqual(
            QuickIntentParser.parse("what is the eth price"),
            .price(coinID: "ethereum", symbol: "ETH")
        )
        XCTAssertEqual(
            QuickIntentParser.parse("near price"),
            .price(coinID: "near", symbol: "NEAR")
        )
        XCTAssertEqual(
            QuickIntentParser.parse("what's bitcoin worth"),
            .price(coinID: "bitcoin", symbol: "BTC")
        )
    }

    func testQuickIntentParsesWeather() {
        XCTAssertEqual(QuickIntentParser.parse("what's the weather in Tokyo"), .weather(query: "tokyo"))
        XCTAssertEqual(QuickIntentParser.parse("weather in new york"), .weather(query: "new york"))
        XCTAssertEqual(QuickIntentParser.parse("London forecast"), .weather(query: "london"))
        // No extractable place → falls through to the model.
        XCTAssertNil(QuickIntentParser.parse("what's the weather"))
    }

    func testQuickIntentParsesWorldTime() {
        XCTAssertEqual(QuickIntentParser.parse("what time is it in Tokyo"), .worldTime(query: "tokyo"))
        XCTAssertEqual(QuickIntentParser.parse("London time"), .worldTime(query: "london"))
        // "time" with no place is not a world-time query.
        XCTAssertNil(QuickIntentParser.parse("what time do you close"))
        XCTAssertNil(QuickIntentParser.parse("time to go home"))
        // Duration fillers are not places.
        XCTAssertNil(QuickIntentParser.parse("what time is it in a bit"))
        XCTAssertNil(QuickIntentParser.parse("set a timer for 5 minutes"))
    }

    func testQuickIntentParsesCurrencyConversion() {
        XCTAssertEqual(QuickIntentParser.parse("convert 100 usd to eur"), .fx(amount: 100, from: "USD", to: "EUR"))
        XCTAssertEqual(QuickIntentParser.parse("how much is 50 gbp in usd"), .fx(amount: 50, from: "GBP", to: "USD"))
        XCTAssertEqual(QuickIntentParser.parse("euros to yen"), .fx(amount: 1, from: "EUR", to: "JPY"))
        // Same currency or non-currency words don't trigger a conversion.
        XCTAssertNil(QuickIntentParser.parse("translate this to spanish"))
    }

    func testQuickIntentParsesMemory() {
        XCTAssertEqual(QuickIntentParser.parse("remember that I prefer concise answers"), .remember(text: "I prefer concise answers"))
        XCTAssertEqual(QuickIntentParser.parse("Remember my anniversary is June 3"), .remember(text: "my anniversary is June 3"))
        XCTAssertEqual(QuickIntentParser.parse("what do you remember"), .recallMemory)
        // Original casing is preserved for the stored fact.
        guard case let .remember(text) = QuickIntentParser.parse("remember that my dog is named Biscuit") else {
            return XCTFail("Expected a remember intent.")
        }
        XCTAssertTrue(text.contains("Biscuit"))
        // Not a store/recall command.
        XCTAssertNil(QuickIntentParser.parse("tell me about the memory of a computer"))
    }

    func testParsePriceConditionRecognizesThresholds() {
        XCTAssertEqual(QuickIntentParser.parsePriceCondition("when eth drops below 2000")?.0, .below)
        XCTAssertEqual(QuickIntentParser.parsePriceCondition("when eth drops below 2000")?.1, 2000)
        XCTAssertEqual(QuickIntentParser.parsePriceCondition("if btc goes above $80k")?.0, .above)
        XCTAssertEqual(QuickIntentParser.parsePriceCondition("if btc goes above $80k")?.1, 80_000)
        XCTAssertEqual(QuickIntentParser.parsePriceCondition("near over 5")?.0, .above)
        XCTAssertEqual(QuickIntentParser.parsePriceCondition("eth under 1,500")?.1, 1_500)
        XCTAssertEqual(QuickIntentParser.parsePriceCondition("eth above $1.2m")?.1, 1_200_000)
        // No comparator/number → nil.
        XCTAssertNil(QuickIntentParser.parsePriceCondition("tell me about ethereum"))
    }

    func testQuickIntentParsesConditionalAlert() {
        guard case let .createTracker(spec) = QuickIntentParser.parse("notify me when ETH drops below $2,000") else {
            return XCTFail("Expected a conditional tracker.")
        }
        XCTAssertEqual(spec.kind, .cryptoPrice)
        XCTAssertEqual(spec.subject, "ethereum")
        XCTAssertEqual(spec.condition?.comparator, .below)
        XCTAssertEqual(spec.condition?.threshold, 2_000)
        XCTAssertEqual(spec.condition?.symbol, "ETH")
        // No explicit cadence → defaults to the few-hour watch cycle.
        XCTAssertEqual(spec.schedule, .everyNHours(3))

        // An explicit cadence is honored.
        guard case let .createTracker(daily) = QuickIntentParser.parse("alert me if bitcoin goes above 80k every morning") else {
            return XCTFail("Expected a conditional tracker.")
        }
        XCTAssertEqual(daily.condition?.comparator, .above)
        XCTAssertEqual(daily.condition?.threshold, 80_000)
        XCTAssertEqual(daily.schedule, .daily(hour: 8, minute: 0))

        // A plain price tracker (no comparator) is NOT conditional.
        guard case let .createTracker(plain) = QuickIntentParser.parse("create an eth price tracker every morning") else {
            return XCTFail("Expected a plain tracker.")
        }
        XCTAssertNil(plain.condition)

        // A bare mid-sentence "if" question is NOT an alert (goes to the model).
        XCTAssertNil(QuickIntentParser.parse("explain what happens if eth hits 5000"))
    }

    func testQuickIntentParsesPassiveMemoryControls() {
        XCTAssertEqual(QuickIntentParser.parse("stop learning about me"), .setMemoryCapture(enabled: false))
        XCTAssertEqual(QuickIntentParser.parse("turn off auto memory"), .setMemoryCapture(enabled: false))
        XCTAssertEqual(QuickIntentParser.parse("stop auto memory"), .setMemoryCapture(enabled: false))
        XCTAssertEqual(QuickIntentParser.parse("start learning about me"), .setMemoryCapture(enabled: true))
        XCTAssertEqual(QuickIntentParser.parse("forget what you learned automatically"), .forgetAutoLearned)
        // The controls don't swallow an ordinary remember or a full wipe.
        XCTAssertEqual(QuickIntentParser.parse("remember that I like tea"), .remember(text: "I like tea"))
        XCTAssertEqual(QuickIntentParser.parse("forget everything"), .forget(text: nil))
        // "stop auto…" of unrelated things must NOT toggle passive memory.
        XCTAssertNotEqual(QuickIntentParser.parse("stop autocorrect"), .setMemoryCapture(enabled: false))
        XCTAssertNotEqual(QuickIntentParser.parse("how do I stop automatic updates"), .setMemoryCapture(enabled: false))
    }

    func testQuickIntentParsesSearchHistory() {
        XCTAssertEqual(QuickIntentParser.parse("search my chats for bitcoin"), .searchHistory(query: "bitcoin"))
        XCTAssertEqual(QuickIntentParser.parse("what did I say about my budget?"), .searchHistory(query: "my budget"))
        XCTAssertEqual(QuickIntentParser.parse("find where I talked about the Lisbon trip"),
                       .searchHistory(query: "the Lisbon trip"))
        // A plain question is not a history search.
        XCTAssertNotEqual(QuickIntentParser.parse("tell me about bitcoin"), .searchHistory(query: "bitcoin"))
    }

    func testQuickIntentParsesTrendingCrypto() {
        XCTAssertEqual(QuickIntentParser.parse("what's trending in crypto"), .trendingCrypto)
        XCTAssertEqual(QuickIntentParser.parse("show me trending coins"), .trendingCrypto)
        XCTAssertEqual(QuickIntentParser.parse("what crypto is trending"), .trendingCrypto)
        // A single-coin price question is unaffected.
        XCTAssertEqual(QuickIntentParser.parse("what's the eth price"), .price(coinID: "ethereum", symbol: "ETH"))
    }

    func testQuickIntentParsesCryptoMarket() {
        XCTAssertEqual(QuickIntentParser.parse("how's the crypto market"), .cryptoMarket)
        XCTAssertEqual(QuickIntentParser.parse("total crypto market cap"), .cryptoMarket)
        XCTAssertEqual(QuickIntentParser.parse("bitcoin dominance"), .cryptoMarket)
        // A single-coin price question is unaffected.
        XCTAssertEqual(QuickIntentParser.parse("what's the btc price"), .price(coinID: "bitcoin", symbol: "BTC"))
    }

    func testQuickIntentParsesMath() {
        guard case let .math(_, result) = QuickIntentParser.parse("what's 12*7+3") else {
            return XCTFail("Expected a math intent.")
        }
        XCTAssertEqual(result, "87")
        if case let .math(_, r)? = QuickIntentParser.parse("18% of 85.50") {
            XCTAssertEqual(r, "15.39")
        } else {
            XCTFail("Expected a math intent for a percentage.")
        }
        // A bare percentage isn't a calculation — needs an operator or "of".
        if case .math? = QuickIntentParser.parse("i'm 50% sure") { XCTFail("bare % must not be math") }
        if case .math? = QuickIntentParser.parse("50%") { XCTFail("bare % must not be math") }
        // …but "% of" and "% with an operator" still compute.
        if case let .math(_, r)? = QuickIntentParser.parse("200 + 5%") { XCTAssertEqual(r, "200.05") } else {
            XCTFail("Expected math for a % with an operator.")
        }
        // Prose isn't math; currency/unit phrases (digits but no operator) keep
        // their own intents and are not hijacked by the calculator.
        XCTAssertNil(QuickIntentParser.parse("what is bitcoin"))
        XCTAssertEqual(QuickIntentParser.parse("5 miles in km"), .unitConvert(value: 5, from: "miles", to: "km"))
        if case .math? = QuickIntentParser.parse("100 usd to eur") {
            XCTFail("Currency phrase must not parse as math.")
        }
        if case .math? = QuickIntentParser.parse("5 miles in km") {
            XCTFail("Unit phrase must not parse as math.")
        }
    }

    func testQuickIntentParsesTipSplit() {
        guard case let .tipSplit(combined)? = QuickIntentParser.parse("20% tip on $85 split 3 ways") else {
            return XCTFail("Expected a tipSplit intent.")
        }
        XCTAssertTrue(combined.contains("$17.00"))      // 20% tip
        XCTAssertTrue(combined.contains("$102.00"))     // total
        XCTAssertTrue(combined.contains("$34.00 each")) // per person

        guard case let .tipSplit(splitOnly)? = QuickIntentParser.parse("split $120 between 4") else {
            return XCTFail("Expected a tipSplit intent.")
        }
        XCTAssertTrue(splitOnly.contains("$30.00 each"))

        guard case let .tipSplit(tipOnly)? = QuickIntentParser.parse("18% tip on $85") else {
            return XCTFail("Expected a tipSplit intent.")
        }
        XCTAssertTrue(tipOnly.contains("$15.30"))
        XCTAssertTrue(tipOnly.contains("$100.30"))

        // A pure percentage calc stays math; prose stays prose.
        if case .tipSplit? = QuickIntentParser.parse("20% of 85") { XCTFail("calc must be math, not tipSplit") }
        XCTAssertNil(QuickIntentParser.parse("how was your day"))
    }

    func testQuickIntentParsesBriefMe() {
        XCTAssertEqual(QuickIntentParser.parse("brief me"), .briefMe)
        XCTAssertEqual(QuickIntentParser.parse("catch me up"), .briefMe)
        // With a recurrence word it schedules a recurring brief instead.
        guard case let .createTracker(spec) = QuickIntentParser.parse("brief me every morning") else {
            return XCTFail("Expected a scheduled daily brief.")
        }
        XCTAssertEqual(spec.kind, .dailyBrief)
        XCTAssertEqual(spec.schedule, .daily(hour: 8, minute: 0))
    }

    func testSpreadsheetExtractorPreservesSheetAndSupplementRows() throws {
        let workbookData = Self.makeStoredZip(entries: [
            (
                "xl/workbook.xml",
                """
                <workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
                  <sheets>
                    <sheet name="Supplementation" sheetId="1" r:id="rId1"/>
                  </sheets>
                </workbook>
                """
            ),
            (
                "xl/_rels/workbook.xml.rels",
                """
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                  <Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/>
                </Relationships>
                """
            ),
            (
                "xl/worksheets/sheet1.xml",
                """
                <worksheet>
                  <sheetData>
                    <row r="2">
                      <c r="A2" t="inlineStr"><is><t>Upon Waking</t></is></c>
                      <c r="B2" t="inlineStr"><is><t>With Breakfast</t></is></c>
                      <c r="C2" t="inlineStr"><is><t>Before Bed</t></is></c>
                    </row>
                    <row r="3">
                      <c r="A3" t="inlineStr"><is><t>Whey</t></is></c>
                      <c r="B3" t="inlineStr"><is><t>Fish Oil</t></is></c>
                      <c r="C3" t="inlineStr"><is><t>Magnesium</t></is></c>
                    </row>
                  </sheetData>
                </worksheet>
                """
            )
        ])

        let extraction = try XCTUnwrap(DocumentTextExtractor.extractedSpreadsheetTableText(
            data: workbookData,
            filename: "supplements.xlsx"
        ))

        XCTAssertTrue(extraction.text.contains("Extracted workbook rows from supplements.xlsx"))
        XCTAssertTrue(extraction.text.contains("Sheet \"Supplementation\""))
        XCTAssertTrue(extraction.text.contains("Row 2: Upon Waking | With Breakfast | Before Bed"))
        XCTAssertTrue(extraction.text.contains("Row 3: Whey | Fish Oil | Magnesium"))
        XCTAssertFalse(extraction.truncated)
    }

    func testSpreadsheetExtractorReadsSupplementWorkbookWhenPresent() throws {
        let envKey = "NEAR_SUPPLEMENT_WORKBOOK_FIXTURE"
        guard let fixturePath = ProcessInfo.processInfo.environment[envKey],
              !fixturePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XCTSkip("Set \(envKey) to a local supplement workbook path to run this optional integration fixture.")
        }
        let url = URL(fileURLWithPath: fixturePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Supplement workbook fixture does not exist at \(url.path).")
        }

        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        let extraction = try XCTUnwrap(DocumentTextExtractor.extractedSpreadsheetTableText(from: url, fileSize: fileSize))

        let preview = String(extraction.text.prefix(2_500))
        XCTAssertTrue(extraction.text.contains("Sheet \"Supplementation\""), preview)
        XCTAssertTrue(extraction.text.contains("Upon"), preview)
        XCTAssertTrue(extraction.text.contains("Whey"), preview)
        XCTAssertTrue(extraction.text.contains("Fish Oil"), preview)
    }

    func testQuickIntentParsesActivityLog() {
        XCTAssertEqual(QuickIntentParser.parse("what have you done"), .activityLog)
        XCTAssertEqual(QuickIntentParser.parse("show your activity"), .activityLog)
    }

    func testQuickIntentParsesForget() {
        XCTAssertEqual(QuickIntentParser.parse("forget that I prefer concise answers"), .forget(text: "I prefer concise answers"))
        XCTAssertEqual(QuickIntentParser.parse("forget everything"), .forget(text: nil))
        XCTAssertEqual(QuickIntentParser.parse("clear your memory"), .forget(text: nil))
    }

    func testQuickIntentParsesDefinition() {
        XCTAssertEqual(QuickIntentParser.parse("define serendipity"), .define(word: "serendipity"))
        XCTAssertEqual(QuickIntentParser.parse("what does ephemeral mean"), .define(word: "ephemeral"))
        XCTAssertEqual(QuickIntentParser.parse("meaning of zeitgeist"), .define(word: "zeitgeist"))
        // Not a definition request.
        XCTAssertNil(QuickIntentParser.parse("define"))
        XCTAssertNil(QuickIntentParser.parse("tell me a story"))
    }

    func testQuickIntentParsesCompoundQueries() {
        let intents = try? XCTUnwrap(QuickIntentParser.parseCompound("what's the eth price and the weather in tokyo"))
        XCTAssertEqual(intents?.count, 2)
        XCTAssertEqual(intents?.first, .price(coinID: "ethereum", symbol: "ETH"))
        XCTAssertEqual(intents?.last, .weather(query: "tokyo"))
        // Three lookups chain too.
        XCTAssertEqual(QuickIntentParser.parseCompound("eth price, bitcoin price and near price")?.count, 3)
        // Prose with "and" that isn't two data lookups doesn't compound.
        XCTAssertNil(QuickIntentParser.parseCompound("explain the pros and cons of sharding"))
        // A memory write with "and" is not swept into a compound run.
        XCTAssertNil(QuickIntentParser.parseCompound("remember that I like tea and coffee"))
    }

    func testChatLocalIntentDispatcherHandlesPendingNearAccountTracker() {
        let schedule = BriefingSchedule.weekdays(hour: 7, minute: 0)

        XCTAssertEqual(
            ChatLocalIntentDispatcher.dispatch(
                text: "root.near",
                pendingNearAccountTrackerSchedule: schedule
            ),
            ChatLocalIntentDispatch(
                clearsPendingNearAccountTracker: true,
                action: .completePendingNearAccountTracker(account: "root.near", schedule: schedule)
            )
        )
        XCTAssertEqual(
            ChatLocalIntentDispatcher.dispatch(
                text: "write me a haiku about the sea",
                pendingNearAccountTrackerSchedule: schedule
            ),
            ChatLocalIntentDispatch(clearsPendingNearAccountTracker: true, action: nil)
        )
        XCTAssertEqual(
            ChatLocalIntentDispatcher.dispatch(
                text: "what is the eth price",
                pendingNearAccountTrackerSchedule: schedule
            ),
            ChatLocalIntentDispatch(
                clearsPendingNearAccountTracker: true,
                action: .single(.price(coinID: "ethereum", symbol: "ETH"))
            )
        )
    }

    func testChatLocalIntentDispatcherKeepsCompoundLookupAsOneLocalAction() {
        XCTAssertEqual(
            ChatLocalIntentDispatcher.dispatch(
                text: "what's the eth price and the weather in tokyo",
                pendingNearAccountTrackerSchedule: nil
            ),
            ChatLocalIntentDispatch(
                clearsPendingNearAccountTracker: false,
                action: .compound([
                    .price(coinID: "ethereum", symbol: "ETH"),
                    .weather(query: "tokyo")
                ])
            )
        )
        XCTAssertNil(
            ChatLocalIntentDispatcher.dispatch(
                text: "explain the pros and cons of sharding",
                pendingNearAccountTrackerSchedule: nil
            )
        )
    }

    func testChatLocalIntentWidgetServiceUsesInjectedBriefDigest() async {
        let expected = MessageWidget(kind: .generic, title: "Daily brief", time: "now", note: "Two trackers ready.")
        let widget = await ChatLocalIntentWidgetService.widget(for: .briefMe) {
            expected
        }
        XCTAssertEqual(widget, expected)
    }

    func testChatLocalIntentWidgetServiceLeavesActionIntentsSynchronous() async {
        let widget = await ChatLocalIntentWidgetService.widget(for: .remember(text: "I prefer concise answers")) {
            XCTFail("Action intents should not request a live widget.")
            return MessageWidget(kind: .generic, title: "Unexpected")
        }
        XCTAssertNil(widget)
    }

    func testChatLocalIntentTranscriptWriterCreatesLocalTurns() {
        let createdAt = Date(timeIntervalSince1970: 42)
        let user = ChatLocalIntentTranscriptWriter.userMessage(
            id: "user-id",
            text: "what is the eth price",
            model: "nearai/test",
            createdAt: createdAt
        )
        XCTAssertEqual(user.id, "user-id")
        XCTAssertEqual(user.role, .user)
        XCTAssertEqual(user.status, "completed")
        XCTAssertFalse(user.isStreaming)

        var messages: [ChatMessage] = []
        let widget = MessageWidget(kind: .generic, title: "ETH", note: "$3,000")
        let assistantID = ChatLocalIntentTranscriptWriter.appendAssistant(
            text: "",
            model: "nearai/test",
            messages: &messages,
            widget: widget,
            streaming: true,
            trustMetadata: { _ in nil }
        )
        XCTAssertEqual(messages.first?.id, assistantID)
        XCTAssertEqual(messages.first?.role, .assistant)
        XCTAssertEqual(messages.first?.status, "searching")
        XCTAssertTrue(messages.first?.isStreaming == true)
        XCTAssertEqual(messages.first?.widget, widget)
    }

    func testQuickIntentParsesUnitConversion() {
        XCTAssertEqual(QuickIntentParser.parse("5 miles in km"), .unitConvert(value: 5, from: "miles", to: "km"))
        XCTAssertEqual(QuickIntentParser.parse("convert 100 f to c"), .unitConvert(value: 100, from: "f", to: "c"))
        XCTAssertEqual(QuickIntentParser.parse("10 kg to lb"), .unitConvert(value: 10, from: "kg", to: "lb"))
        // Mismatched categories / non-units don't convert.
        XCTAssertNil(QuickIntentParser.parse("5 km to kg"))
        XCTAssertNil(QuickIntentParser.parse("5 apples to oranges"))
    }

    func testQuickIntentFallsThroughForChainedActionsAndConditionalCreation() {
        XCTAssertNil(QuickIntentParser.parse("Weather in Tokyo and remind me to pack an umbrella tomorrow at 7am"))
        guard case let .createTracker(monthly) = QuickIntentParser.parse("Set up a monthly briefing on Anthropic policy updates with source links and calendar-worthy follow-ups") else {
            return XCTFail("Expected monthly briefing to become a scheduled tracker.")
        }
        XCTAssertEqual(monthly.schedule, .monthly(day: 1, hour: 8, minute: 0))
        XCTAssertNil(QuickIntentParser.parse("Deep search Claude Code and Xcode release notes; make a tracker only if there is a breaking workflow change; otherwise list dated sources."))
    }

    func testHostileUnknownPricePromptsUseWebNotCannedWidgets() throws {
        let cantonSpot = "what's the Canton Network token price"
        XCTAssertNil(QuickIntentParser.parse(cantonSpot), "Unknown assets must not become ETH/BTC/stock canned widgets.")
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb(cantonSpot), "Unknown live price asks need web grounding.")

        let rolexSpot = "what is the price of a Rolex GMT Master II"
        XCTAssertNil(QuickIntentParser.parse(rolexSpot), "Collectibles should not be forced into crypto/stock widgets.")
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb(rolexSpot), "Collectible pricing needs fresh sources.")

        guard case let .createTracker(canton) = QuickIntentParser.parse("track Canton Network token price every morning at 8am") else {
            return XCTFail("Expected unknown live-price subject to become a custom recurring tracker.")
        }
        XCTAssertEqual(canton.kind, .customPrompt)
        XCTAssertTrue(try XCTUnwrap(canton.prompt).lowercased().contains("canton network token price"))
        XCTAssertNil(canton.subject)

        guard case let .createTracker(mixedOneKnown) = QuickIntentParser.parse("track Canton Network token and BTC price every morning") else {
            return XCTFail("Expected mixed known/unknown assets to stay as a custom web-grounded tracker.")
        }
        XCTAssertEqual(mixedOneKnown.kind, .customPrompt)
        XCTAssertTrue(try XCTUnwrap(mixedOneKnown.prompt).lowercased().contains("canton network token and btc price"))

        guard case let .createTracker(mixedWatchlist) = QuickIntentParser.parse("track Canton Network token, BTC, and TSLA prices every morning") else {
            return XCTFail("Expected mixed watchlist with an unknown asset to stay custom, not drop Canton.")
        }
        XCTAssertEqual(mixedWatchlist.kind, .customPrompt)
        XCTAssertTrue(try XCTUnwrap(mixedWatchlist.prompt).lowercased().contains("canton network token"))

        guard case let .createTracker(knownWatchlist) = QuickIntentParser.parse("track BTC and TSLA prices every morning") else {
            return XCTFail("Expected known multi-asset list to remain a structured watchlist.")
        }
        XCTAssertEqual(knownWatchlist.kind, .watchlist)
        XCTAssertEqual(knownWatchlist.subject, "crypto:bitcoin|stock:TSLA")

        XCTAssertNil(
            QuickIntentParser.parse("track Canton Network token price every morning, no web"),
            "A no-web live-price tracker must not create a future web-grounded automation."
        )
        XCTAssertNil(
            QuickIntentParser.parse("what's the Canton Network token and BTC price?"),
            "Mixed known/unknown spot prices must not drop the unknown asset into a canned coin card."
        )
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb("what's the Canton Network token and BTC price?"))
        XCTAssertNil(
            QuickIntentParser.parse("watchlist Canton Network token BTC TSLA"),
            "Explicit watchlists must not silently discard unknown assets."
        )
        XCTAssertNil(
            QuickIntentParser.parse("what's the Tesla Model Y price?"),
            "Known-company product prices must not become stock widgets."
        )
        XCTAssertNil(QuickIntentParser.parse("Apple iPhone price"))
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb("what's the Tesla Model Y price?"))
    }

    func testQuickIntentBareNewsReturnsFeedTopicNewsFallsThrough() {
        // Bare news → instant multi-source feed.
        XCTAssertEqual(QuickIntentParser.parse("news"), .news)
        XCTAssertEqual(QuickIntentParser.parse("what's happening"), .news)
        XCTAssertEqual(QuickIntentParser.parse("pull the daily news"), .news)
        // Topic news → no quick widget; the web-grounded model answers instead
        // of dumping generic headlines that ignore the topic.
        XCTAssertNil(QuickIntentParser.parse("what's happening in global politics"))
        XCTAssertNil(QuickIntentParser.parse("tech news"))
        XCTAssertNil(QuickIntentParser.parse("what's the latest news on Ukraine"))
    }

    func testWeatherRejectsFigurativeNonPlaces() {
        // INPUT-DISCARD/false-positive: " in <abstract noun>" must not geocode.
        XCTAssertNil(QuickIntentParser.parse("what's the weather like in a relationship"))
        XCTAssertNil(QuickIntentParser.parse("is the weather nice in general"))
        XCTAssertNil(QuickIntentParser.parse("how's the weather in control"))
        // Real places — including the "like in <place>" form — still resolve.
        XCTAssertEqual(QuickIntentParser.parse("what's the weather like in Tokyo"), .weather(query: "tokyo"))
        XCTAssertEqual(QuickIntentParser.parse("weather in new york"), .weather(query: "new york"))
    }

    func testPriceDoesNotHijackExplanatoryOrOpinionPrompts() {
        XCTAssertNil(QuickIntentParser.parse("explain how ethereum works"))
        XCTAssertNil(QuickIntentParser.parse("is solana a good investment"))
        XCTAssertNil(QuickIntentParser.parse("why does bitcoin matter"))
    }

    func testStockIntentResolvesTickersAndCompanies() {
        XCTAssertEqual(QuickIntentParser.parse("AAPL stock price"), .stock(symbol: "AAPL", company: "Apple"))
        XCTAssertEqual(QuickIntentParser.parse("$TSLA"), .stock(symbol: "TSLA", company: "Tesla"))
        XCTAssertEqual(QuickIntentParser.parse("Tesla stock"), .stock(symbol: "TSLA", company: "Tesla"))
        XCTAssertEqual(QuickIntentParser.parse("Nvidia price"), .stock(symbol: "NVDA", company: "Nvidia"))
        XCTAssertEqual(QuickIntentParser.parse("how's Microsoft stock doing"), .stock(symbol: "MSFT", company: "Microsoft"))
    }

    func testStockIntentDoesNotHijackProse() {
        // Common-word company names need an explicit stock cue.
        XCTAssertNil(QuickIntentParser.parse("apple pie recipe"))
        XCTAssertNil(QuickIntentParser.parse("how much is an apple"))
        XCTAssertNil(QuickIntentParser.parse("that's a meta question"))
        // A company name with no stock/price cue stays a model question.
        XCTAssertNil(QuickIntentParser.parse("I love Netflix"))
        // Non-ticker all-caps tokens don't resolve.
        XCTAssertNil(QuickIntentParser.parse("the USA economy is strong"))
    }

    func testQuickIntentIgnoresChitChat() {
        XCTAssertNil(QuickIntentParser.parse("hello how are you"))
        XCTAssertNil(QuickIntentParser.parse("write me a poem about the ocean"))
        XCTAssertNil(QuickIntentParser.parse("tell me a joke"))
        XCTAssertNil(QuickIntentParser.parse("   "))
    }

    func testChatLocalIntentResponseFormatterOwnsTrackerCopy() {
        let plain = TrackerSpec(
            title: "Rolex GMT Master II",
            kind: .customPrompt,
            subject: nil,
            schedule: .daily(hour: 8, minute: 0),
            council: false,
            confirmation: "Rolex GMT Master II · Daily · 8:00 AM",
            prompt: nil,
            condition: nil
        )
        XCTAssertTrue(ChatLocalIntentResponseFormatter.trackerCreated(spec: plain).contains("Created a tracker"))
        XCTAssertTrue(ChatLocalIntentResponseFormatter.trackerCreated(spec: plain).contains("Run now, change it, or delete it"))

        let gated = TrackerSpec(
            title: "ETH alert",
            kind: .cryptoPrice,
            subject: "ethereum",
            schedule: .everyNHours(3),
            council: false,
            confirmation: "ETH below $2,000 · Every 3h",
            prompt: nil,
            condition: BriefingCondition(coinID: "ethereum", symbol: "ETH", comparator: .below, threshold: 2_000)
        )
        XCTAssertTrue(ChatLocalIntentResponseFormatter.trackerCreated(spec: gated).contains("Set up an alert"))
        XCTAssertTrue(ChatLocalIntentResponseFormatter.trackerCreated(spec: gated).contains("re-arm, change, or delete it"))
    }

    func testChatLocalIntentResponseFormatterLabelsInferredMemory() {
        let explicit = MemoryItem(text: "I prefer concise answers", source: .explicit)
        let inferred = MemoryItem(text: "I live in Lisbon", source: .inferred)

        let empty = ChatLocalIntentResponseFormatter.memoryRecall([])
        XCTAssertTrue(empty.contains("I’m not remembering anything yet"))

        let populated = ChatLocalIntentResponseFormatter.memoryRecall([explicit, inferred])
        XCTAssertTrue(populated.contains("• I prefer concise answers"))
        XCTAssertTrue(populated.contains("• I live in Lisbon  _(noted automatically)_"))
        XCTAssertTrue(populated.contains("Items marked _noted automatically_"))
    }

    func testChatLocalIntentResponseFormatterFormatsSearchHits() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let hit = ConversationSearchHit(
            id: "m1",
            conversationID: "c1",
            conversationTitle: "Client SLA review",
            isUser: true,
            snippet: "Vendor changed termination notice language.",
            score: 2,
            date: now.addingTimeInterval(-3600)
        )

        let empty = ChatLocalIntentResponseFormatter.searchHistory(query: "SLA", hits: [], now: now)
        XCTAssertTrue(empty.contains("I couldn’t find anything about “SLA”"))

        let populated = ChatLocalIntentResponseFormatter.searchHistory(query: "SLA", hits: [hit], now: now)
        XCTAssertTrue(populated.contains("Found 1 match for “SLA”"))
        XCTAssertTrue(populated.contains("**Client SLA review** — You: Vendor changed termination notice language."))
    }

    func testChatLocalIntentResponseFormatterFormatsReminderCopy() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reminder = PersonalReminder(title: "call mom", date: now.addingTimeInterval(3600))
        let text = ChatLocalIntentResponseFormatter.reminderCreated(reminder, now: now)

        XCTAssertTrue(text.contains("Reminder set"))
        XCTAssertTrue(text.contains("**call mom**"))
        XCTAssertTrue(text.contains("notification even if the app is closed"))
    }

    @MainActor
    func testChatLocalIntentExecutorOwnsMemorySideEffects() {
        let memoryStore = MemoryStore(fileURL: temporaryJSONFileURL())
        let activityLog = AgentActivityLog(fileURL: temporaryJSONFileURL())
        var passiveMemoryEnabled = true
        var keepDocumentsOnDevice = false
        let environment = ChatLocalIntentExecutor.Environment(
            memoryStore: memoryStore,
            activityLog: activityLog,
            trackers: { [] },
            createTracker: { _ in XCTFail("Memory intent should not create trackers.") },
            setPassiveMemoryEnabled: { passiveMemoryEnabled = $0 },
            setKeepDocumentsOnDevice: { keepDocumentsOnDevice = $0 },
            searchHistory: { _ in [] },
            scheduleReminder: { _ in XCTFail("Memory intent should not schedule reminders.") }
        )

        let remembered = ChatLocalIntentExecutor.execute(
            intent: .remember(text: "I prefer concise answers"),
            prompt: "remember that I prefer concise answers",
            priorUserText: nil,
            environment: environment
        )
        XCTAssertTrue(remembered?.assistantText.contains("I’ll remember") == true)
        XCTAssertTrue(remembered?.shouldHaptic == true)
        XCTAssertEqual(memoryStore.items.map(\.text), ["I prefer concise answers"])

        let disabled = ChatLocalIntentExecutor.execute(
            intent: .setMemoryCapture(enabled: false),
            prompt: "stop learning about me",
            priorUserText: nil,
            environment: environment
        )
        XCTAssertFalse(passiveMemoryEnabled)
        XCTAssertTrue(disabled?.assistantText.contains("Passive memory is off") == true)

        let privacy = ChatLocalIntentExecutor.execute(
            intent: .setDocumentPrivacy(onDevice: true),
            prompt: "keep documents on device",
            priorUserText: nil,
            environment: environment
        )
        XCTAssertTrue(keepDocumentsOnDevice)
        XCTAssertTrue(privacy?.assistantText.contains("Private document mode is on") == true)
    }

    @MainActor
    func testChatLocalIntentExecutorOwnsTrackerSideEffects() throws {
        let memoryStore = MemoryStore(fileURL: temporaryJSONFileURL())
        let activityLog = AgentActivityLog(fileURL: temporaryJSONFileURL())
        var createdTrackers: [Briefing] = []
        let environment = ChatLocalIntentExecutor.Environment(
            memoryStore: memoryStore,
            activityLog: activityLog,
            trackers: { createdTrackers },
            createTracker: { createdTrackers.append($0) },
            setPassiveMemoryEnabled: { _ in },
            setKeepDocumentsOnDevice: { _ in },
            searchHistory: { _ in [] },
            scheduleReminder: { _ in XCTFail("Tracker intent should not schedule reminders.") }
        )
        let spec = TrackerSpec(
            title: "Rolex GMT Master II",
            kind: .customPrompt,
            subject: nil,
            schedule: .daily(hour: 8, minute: 0),
            council: false,
            confirmation: "Rolex GMT Master II · Daily · 8:00 AM",
            prompt: "Track Rolex GMT Master II pricing.",
            condition: nil
        )

        let result = ChatLocalIntentExecutor.execute(
            intent: .createTracker(spec),
            prompt: "track Rolex prices daily",
            priorUserText: nil,
            environment: environment
        )
        XCTAssertEqual(createdTrackers.first?.title, "Rolex GMT Master II")
        XCTAssertTrue(activityLog.entries.first?.summary.contains("Created tracker") == true)
        XCTAssertTrue(result?.assistantText.contains("Created a tracker") == true)
        XCTAssertTrue(result?.shouldHaptic == true)

        let schedule = BriefingSchedule.weekdays(hour: 7, minute: 30)
        let pending = ChatLocalIntentExecutor.completePendingNearAccountTracker(
            account: "codex.near",
            schedule: schedule,
            environment: environment
        )
        XCTAssertEqual(createdTrackers.last?.kind, .nearAccount)
        XCTAssertEqual(createdTrackers.last?.accountID, "codex.near")
        XCTAssertTrue(pending.assistantText.contains("NEAR account · codex.near"))
    }

    func testChatLocalIntentBriefingFactoryBuildsTrackerBriefings() {
        let spec = TrackerSpec(
            title: "Rolex GMT Master II",
            kind: .customPrompt,
            subject: nil,
            schedule: .daily(hour: 8, minute: 0),
            council: true,
            confirmation: "Rolex GMT Master II · Daily · 8:00 AM",
            prompt: "Track Rolex GMT Master II pricing from current sources.",
            condition: nil
        )

        let briefing = ChatLocalIntentBriefingFactory.trackerBriefing(for: spec, fallbackPrompt: "fallback")
        XCTAssertEqual(briefing.title, "Rolex GMT Master II")
        XCTAssertEqual(briefing.prompt, "Track Rolex GMT Master II pricing from current sources.")
        XCTAssertEqual(briefing.schedule, .daily(hour: 8, minute: 0))
        XCTAssertTrue(briefing.council)
        XCTAssertEqual(briefing.kind, .customPrompt)
        XCTAssertEqual(ChatLocalIntentBriefingFactory.trackerActivitySummary(for: spec), "Created tracker “Rolex GMT Master II” · Rolex GMT Master II · Daily · 8:00 AM")
    }

    func testChatLocalIntentBriefingFactoryBuildsTrackLastDraft() throws {
        let draft = try XCTUnwrap(ChatLocalIntentBriefingFactory.trackLastDraft(
            priorUserText: "what is the price of a Rolex GMT Master II?",
            schedule: .daily(hour: 8, minute: 0)
        ))

        XCTAssertTrue(draft.title.localizedCaseInsensitiveContains("Rolex"))
        XCTAssertEqual(draft.briefing.title, draft.title)
        XCTAssertEqual(draft.briefing.schedule, .daily(hour: 8, minute: 0))
        XCTAssertEqual(draft.briefing.kind, .customPrompt)
        XCTAssertTrue(draft.briefing.prompt.contains("Using web search"))
        XCTAssertTrue(ChatLocalIntentBriefingFactory.trackLastActivitySummary(title: draft.title).contains("track that"))
        XCTAssertNil(ChatLocalIntentBriefingFactory.trackLastDraft(priorUserText: "", schedule: .daily(hour: 8, minute: 0)))
    }

    func testChatLocalIntentBriefingFactoryBuildsNearAccountTracker() {
        let schedule = BriefingSchedule.weekdays(hour: 7, minute: 30)
        let briefing = ChatLocalIntentBriefingFactory.nearAccountBriefing(
            account: "codex.near",
            schedule: schedule
        )

        XCTAssertEqual(briefing.title, "NEAR account")
        XCTAssertEqual(briefing.prompt, "Track NEAR account codex.near.")
        XCTAssertEqual(briefing.kind, .nearAccount)
        XCTAssertEqual(briefing.accountID, "codex.near")
        XCTAssertEqual(briefing.schedule, schedule)
        XCTAssertEqual(
            ChatLocalIntentBriefingFactory.nearAccountActivitySummary(account: "codex.near", schedule: schedule),
            "Created tracker “NEAR account” · NEAR account · codex.near · \(schedule.scheduleLabel)"
        )
    }
}

private func temporaryJSONFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("near-private-chat-test-\(UUID().uuidString).json")
}
