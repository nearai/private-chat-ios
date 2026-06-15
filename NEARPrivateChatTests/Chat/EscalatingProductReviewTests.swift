import XCTest
@testable import NEARPrivateChat

/// Escalating-difficulty product review, made executable.
///
/// Derived from the 2026-06-15 review of the quick-intent tracker parser across
/// crypto / equities / commodities-metals / watches-luxury / products / long-tail
/// scenarios. Locks the behaviors that currently work AND the two parity fixes
/// shipped on this branch:
///   1. an unknown `$cashtag` no longer misclassifies as a Yahoo equity, and
///   2. a recurring price ALERT with no resolvable coin/stock now becomes a
///      web-grounded recurring tracker instead of a one-off model chat — which
///      closes commodities, luxury watches, retail products, and long-tail coins
///      for conditional alerts in one move.
extension PrivateChatCoreTests {

    // MARK: - Current parity locks (must keep working)

    func testReview_cryptoPriceAndAlertAndWatchlistStillWork() {
        XCTAssertEqual(
            QuickIntentParser.parse("what's the price of BTC"),
            .price(coinID: "bitcoin", symbol: "BTC")
        )
        guard case let .createTracker(sol) = QuickIntentParser.parse("alert me when SOL drops below $140") else {
            return XCTFail("Expected a SOL conditional tracker.")
        }
        XCTAssertEqual(sol.kind, .cryptoPrice)
        XCTAssertEqual(sol.subject, "solana")
        XCTAssertEqual(sol.condition?.comparator, .below)
        XCTAssertEqual(sol.condition?.threshold, 140)

        guard case let .createTracker(watch) = QuickIntentParser.parse("track ETH and SOL prices every morning") else {
            return XCTFail("Expected a 2-asset watchlist tracker.")
        }
        XCTAssertEqual(watch.kind, .watchlist)
        XCTAssertEqual(watch.subject, "crypto:ethereum|crypto:solana")
    }

    func testReview_knownEquityCashtagsAndConditionsStillWork() {
        XCTAssertEqual(QuickIntentParser.parse("$AAPL"), .stock(symbol: "AAPL", company: "Apple"))
        guard case let .createTracker(tsla) = QuickIntentParser.parse("notify me when TSLA drops below 200") else {
            return XCTFail("Expected a TSLA conditional tracker.")
        }
        XCTAssertEqual(tsla.kind, .stockPrice)
        XCTAssertEqual(tsla.condition?.symbol, "TSLA")
        XCTAssertEqual(tsla.condition?.comparator, .below)
        XCTAssertEqual(tsla.condition?.threshold, 200)
    }

    // MARK: - Fix #1: unknown $cashtags must not become a Yahoo equity

    func testReview_unknownCashtagDoesNotMisclassifyAsStock() {
        // $TIA (Celestia), $JUP, $WIF, $BONK are crypto cashtags, not equities.
        for cashtag in ["$TIA", "$JUP", "$WIF", "$BONK"] {
            if case .stock = QuickIntentParser.parse("track \(cashtag) price") {
                XCTFail("\(cashtag) must not resolve as a stock.")
            }
            if case .stock = QuickIntentParser.parse(cashtag) {
                XCTFail("Bare \(cashtag) must not resolve as a stock.")
            }
        }
        // Crypto cashtags already in the coin table keep routing to the crypto card.
        XCTAssertEqual(QuickIntentParser.parse("$ETH price"), .price(coinID: "ethereum", symbol: "ETH"))
    }

    // MARK: - Fix #2: web-grounded conditional fallback (commodities / watches / products / long-tail)

    private func assertWebGroundedAlert(
        _ prompt: String,
        mustMentionLowercased keyword: String,
        comparator: BriefingComparator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .createTracker(spec) = QuickIntentParser.parse(prompt) else {
            return XCTFail("Expected a recurring tracker for: \(prompt)", file: file, line: line)
        }
        XCTAssertEqual(spec.kind, .customPrompt, "Unresolved-asset alert should be a web-grounded customPrompt tracker.", file: file, line: line)
        XCTAssertNil(spec.condition, "Web-grounded alert has no structured price condition.", file: file, line: line)
        let body = (spec.prompt ?? "").lowercased()
        XCTAssertTrue(body.contains(keyword), "Tracker prompt must preserve '\(keyword)'. Got: \(body)", file: file, line: line)
        XCTAssertTrue(
            body.contains(comparator == .below ? "below" : "above"),
            "Tracker prompt must preserve the alert direction.", file: file, line: line
        )
    }

    func testReview_commodityConditionalAlertBecomesTracker() {
        assertWebGroundedAlert("alert me when gold goes above $2,500", mustMentionLowercased: "gold", comparator: .above)
        assertWebGroundedAlert("notify me when silver drops below $25", mustMentionLowercased: "silver", comparator: .below)
        assertWebGroundedAlert("let me know when oil climbs above $90", mustMentionLowercased: "oil", comparator: .above)
    }

    func testReview_luxuryWatchConditionalAlertBecomesTracker() {
        assertWebGroundedAlert("notify me when a Rolex Daytona drops below $30,000", mustMentionLowercased: "rolex daytona", comparator: .below)
    }

    func testReview_retailProductConditionalAlertBecomesTracker() {
        assertWebGroundedAlert("alert me when the iPhone 16 Pro drops below $900", mustMentionLowercased: "iphone 16 pro", comparator: .below)
    }

    func testReview_longTailCoinConditionalAlertBecomesTracker() {
        assertWebGroundedAlert("alert me when PEPE drops below $0.000012", mustMentionLowercased: "pepe", comparator: .below)
    }

    func testReview_webGroundedAlertSchedulesARecurringWatch() {
        guard case let .createTracker(spec) = QuickIntentParser.parse("alert me when gold goes above $2,500") else {
            return XCTFail("Expected a recurring tracker.")
        }
        // No explicit cadence given → defaults to the few-hour watch cycle so it
        // behaves like a real alert rather than a one-shot.
        XCTAssertEqual(spec.schedule, .everyNHours(3))
    }

    func testReview_webGroundedAlertHonorsExplicitCadence() {
        guard case let .createTracker(spec) = QuickIntentParser.parse("alert me when gold goes above $2,500 every morning at 8am") else {
            return XCTFail("Expected a recurring tracker.")
        }
        // An explicit cadence must be kept, not flattened to the default cycle.
        XCTAssertNotEqual(spec.schedule, .everyNHours(3))
    }

    // MARK: - Over-trigger guard: abstract-metric / pronoun alerts must NOT become price trackers

    func testReview_abstractMetricAndPronounAlertsDoNotBecomePriceTrackers() {
        // A comparator + bare number with no priceable asset is not a price
        // alert — these used to (briefly) build a fake "$N price" watcher; they
        // must fall through to the model instead.
        let nonPriceAlerts = [
            "alert me when my coverage drops below 80",
            "warn me when cpu is above 90",
            "ping me when my credit score drops below 700",
            "let me know when occupancy is below 90",
            "notify me when the queue is above 100",
            "alert me when it drops below $100"
        ]
        for prompt in nonPriceAlerts {
            if case .createTracker = QuickIntentParser.parse(prompt) {
                XCTFail("Non-price alert must not become a tracker: \(prompt)")
            }
        }
    }

    // MARK: - Cashtag-in-alert routing (ties the two fixes together)

    func testReview_knownEquityCashtagAlertStaysStructured() {
        guard case let .createTracker(spec) = QuickIntentParser.parse("alert me when $AAPL drops below 150") else {
            return XCTFail("Expected a structured AAPL stock alert.")
        }
        XCTAssertEqual(spec.kind, .stockPrice)
        XCTAssertEqual(spec.condition?.symbol, "AAPL")
        XCTAssertEqual(spec.condition?.comparator, .below)
        XCTAssertEqual(spec.condition?.threshold, 150)
    }

    func testReview_unknownCashtagAlertBecomesWebGrounded() {
        guard case let .createTracker(spec) = QuickIntentParser.parse("alert me when $WIF drops below $2") else {
            return XCTFail("Expected a web-grounded tracker for the unknown cashtag.")
        }
        XCTAssertEqual(spec.kind, .customPrompt)
        XCTAssertNil(spec.condition)
        XCTAssertTrue((spec.prompt ?? "").lowercased().contains("wif"))
    }
}
