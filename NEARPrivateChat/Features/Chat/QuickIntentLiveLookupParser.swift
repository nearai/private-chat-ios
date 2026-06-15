import Foundation

extension QuickIntentParser {
    static let knownStocks: [(symbol: String, names: [String], ambiguous: Bool)] = [
        ("AAPL", ["apple"], true), ("MSFT", ["microsoft"], false),
        ("GOOGL", ["google", "alphabet"], false), ("AMZN", ["amazon"], false),
        ("TSLA", ["tesla"], false), ("NVDA", ["nvidia"], false),
        ("META", ["meta", "facebook"], true), ("NFLX", ["netflix"], false),
        ("AMD", ["amd"], false), ("INTC", ["intel"], false),
        ("DIS", ["disney"], false), ("BA", ["boeing"], false),
        ("JPM", ["jpmorgan", "jp morgan"], false), ("V", ["visa"], true),
        ("WMT", ["walmart"], false), ("KO", ["coca cola", "coca-cola"], false),
        ("PEP", ["pepsi", "pepsico"], false), ("NKE", ["nike"], false),
        ("SBUX", ["starbucks"], false), ("UBER", ["uber"], false),
        ("ABNB", ["airbnb"], false), ("COIN", ["coinbase"], false),
        ("PLTR", ["palantir"], false), ("SHOP", ["shopify"], false),
        ("PYPL", ["paypal"], false), ("ORCL", ["oracle"], false),
        ("CRM", ["salesforce"], false), ("ADBE", ["adobe"], false),
        ("SPY", ["s&p 500", "s&p500", "sp500", "s and p 500"], false),
        ("QQQ", ["nasdaq 100", "nasdaq100"], false)
    ]

    /// Resolves a stock from free text → (ticker, company). Conservative by
    /// design: a `$TICKER`, a KNOWN all-caps ticker with a cue, or a known
    /// company name with a stock/price cue (ambiguous names require a stock cue).
    /// Anything weaker returns nil and falls through (e.g. to the open-ended
    /// web-search tracker), so prose is never hijacked into a wrong stock card.
    static func parseStock(_ text: String, original: String) -> (symbol: String, company: String)? {
        let stockCue = contains(text, ["stock", "stocks", "shares", "share price", "ticker", "nasdaq", "nyse", "equity", "equities"]) || original.contains("$")
        // NB: no "doing" — too broad ("what is Amazon doing about AI" is prose,
        // not a stock card). Use "stock"/"shares" or "price" to ask for a quote.
        let priceCue = contains(text, ["price", "worth", "trading", "quote", "how much", "value"])
        if priceCue, !stockCue, hasProductPriceContext(text) {
            return nil
        }

        // 1) $TICKER — explicit, but only resolve a KNOWN equity ticker. An
        // unknown cashtag is ambiguous and is most often a crypto cashtag
        // ($TIA = Celestia, $JUP, $WIF, $BONK) — and $ETH/$BTC are crypto too.
        // Claiming an unknown $cashtag as a Yahoo equity renders a wrong stock
        // card, so defer (return nil) and let the coin/web path handle it.
        if let r = original.range(of: #"\$([A-Za-z]{1,5})\b"#, options: .regularExpression) {
            let sym = String(original[r].dropFirst()).uppercased()
            guard let stock = knownStocks.first(where: { $0.symbol == sym }) else {
                return nil
            }
            return (sym, stock.names.first?.capitalized ?? "")
        }
        // 2) A known all-caps ticker token (AAPL, TSLA) with any stock/price cue.
        if stockCue || priceCue,
           let r = original.range(of: #"\b[A-Z]{1,5}\b"#, options: .regularExpression),
           let stock = knownStocks.first(where: { $0.symbol == String(original[r]) }) {
            return (stock.symbol, stock.names.first?.capitalized ?? "")
        }
        // 3) A known company name. Ambiguous names need an explicit stock cue;
        // others need at least a stock or price cue.
        for stock in knownStocks {
            for name in stock.names where wordPresent(name, in: text) {
                if stock.ambiguous { if stockCue { return (stock.symbol, name.capitalized) } }
                else if stockCue || priceCue { return (stock.symbol, name.capitalized) }
            }
        }
        return nil
    }

    static func hasProductPriceContext(_ text: String) -> Bool {
        contains(text, [
            "model y", "model 3", "cybertruck", "car", "vehicle", "ev ",
            "iphone", "ipad", "macbook", "airpods", "apple watch",
            "rolex", "gmt-master", "gmt master", "secondary market",
            "resale", "pre-owned", "preowned", "collectible", "collectibles",
            "grey market", "gray market", "bezel",
            "prime", "subscription", "ticket", "tickets", "movie", "movies",
            "phone", "laptop", "shoe", "shoes", "sneaker", "sneakers",
            "console", "device", "service", "plan", "membership"
        ])
    }

    /// Resolves a single token to a known stock (no cue required — used inside a
    /// watchlist where the list context is the cue). nil if not a known asset.
    static func resolveStockToken(_ token: String) -> (symbol: String, label: String)? {
        let lower = token.lowercased()
        for stock in knownStocks {
            if lower == stock.symbol.lowercased() { return (stock.symbol, stock.symbol) }
            for name in stock.names where wordPresent(name, in: lower) { return (stock.symbol, name.capitalized) }
        }
        return nil
    }

    /// Extracts a watchlist (≥2 distinct assets) from free text → a serialized
    /// "crypto:ethereum|stock:AAPL|crypto:near" string. Resolves each token to a
    /// known coin or stock; non-asset tokens (track/every/morning/…) are ignored.
    /// Returns nil for fewer than 2 assets so single-asset trackers stay simple.
    static func parseWatchlistAssets(_ text: String) -> String? {
        let normalized = text.lowercased()
            .replacingOccurrences(of: #"\b(and|plus|with|vs)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&", with: " ")
            .replacingOccurrences(of: ",", with: " ")
        let tokens = normalized.split(whereSeparator: { $0 == " " }).map(String.init)
        var assets: [String] = []
        var seen = Set<String>()
        for token in tokens where token.count >= 2 {
            if let coin = matchedCoin(in: token) {
                let key = "crypto:\(coin.id)"
                if seen.insert(key).inserted { assets.append(key) }
            } else if let stock = resolveStockToken(token) {
                let key = "stock:\(stock.symbol)"
                if seen.insert(key).inserted { assets.append(key) }
            }
        }
        guard assets.count >= 2 else { return nil }
        // Require a finance signal so ordinary prose with two proper nouns
        // ("watch Netflix and Disney tonight") isn't turned into a watchlist. A
        // crypto leg, a $ticker, or an explicit finance word all qualify.
        let lower = text.lowercased()
        let financeCue = assets.contains { $0.hasPrefix("crypto:") }
            || lower.contains("$")
            || contains(lower, ["watchlist", "watch list", "portfolio", "price", "prices", "stock", "stocks", "shares", "ticker", "crypto", "market", "markets"])
        // A media/entertainment "watchlist" ("movie watchlist with Netflix and
        // Disney") names two tickers by coincidence. Exclude it so an evening's
        // viewing plan isn't turned into a finance card.
        let mediaContext = contains(lower, ["movie", "movies", "film", "films", "tv ", "show", "shows", "series",
                                            "book", "books", "reading", "playlist", "anime", "documentary",
                                            "binge", "to watch", "watch tonight"])
        return (financeCue && !mediaContext) ? assets.joined(separator: "|") : nil
    }

    /// Detects a chart/history follow-up with a timeframe and maps it to the
    /// CoinGecko `market_chart` `days` value + a short label. Used by price
    /// tracker threads so "show me the 1 year chart" renders a REAL historical
    /// chart, not prose. Returns nil when it isn't a chart/timeframe request.
    static func parseChartTimeframe(_ raw: String) -> (days: String, label: String)? {
        let text = raw.lowercased()
        let timeframe: (days: String, label: String)?
        if contains(text, ["all time", "all-time", "since inception", "ever", "max history", "entire history"]) {
            timeframe = ("max", "all time")
        } else if contains(text, ["year", "12 month", "12 months", "1y", "annual", "yearly"]) {
            timeframe = ("365", "1Y")
        } else if contains(text, ["6 month", "6 months", "6mo", "half year", "180 day", "180 days"]) {
            timeframe = ("180", "6M")
        } else if contains(text, ["quarter", "3 month", "3 months", "90 day", "90 days"]) {
            timeframe = ("90", "3M")
        } else if contains(text, ["month", "30 day", "30 days", "1mo", "4 week", "4 weeks"]) {
            timeframe = ("30", "1M")
        } else if contains(text, ["week", "7 day", "7 days"]) {
            timeframe = ("7", "1W")
        } else {
            timeframe = nil
        }
        guard let tf = timeframe else { return nil }
        // Require a charting cue so a plain "what happened this year" stays text.
        let wantsChart = contains(text, [
            "chart", "graph", "history", "historical", "trend", "performance",
            "price history", "over the past", "over the last", "show me", "show",
            "pull up", "see the", "view"
        ])
        return wantsChart ? tf : nil
    }

    /// The subject of a question, with common lead-ins stripped, for "track
    /// that": "what's the price of a Rolex GMT Master II?" → "price of a Rolex
    /// GMT Master II".
    static func subjectFromQuery(_ text: String) -> String {
        var subject = text.trimmingCharacters(in: CharacterSet(charactersIn: " ?.!"))
        let lower = subject.lowercased()
        for lead in ["what's the current ", "whats the current ", "what is the current ",
                     "what's the ", "whats the ", "what is the ", "what's ", "whats ", "what is ",
                     "how much is the ", "how much is a ", "how much is an ", "how much is ",
                     "how much does a ", "how much does the ", "current ", "the latest ", "latest ",
                     "tell me the ", "tell me ", "get the ", "show me the ", "show me ", "find the ", "find "]
        where lower.hasPrefix(lead) {
            subject = String(subject.dropFirst(lead.count)); break
        }
        return subject.trimmingCharacters(in: CharacterSet(charactersIn: " ?.!"))
    }

    /// A short display title from a tracker subject — strips a leading
    /// "price/value/cost of" and an article. "price of a Rolex GMT Master II"
    /// → "Rolex GMT Master II".
    static func prettyTrackerTitle(from subject: String) -> String {
        var title = subject
        for prefix in ["current price of ", "price of ", "value of ", "cost of ", "quote for ", "the "] {
            if title.lowercased().hasPrefix(prefix) { title = String(title.dropFirst(prefix.count)) }
        }
        for article in ["a ", "an ", "the "] where title.lowercased().hasPrefix(article) {
            title = String(title.dropFirst(article.count))
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ?.!,"))
        if let range = title.range(of: " covering ", options: [.caseInsensitive]),
           title.distance(from: title.startIndex, to: range.lowerBound) >= 8 {
            title = String(title[..<range.lowerBound])
                .trimmingCharacters(in: CharacterSet(charactersIn: " ?.!,"))
        }
        for trailingCue in [" and tell me", " and notify me", " and alert me", " and let me know"] {
            if let range = title.range(of: trailingCue, options: [.caseInsensitive]),
               title.distance(from: title.startIndex, to: range.lowerBound) >= 8 {
                title = String(title[..<range.lowerBound])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ?.!,"))
                break
            }
        }
        if title.lowercased().hasSuffix(" release date updates") {
            title = String(title.dropLast(" updates".count))
        }
        return BriefingPresentationText.wordBoundaryTitle(title)
    }

    /// True when a news request carries NO topic — just "news" / "headlines" /
    /// "what's happening" surrounded by filler, schedule words, or tracker
    /// scaffolding. A request that names a subject ("global politics", "tech",
    /// "AI") is NOT bare, so the caller routes it to the web-grounded model or a
    /// topic-specific tracker instead of the generic multi-source feed. Biased
    /// toward "topic": a leftover noun makes it non-bare, because surfacing a
    /// generic headline dump for a topic ask is the worse failure.
    static func isBareNewsRequest(_ text: String) -> Bool {
        var t = " " + text.lowercased() + " "
        // Collapse multi-word triggers/lead-ins first so their non-stop words
        // ("happening", "stories", "events") don't survive as fake topics.
        let multiword = [
            "what's happening", "whats happening", "what is happening",
            "what's going on", "whats going on", "what is going on",
            "top stories", "top story", "current events", "current affairs",
            "in the news", "around the world", "the latest", "what's new", "whats new"
        ]
        for phrase in multiword {
            t = t.replacingOccurrences(of: phrase, with: " ")
        }
        let stop: Set<String> = [
            // news words
            "news", "headlines", "headline", "stories", "story", "events", "event",
            "happening", "going", "affairs", "update", "updates", "briefing", "brief",
            // articles / pronouns / imperatives
            // NB: "us" is intentionally NOT a stop word — "US news"/"US headlines"
            // is a topic (the country), which must reach topic-aware grounding,
            // not the generic feed. "give us the news" simply routes to the model.
            "the", "a", "an", "my", "our", "me", "give", "show", "tell",
            "get", "fetch", "bring", "find", "read", "list", "display", "want",
            "see", "like", "to", "please", "with", "of", "new", "pull", "grab",
            "catch", "check", "gimme", "lemme", "pull up", "whats", "whatre",
            // questions / time / scope
            "now", "today", "todays", "this", "morning", "afternoon", "evening",
            "tonight", "right", "currently", "lately", "recently", "latest",
            "current", "whats", "what", "is", "are", "any", "some", "for", "in",
            "on", "out", "there", "day", "these", "days", "around", "world",
            "global", "international",
            // tracker / schedule scaffolding (so full tracker commands classify)
            "create", "set", "setup", "up", "make", "build", "schedule", "start",
            "add", "tracker", "alert", "watcher", "digest", "watch", "track",
            "monitor", "follow", "keep", "eye", "tabs", "daily", "weekly",
            "every", "each", "weekday", "weekdays", "week", "am", "pm", "at",
            "can", "you", "could", "would", "i"
        ]
        let residue = t
            .split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .map { $0.replacingOccurrences(of: "'", with: "") }
            .filter { !$0.isEmpty && !stop.contains($0) }
        return residue.isEmpty
    }

    /// The topic of a news tracker, with tracker/schedule scaffolding and the
    /// news words themselves stripped. "track global politics news every
    /// morning at 8am" → "global politics". Returns "" for a bare news request.
    static func newsTopic(from text: String) -> String {
        var topic = trackerSubject(from: text).lowercased()
        // Drop the news nouns and the connectors that introduce them, leaving
        // just the subject. Word-boundary anchored so "newscaster" survives.
        let dropWords = ["headlines", "headline", "stories", "story", "news",
                         "latest", "top", "daily", "current", "about", "regarding",
                         "on", "for", "in", "the", "happenings", "developments"]
        for word in dropWords {
            topic = topic.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
                with: " ",
                options: .regularExpression
            )
        }
        topic = topic.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return topic.trimmingCharacters(in: CharacterSet(charactersIn: " ?.!,"))
    }

    /// True when the text reads as an imperative "track/watch/monitor <subject>"
    /// command (optionally after a polite lead-in), excluding idioms like "watch
    /// out" / "watch for" so a statement ("watch out, the price went up") can't
    /// trip it. Expects lowercased input.
    static func startsWithWatchCommand(_ text: String) -> Bool {
        watchCommandTail(text) != nil
    }

    /// The text after a leading "track/watch/monitor …" command (and any polite
    /// lead-in), or nil if the text isn't such a command. Excludes "watch out" /
    /// "watch for" idioms.
    static func watchCommandTail(_ text: String) -> String? {
        var rest = text
        for prefix in ["please ", "can you ", "could you ", "would you ", "i want to ", "i'd like to ",
                       "i would like to ", "i want you to ", "i'd like you to ", "let's ", "lets "]
        where rest.hasPrefix(prefix) {
            rest = String(rest.dropFirst(prefix.count)); break
        }
        let verbs = ["track ", "watch ", "monitor ", "follow ", "keep an eye on ", "keep tabs on ", "keep track of "]
        guard let verb = verbs.first(where: { rest.hasPrefix($0) }) else { return nil }
        let tail = String(rest.dropFirst(verb.count))
        if verb == "watch " && tail.hasPrefix("out") { return nil }
        return tail
    }

    /// True for a bare "track that / watch it / keep an eye on this [daily]" —
    /// a follow-up that should track whatever the previous answer was about. The
    /// pronoun must have NO subject of its own ("track that bitcoin" is a normal
    /// tracker, not this).
    /// Recognizes a BARE Daily Brief request ("brief me", "catch me up", "brief
    /// me every morning"), returning whether it's recurring. Strips schedule and
    /// filler, then matches an exact phrase set — so "daily briefing about X" or
    /// "brief me on the market" (which carry a topic) are NOT the digest.
    static func parseBrief(_ text: String) -> Bool? {
        var trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " ?.!"))
        for prefix in ["please ", "can you ", "could you ", "hey ", "ok ", "okay "] where trimmed.hasPrefix(prefix) {
            trimmed = String(trimmed.dropFirst(prefix.count)); break
        }
        let recurringWords = ["every weekday", "every morning", "every day", "each morning", "each day",
                              "every week", "weekly", "nightly", "daily", "every ", "each "]
        let recurring = recurringWords.contains { trimmed.contains($0) }
        var core = trimmed
        for word in recurringWords + ["for me", "right now", "now", "today", "please"] {
            core = core.replacingOccurrences(of: word, with: " ", options: .caseInsensitive)
        }
        core = core.replacingOccurrences(of: #"\b(at\s+)?\d{1,2}(:\d{2})?\s*(am|pm)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        core = core.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ?.!,"))
        let briefs: Set<String> = [
            "brief me", "brief", "morning brief", "my brief", "my morning brief", "give me my brief",
            "what's my brief", "whats my brief", "what is my brief", "catch me up",
            "what should i know", "what should i know today"
        ]
        return briefs.contains(core) ? recurring : nil
    }

    static func parseTrackLast(_ text: String) -> Bool {
        guard let tail = watchCommandTail(text) else { return false }
        var rest = tail.trimmingCharacters(in: .whitespaces)
        let pronouns = ["that one", "this one", "those", "these", "that", "this", "it"]
        guard let pronoun = pronouns.first(where: { rest == $0 || rest.hasPrefix($0 + " ") }) else { return false }
        rest = String(rest.dropFirst(pronoun.count))
        for filler in ["for me", "please", "going forward", "from now on",
                       "every weekday", "every morning", "every day", "each day", "each morning",
                       "every week", "weekdays", "daily", "weekly", "hourly", "nightly"] {
            rest = rest.replacingOccurrences(of: filler, with: " ", options: .caseInsensitive)
        }
        rest = rest.replacingOccurrences(of: #"\b(at\s+)?\d{1,2}(:\d{2})?\s*(am|pm)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
        return rest.isEmpty
    }

    /// "notify me when ETH drops below $2,000" → a coin-price threshold tracker.
    /// Strict gate: must read like an alert (an alert verb or when/if/once) AND
    /// name a known coin AND carry a comparator + number — otherwise nil so
    /// ordinary prompts fall through to the generic tracker path or the model.
    static func makeConditionalTracker(from text: String, original: String) -> TrackerSpec? {
        let alertVerb = contains(text, ["notify", "alert", "tell me", "let me know",
                                        "ping me", "warn me", "message me", "remind me"])
        // A bare mid-sentence "if"/"when" is too loose (it would catch "explain
        // what happens if eth hits 5000"). Require an alert verb, OR a sentence
        // that opens with when/if, OR a strongly-conditional connector.
        let conditional = text.hasPrefix("when ") || text.hasPrefix("if ")
            || contains(text, [" whenever ", " as soon as "])
        // A conditional that's really a question ("if AAPL drops below 300,
        // should I buy?") wants advice, not a silent alert. An explicit alert
        // verb still wins — "notify me when…" is an alert even with a "?".
        let isQuestion = text.hasSuffix("?")
            || contains(text, ["should i", "should we", "is it worth", "worth buying",
                                "good idea", "what do you think", "do you think", "would you"])
        guard alertVerb || (conditional && !isQuestion) else { return nil }
        if let percentMove = makePercentMoveTracker(from: text, original: original) {
            return percentMove
        }
        // The comparator + number is what makes this an alert (not prose), so it
        // gates both the crypto and stock paths.
        guard let (comparator, threshold) = parsePriceCondition(text) else { return nil }
        // Honor an explicit cadence if the user gave one; otherwise watch on a
        // few-hour cycle so it actually behaves like an alert.
        let schedule = hasExplicitCadence(text) ? extractSchedule(from: text) : .everyNHours(3)

        if let coin = matchedCoin(in: text) {
            let condition = BriefingCondition(coinID: coin.id, symbol: coin.symbol,
                                              comparator: comparator, threshold: threshold)
            return TrackerSpec(
                title: "\(coin.symbol) alert", kind: .cryptoPrice, subject: coin.id,
                schedule: schedule, council: false,
                confirmation: "Alerts when \(condition.summary) · checks \(schedule.scheduleLabel)",
                prompt: nil, condition: condition
            )
        }
        if let commodity = matchedCommodity(in: text) {
            // Commodity/metal conditions reuse the equity evaluation path via a
            // "commodity:" coinID prefix holding the Yahoo futures symbol (GC=F),
            // so the threshold check is deterministic against live data.
            let condition = BriefingCondition(coinID: "commodity:\(commodity.yahooSymbol)", symbol: commodity.symbol,
                                              comparator: comparator, threshold: threshold)
            return TrackerSpec(
                title: "\(commodity.label) alert", kind: .commodityPrice, subject: commodity.label,
                schedule: schedule, council: false,
                confirmation: "Alerts when \(commodity.label) is \(comparator.phrase) \(condition.thresholdLabel) · checks \(schedule.scheduleLabel)",
                prompt: nil, condition: condition
            )
        }
        if let stock = alertStock(in: text, original: original) {
            // Stock conditions reuse BriefingCondition with a "stock:" coinID
            // prefix (no schema change, back-compatible with crypto conditions).
            let condition = BriefingCondition(coinID: "stock:\(stock.symbol)", symbol: stock.symbol,
                                              comparator: comparator, threshold: threshold)
            return TrackerSpec(
                title: "\(stock.symbol) alert", kind: .stockPrice, subject: stock.symbol,
                schedule: schedule, council: false,
                confirmation: "Alerts when \(condition.summary) · checks \(schedule.scheduleLabel)",
                prompt: nil, condition: condition
            )
        }
        // No structured coin or stock resolved, but this is unmistakably a
        // recurring price ALERT (alert intent + comparator + threshold). Rather
        // than silently drop it to a one-off model chat, preserve it as a
        // web-grounded recurring tracker so commodities (gold, oil), luxury
        // goods (a Rolex Daytona), retail products (iPhone 16 Pro), and
        // long-tail coins still get a real watcher on a schedule.
        let subject = String(conditionalAlertSubject(from: text).prefix(80))
        guard isPriceableAlertSubject(subject, original: original) else { return nil }
        let title = prettyTrackerTitle(from: subject)
        let label = BriefingCondition.thresholdLabel(threshold)
        return TrackerSpec(
            title: "\(title) alert",
            kind: .customPrompt,
            subject: nil,
            schedule: schedule,
            council: false,
            confirmation: "Alerts when \(title) is \(comparator.phrase) \(label) · checks \(schedule.scheduleLabel)",
            prompt: "Using live web search, check the current price of \(subject). If it is \(comparator.phrase) \(label), lead with the alert and cite a source with the price and the time checked. Otherwise return a concise no-alert status with the latest price, how far it is from \(label), and the next check time.",
            condition: nil
        )
    }

    /// Extracts the asset/product being alerted on from a conditional-alert
    /// sentence — "alert me when gold goes above $2,500/oz" → "gold",
    /// "notify me if a Rolex Daytona drops below $30k" → "Rolex Daytona". Strips
    /// the alert lead-in, a leading when/if, and the comparator+threshold clause.
    /// Used by the web-grounded conditional fallback above.
    static func conditionalAlertSubject(from text: String) -> String {
        var s = trackerSubject(from: text)
        for verb in ["alert me when", "alert me if", "notify me when", "notify me if",
                     "let me know when", "let me know if", "tell me when", "tell me if",
                     "ping me when", "ping me if", "warn me when", "warn me if",
                     "message me when", "message me if", "remind me when", "remind me if",
                     "alert me", "notify me", "let me know", "ping me", "warn me",
                     "message me", "remind me"] {
            s = s.replacingOccurrences(of: verb, with: " ", options: .caseInsensitive)
        }
        s = s.replacingOccurrences(of: #"^\s*(when|if|whenever|once|as soon as)\s+"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        // Drop everything from the comparator onward — the condition clause:
        // "goes above $2,500/oz", "drops below $30k". The comparator must be
        // followed by a number (modulo $/space) so a subject word that merely
        // contains a comparator token ("over-the-counter price") is left intact.
        s = s.replacingOccurrences(
            of: #"\s*\b(drops?|dips?|falls?|goes?|climbs?|rises?|breaks?|jumps?|reaches|hits|trades?|is|are|moves?|sells?|sinks?|tops?)?\s*(below|under|above|over|less than|greater than|higher than|lower than|more than|down to|up to|exceeds)\s+\$?\s*[0-9].*$"#,
            with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ?.!,'\""))
        return s
    }

    /// Commodities/metals the model can price via web search — these mark a
    /// subject as priceable even without a "$".
    static let priceableCommodityKeywords: Set<String> = [
        "gold", "silver", "platinum", "palladium", "copper", "nickel", "aluminum",
        "aluminium", "zinc", "lithium", "uranium", "oil", "crude", "brent", "wti",
        "gasoline", "diesel", "natgas", "wheat", "corn", "soybean", "soybeans",
        "coffee", "sugar", "cotton", "cocoa", "lumber"
    ]

    /// Abstract metrics that take a "below/above N" but are NOT prices, so an
    /// alert about them must never become a fake recurring price watcher.
    static let nonPriceMetricWords: Set<String> = [
        "coverage", "cpu", "gpu", "ram", "memory", "disk", "queue", "latency",
        "occupancy", "attendance", "rate", "ratio", "uptime", "downtime", "sla",
        "temperature", "humidity", "speed", "count", "level", "load", "usage",
        "traffic", "bandwidth", "fps", "ping", "votes", "followers", "subscribers"
    ]

    /// Filler/pronoun tokens that never name a priceable asset on their own.
    static let alertSubjectFillers: Set<String> = [
        "the", "and", "for", "with", "current", "latest", "live", "today",
        "tomorrow", "their", "your", "our", "his", "her", "its", "this", "that",
        "these", "those", "mine", "ours", "yours", "them"
    ]

    /// True when the leftover alert subject is a plausibly *priceable* thing — it
    /// names a real asset/product AND carries a price signal (a "$", a
    /// commodity/coin keyword, a product cue, or an explicit price word).
    /// Abstract-metric alerts ("coverage drops below 80", "cpu above 90") and
    /// pronoun-only subjects ("it below $100") fail this gate and fall through to
    /// the model instead of becoming a bogus recurring price tracker.
    static func isPriceableAlertSubject(_ subject: String, original: String) -> Bool {
        let lower = subject.lowercased()
        let nouns = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
            .filter { $0.count >= 3 && !alertSubjectFillers.contains($0) }
        guard !nouns.isEmpty, !nouns.allSatisfy(nonPriceMetricWords.contains) else { return false }
        return original.contains("$")
            || hasProductPriceContext(lower)
            || matchedCoin(in: lower) != nil
            || nouns.contains(where: priceableCommodityKeywords.contains)
            || contains(lower, ["price", "worth", "cost", "valuation", "quote", "resale", "floor", "spot"])
    }

    /// "alert me if NEAR moves more than 5%" is a percentage-move alert, not
    /// an absolute price alert at $5. Preserve it as a model-routed tracker
    /// until the local condition schema supports percent-change gates.
    static func makePercentMoveTracker(from text: String, original: String) -> TrackerSpec? {
        guard let percent = parsePercentageMoveThreshold(text) else { return nil }
        let schedule = hasExplicitCadence(text) ? extractSchedule(from: text) : .everyNHours(3)
        let percentLabel = formatPercentMove(percent)

        if let coin = matchedCoin(in: text) {
            return TrackerSpec(
                title: "\(coin.symbol) move alert",
                kind: .customPrompt,
                subject: nil,
                schedule: schedule,
                council: false,
                confirmation: "Alerts when \(coin.symbol) moves \(percentLabel)+ in 24h · checks \(schedule.scheduleLabel)",
                prompt: "Using live market data or web search, check \(coin.symbol) / USD and its 24h percent move. If the absolute 24h move is at least \(percentLabel), lead with the alert and explain the move briefly with sources. If it is below \(percentLabel), return a concise no-alert status with the latest price, the 24h move, and next check time."
            )
        }

        if let stock = alertStock(in: text, original: original) {
            return TrackerSpec(
                title: "\(stock.symbol) move alert",
                kind: .customPrompt,
                subject: nil,
                schedule: schedule,
                council: false,
                confirmation: "Alerts when \(stock.symbol) moves \(percentLabel)+ in 24h · checks \(schedule.scheduleLabel)",
                prompt: "Using live market data or web search, check \(stock.symbol) and its latest daily percent move. If the absolute move is at least \(percentLabel), lead with the alert and explain the move briefly with sources. If it is below \(percentLabel), return a concise no-alert status with the latest price, the percent move, and next check time."
            )
        }

        return nil
    }

    /// Resolves a stock for an ALERT (lenient — the alert verb + threshold is the
    /// cue, so no stock/price word is required): a `$ticker`, a known all-caps
    /// ticker, or a known company name.
    static func alertStock(in text: String, original: String) -> (symbol: String, label: String)? {
        for raw in original.split(whereSeparator: { !$0.isLetter && $0 != "$" }).map(String.init) {
            let token = raw.hasPrefix("$") ? String(raw.dropFirst()) : raw
            guard (1...5).contains(token.count) else { continue }
            let up = token.uppercased()
            if (raw.hasPrefix("$") || token == up), let stock = knownStocks.first(where: { $0.symbol == up }) {
                return (up, stock.names.first?.capitalized ?? up)
            }
        }
        // A bare company name next to a non-asset noun ("Disney tickets",
        // "Netflix subscription", "Apple store") is about the product, not the
        // equity. The explicit-ticker path above already returned; here we only
        // have a fuzzy name match, so a product/service noun disqualifies it.
        let nonAssetContext = hasProductPriceContext(text) ||
            contains(text, ["ticket", "tickets", "movie", "movies", "show", "concert",
                                              "flight", "hotel", "seat", "seats", "merch", "subscription",
                                              "store", "shop", "park", "ride", "menu", "delivery"])
        guard !nonAssetContext else { return nil }
        for stock in knownStocks {
            for name in stock.names where wordPresent(name, in: text) {
                return (stock.symbol, name.capitalized)
            }
        }
        return nil
    }

    /// Extracts a price comparator + threshold from alert text. Recognizes
    /// below/above synonyms and $/comma/k/m number forms. When both directions
    /// appear, the earliest-mentioned one wins.
    static func parsePriceCondition(_ text: String) -> (BriefingComparator, Double)? {
        let belowWords = ["drops below", "dips below", "falls below", "drop below", "goes below",
                          "below", "under", "less than", "lower than", "down to", "<"]
        let aboveWords = ["climbs above", "rises above", "goes above", "breaks above", "jumps above",
                          "greater than", "more than", "higher than", "above", "over", "exceeds",
                          "reaches", "hits", "up to", ">"]
        func earliest(_ words: [String]) -> (pos: Int, value: Double)? {
            var best: (pos: Int, value: Double)?
            for w in words {
                let pattern = NSRegularExpression.escapedPattern(for: w)
                    + #"\s*\$?\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*([km])?"#
                guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                guard let m = re.firstMatch(in: text, options: [], range: range),
                      let numR = Range(m.range(at: 1), in: text),
                      var value = Double(text[numR].replacingOccurrences(of: ",", with: "")) else { continue }
                if let fullRange = Range(m.range, in: text),
                   text[fullRange.upperBound...].drop(while: { $0.isWhitespace }).first == "%" {
                    continue
                }
                if m.range(at: 2).location != NSNotFound, let sufR = Range(m.range(at: 2), in: text) {
                    switch text[sufR].lowercased() {
                    case "k": value *= 1_000
                    case "m": value *= 1_000_000
                    default: break
                    }
                }
                let pos = m.range.location
                if best == nil || pos < best!.pos { best = (pos, value) }
            }
            return best
        }
        let below = earliest(belowWords)
        let above = earliest(aboveWords)
        switch (below, above) {
        case let (b?, a?): return b.pos <= a.pos ? (.below, b.value) : (.above, a.value)
        case let (b?, nil): return (.below, b.value)
        case let (nil, a?): return (.above, a.value)
        case (nil, nil): return nil
        }
    }

    static func parsePercentageMoveThreshold(_ text: String) -> Double? {
        let patterns = [
            #"\b(?:moves?|changes?|swings?|gains?|loses?|drops?|rises?|falls?)\b.{0,48}\b(?:more than|over|above|at least|greater than|>=)\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*%"#,
            #"\b([0-9][0-9,]*(?:\.[0-9]+)?)\s*%\s*(?:move|moves|change|changes|swing|swings|gain|gains|loss|losses|drop|drops|rise|rises)\b"#
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = re.firstMatch(in: text, options: [], range: range),
                  let valueRange = Range(match.range(at: 1), in: text),
                  let value = Double(text[valueRange].replacingOccurrences(of: ",", with: "")) else { continue }
            return value
        }
        return nil
    }

    static func formatPercentMove(_ percent: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = percent.rounded() == percent ? 0 : 2
        formatter.minimumFractionDigits = 0
        let value = formatter.string(from: NSNumber(value: percent)) ?? "\(percent)"
        return "\(value)%"
    }

    /// True when the text names a concrete cadence/time, so we keep it instead of
    /// defaulting an alert to the few-hour watch cycle.
    static func hasExplicitCadence(_ text: String) -> Bool {
        if text.range(of: #"\b\d{1,2}(:\d{2})?\s*(am|pm)\b"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"\bevery\s+\d+\s*(h|hr|hrs|hour|hours|min|mins|minutes)\b"#, options: .regularExpression) != nil { return true }
        return contains(text, [" every morning", " every day", " each day", " daily", " weekly",
                               " biweekly", " bi-weekly", " every other week", " monthly",
                               " every month", " once a month", " every week", " every weekday",
                               " every business day", " business days", " weekdays", " each morning",
                               " every evening", " nightly", " every hour", " hourly", " every night",
                               " at noon", " at midnight", " every monday", " every tuesday",
                               " every wednesday", " every thursday", " every friday",
                               " every saturday", " every sunday", " each monday", " each tuesday",
                               " each wednesday", " each thursday", " each friday", " each saturday",
                               " each sunday"])
    }

    static func hasRecurringCadence(_ text: String) -> Bool {
        if text.range(of: #"\bevery\s+\d+\s*(h|hr|hrs|hour|hours|min|mins|minutes)\b"#, options: .regularExpression) != nil { return true }
        return contains(text, [" every morning", " every day", " each day", " daily", " weekly",
                               " biweekly", " bi-weekly", " every other week", " monthly",
                               " every month", " once a month", " every week", " every weekday",
                               " every business day", " business days", " weekdays", " each morning",
                               " every evening", " nightly", " every hour", " hourly", " every night",
                               " every monday", " every tuesday", " every wednesday", " every thursday",
                               " every friday", " every saturday", " every sunday", " each monday",
                               " each tuesday", " each wednesday", " each thursday", " each friday",
                               " each saturday", " each sunday"])
    }

    /// Strips the "create a tracker … every morning … using council" scaffolding
    /// so the scheduled briefing runs on the user's actual question.
    static func cleanedTrackerPrompt(from raw: String) -> String {
        var s = raw
        let phrases = [
            "using council", "with council", "via council", "by the council", "by council", "as a council", "council",
            "every weekday morning", "every weekday", "each weekday", "every morning", "each morning",
            "every single day", "every day", "each day", "every business day", "business days",
            "every week", "weekly", "daily", "weekdays", "weekday"
        ]
        for p in phrases {
            s = s.replacingOccurrences(of: p, with: " ", options: .caseInsensitive)
        }
        s = s.replacingOccurrences(of: #"\bevery\s+\d+\s*(h|hr|hrs|hour|hours|min|mins|minutes)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(
            of: #"\b(every|each|on)\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)s?\b"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        s = s.replacingOccurrences(of: #"\b(at\s+)?\d{1,2}(:\d{2})?\s*(am|pm)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(
            of: #"^\s*(please\s+)?(create|set ?up|make|build|schedule|start|add)\s+(an|the|a)?\b\s*(tracker|briefing|alert|watcher|digest)\s*(to|for|that|which)?\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matchedCoin(in text: String) -> LiveCoin? {
        // Longest keyword first so "near protocol" beats "near".
        let candidates = liveCoins.flatMap { coin in coin.keywords.map { (coin, $0) } }
            .sorted { $0.1.count > $1.1.count }
        for (coin, keyword) in candidates where wordPresent(keyword, in: text) {
            return coin
        }
        return nil
    }

    static func extractAccount(from text: String) -> String? {
        // A token ending in .near, e.g. "abhishek.near". Only mainnet (.near):
        // the account widget's RPC + FastNEAR are mainnet-only, so capturing a
        // .testnet id would surface a misleading "not found on mainnet" — let
        // those fall through to the model instead.
        let words = text.replacingOccurrences(of: "?", with: " ").split(separator: " ")
        for word in words {
            let w = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if w.hasSuffix(".near"), w.count > 5 {
                return w
            }
        }
        return nil
    }

    /// Pulls a place out of a weather prompt: "weather in tokyo" → "tokyo",
    /// "new york forecast" → "new york". Returns nil when only filler remains.
    static func extractLocation(from text: String, keywords: [String] = ["weather", "forecast", "temperature"]) -> String? {
        for separator in [" in ", " at ", " for "] {
            if let range = text.range(of: separator) {
                let candidate = String(text[range.upperBound...])
                guard !containsChainedAction(candidate) else { return nil }
                return cleanLocation(candidate)
            }
        }
        for keyword in keywords {
            if let range = text.range(of: keyword), range.lowerBound > text.startIndex {
                let candidate = String(text[..<range.lowerBound])
                guard !containsChainedAction(candidate) else { return nil }
                return cleanLocation(candidate)
            }
        }
        return nil
    }

    static func containsChainedAction(_ text: String) -> Bool {
        let lower = text.lowercased()
        return contains(lower, [
            " and remind me", " then remind me", " and set a reminder", " then set a reminder",
            " and create", " then create", " and make", " then make",
            " and track", " then track", " and schedule", " then schedule",
            " and add to calendar", " then add to calendar"
        ])
    }

    static func cleanLocation(_ raw: String) -> String? {
        var location = raw.lowercased()
        let fillers = [
            "what's the", "whats the", "what is the", "how's the", "hows the",
            "how is the", "show me the", "tell me the", "give me the",
            "what", "whats", "when", "whens", "is it", "do you", "does it",
            "current", "today's", "todays", "today", "tonight", "tomorrow",
            "right now", "now", "this week", "like", "weather", "forecast",
            "temperature", "time", "clock", "the", "in", "at", "for"
        ]
        for filler in fillers {
            location = location.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: filler))\\b",
                with: " ",
                options: .regularExpression
            )
        }
        location = location.replacingOccurrences(of: "[?.,!]", with: " ", options: .regularExpression)
        location = location.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !location.isEmpty else { return nil }
        // Reject time-duration fillers so "time in a bit" / "in five minutes"
        // fall through to the model instead of geocoding a non-place.
        let durationFillers: Set<String> = ["a bit", "a while", "a moment", "a sec", "a second", "a minute", "a couple", "a few", "the morning", "the afternoon", "the evening", "bed"]
        if durationFillers.contains(location) { return nil }
        if location.range(of: #"\b(minutes?|hours?|seconds?|mins?|secs?)\b"#, options: .regularExpression) != nil {
            return nil
        }
        // Reject abstract non-place nouns so figurative phrasing ("what's the
        // weather like in a relationship", "in general", "in control") falls
        // through to the model instead of geocoding a non-place. Multi-word
        // real places (e.g. "new york") are unaffected — only exact matches of
        // these abstractions are dropped.
        let placeless = location.replacingOccurrences(
            of: #"^(a|an|the|my|your|our|this|that)\s+"#, with: "", options: .regularExpression
        )
        let nonPlaceNouns: Set<String> = [
            "relationship", "relationships", "love", "charge", "control",
            "general", "trouble", "debt", "life", "doubt", "secret", "denial",
            "theory", "practice", "question", "jeopardy", "vain", "retrospect",
            "hindsight", "moment", "mood", "zone", "dark", "fact", "particular",
            "common", "private", "public", "person", "danger", "limbo", "style",
            "roadmap", "backlog", "sprint", "launch", "strategy", "plan",
            "plans", "pipeline", "product", "review", "critique", "pricing"
        ]
        let nonPlacePhrases: Set<String> = [
            "product roadmap", "app roadmap", "product launch", "app launch",
            "launch plan", "release plan", "design review", "product review",
            "growth strategy", "go to market", "go-to-market"
        ]
        if nonPlacePhrases.contains(placeless) { return nil }
        if nonPlaceNouns.contains(placeless) { return nil }
        return location
    }

    static func parseFX(_ text: String) -> (amount: Double, from: String, to: String)? {
        let pattern = #"(\d[\d,]*(?:\.\d+)?)?\s*([a-z]{3,8})\s+(?:to|in|into|as)\s+([a-z]{3,8})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
        guard let from = currencyCode(group(2)), let to = currencyCode(group(3)), from != to else {
            return nil
        }
        let amount = group(1).flatMap { Double($0.replacingOccurrences(of: ",", with: "")) } ?? 1
        return (amount > 0 ? amount : 1, from, to)
    }

    static func currencyCode(_ raw: String?) -> String? {
        guard let token = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !token.isEmpty else { return nil }
        let map: [String: String] = [
            "usd": "USD", "dollar": "USD", "dollars": "USD", "buck": "USD", "bucks": "USD",
            "eur": "EUR", "euro": "EUR", "euros": "EUR",
            "gbp": "GBP", "pound": "GBP", "pounds": "GBP", "sterling": "GBP", "quid": "GBP",
            "jpy": "JPY", "yen": "JPY",
            "inr": "INR", "rupee": "INR", "rupees": "INR",
            "cny": "CNY", "rmb": "CNY", "yuan": "CNY",
            "chf": "CHF", "franc": "CHF", "francs": "CHF",
            "cad": "CAD", "aud": "AUD", "nzd": "NZD", "sgd": "SGD", "hkd": "HKD",
            "krw": "KRW", "won": "KRW", "aed": "AED", "dirham": "AED",
            "brl": "BRL", "real": "BRL", "mxn": "MXN", "zar": "ZAR", "sek": "SEK", "nok": "NOK", "dkk": "DKK", "pln": "PLN", "try": "TRY", "lira": "TRY"
        ]
        // Only recognized currencies — keeps arbitrary 3-letter words
        // ("add abc to xyz") from being treated as a conversion.
        return map[token]
    }
}
