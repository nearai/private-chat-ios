import Foundation

enum QuickIntentParser {
    static func parse(_ raw: String) -> QuickIntent? {
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmedRaw.lowercased()
        guard !text.isEmpty else { return nil }
        let blocksLiveNetwork = blocksLiveNetwork(text)

        // 0) memory — recall stored facts, or store a new one. Checked first so
        // "remember that …" never gets mistaken for a tracker/reminder.
        if contains(text, ["what do you remember", "what do you know about me", "what have you remembered", "what's in your memory", "whats in your memory", "show my memory", "show what you remember"]) {
            return .recallMemory
        }
        if isActivityLogRequest(text) {
            return .activityLog
        }
        // Every needle names a tracker/alert/briefing, so ambiguous phrases like
        // "what are you watching on tv" can't be mistaken for this.
        if isListTrackersRequest(text) {
            return .listTrackers
        }
        // Capabilities / help — EXACT (punctuation-stripped) match only, so
        // "help me write an email" or "what can you help me with my taxes" stay
        // model questions and don't trip the capabilities card.
        let helpNormalized = text.trimmingCharacters(in: CharacterSet(charactersIn: " ?.!"))
        if Self.capabilityPhrases.contains(helpNormalized) {
            return .capabilities
        }
        // Passive-memory control — checked before the generic forget/remember so
        // "stop remembering things automatically" isn't read as a fact to store.
        if contains(text, ["stop learning about me", "stop auto memory", "stop auto-remember",
                            "stop auto remembering", "disable passive memory", "disable auto memory",
                            "turn off passive memory", "turn off auto memory", "don't auto-remember",
                            "dont auto-remember", "stop remembering things automatically",
                            "stop automatically remembering"]) {
            return .setMemoryCapture(enabled: false)
        }
        if contains(text, ["start learning about me", "enable passive memory", "enable auto memory",
                            "turn on passive memory", "turn on auto memory", "resume learning about me",
                            "auto-remember again", "start remembering things automatically"]) {
            return .setMemoryCapture(enabled: true)
        }
        // Document privacy mode — keep attached docs entirely on-device. Treat
        // these as commands, not discussion topics ("can I upload documents?").
        if let documentPrivacy = documentPrivacyCommand(text) {
            return .setDocumentPrivacy(onDevice: documentPrivacy)
        }
        if contains(text, ["forget what you learned automatically", "forget what you auto", "forget the auto-learned",
                            "forget auto-learned", "clear auto memory", "clear what you inferred",
                            "forget what you picked up", "forget what you noticed", "forget the inferred",
                            "forget things you learned on your own"]) {
            return .forgetAutoLearned
        }
        if let fact = parseRemember(text, original: trimmedRaw) {
            return .remember(text: fact)
        }
        if isClearAllMemoryCommand(text) {
            return .forget(text: nil)
        }
        if let toForget = parseForget(text, original: trimmedRaw) {
            return .forget(text: toForget)
        }
        if let query = parseSearchHistory(text, original: trimmedRaw) {
            return .searchHistory(query: query)
        }

        // 0a3) Daily Brief — compose everything tracked + a market snapshot. Only
        // a BARE brief request triggers it (exact phrase after stripping schedule/
        // filler), so "set up a daily briefing about X" stays a normal briefing
        // tracker and "brief me on the AI market" goes to the model.
        if let recurring = parseBrief(text) {
            if recurring {
                let schedule = extractSchedule(from: text)
                return .createTracker(TrackerSpec(
                    title: "Daily brief", kind: .dailyBrief, subject: nil, schedule: schedule,
                    council: false, confirmation: "Daily brief · \(schedule.scheduleLabel)"
                ))
            }
            return .briefMe
        }

        // 0b) conditional price alert — "notify me when ETH drops below $2,000".
        // Checked before the generic tracker path so an alert isn't mistaken for
        // a plain recurring price briefing. Has its own strict gate (alert/when +
        // coin + comparator + number), so ordinary prose can't trip it.
        if !blocksLiveNetwork, let spec = makeConditionalTracker(from: text, original: trimmedRaw) {
            return .createTracker(spec)
        }

        // 1) "create a tracker / watch / every morning …" — fires when the prompt
        // either names a schedule (createVerb + trackerNoun) OR asks to watch some
        // informational subject (watchVerb + an info cue like "price"/"value"),
        // so "track the price of a Rolex GMT Master II" becomes a web-grounded
        // recurring tracker while "remind me to stretch daily" stays a reminder.
        let createVerb = contains(text, [
            "create", "make", "set up", "set-up", "setup", "build", "schedule",
            "start", "add", "track", "watch", "monitor", "follow", "check", "run",
            "research", "scan", "look up", "look for", "find", "investigate"
        ])
        let trackerNoun = contains(text, [
            "tracker", "watcher", "alert", "briefing", "brief", "digest", "cron",
            "cron job", "recurring", "scheduled task", "every day", "every morning",
            "each morning", "each day", "every weekday", "daily", "weekly",
            "hourly", "every hour", "every evening", "nightly"
        ])
        let infoCue = contains(text, ["price", "value", "cost", "worth", "quote", "rate", "index", "stock",
                                      "score", "news", "level", "status", "forecast", "floor price", "market cap",
                                      "how much", "trading at"])
        let hasScheduleCue = trackerNoun || hasExplicitCadence(text)
        // "track that / watch it daily" → track whatever the last answer was
        // about (checked before the generic gate; the pronoun has no subject).
        if parseTrackLast(text) {
            return .trackLast(schedule: extractSchedule(from: text))
        }
        if let recurringReminder = makeRecurringReminderTracker(from: text, original: trimmedRaw) {
            return .createTracker(recurringReminder)
        }
        if shouldPreviewInsteadOfCreate(text) || hasUnsupportedRecurringCadence(text) {
            return nil
        }
        if blocksLiveNetwork,
           (createVerb && hasScheduleCue) || startsWithWatchCommand(text) {
            return nil
        }
        if createVerb && hasScheduleCue && isNearAccountTrackerRequest(text) && extractAccount(from: text) == nil {
            return .requestNearAccountTracker(schedule: extractSchedule(from: text))
        }
        if (createVerb && hasScheduleCue) || (startsWithWatchCommand(text) && (infoCue || parseStock(text, original: trimmedRaw) != nil || parseWatchlistAssets(text) != nil)),
           let spec = makeTracker(from: text, original: trimmedRaw) {
            return .createTracker(spec)
        }

        // 1b) watchlist — an explicit "watchlist" of ≥2 assets shown as one card.
        if contains(text, ["watchlist", "watch list"]), hasUnresolvedAssetListSubject(text) {
            return nil
        }
        if contains(text, ["watchlist", "watch list"]), let serialized = parseWatchlistAssets(text) {
            return .watchlist(serialized: serialized)
        }

        // 2) news — only a BARE request ("news", "headlines", "what's
        // happening") gets the instant multi-source feed. A request that names a
        // topic ("what's happening in global politics", "tech news") carries a
        // subject the feed can't honor, so it falls through to the web-grounded
        // model for a real answer on that topic.
        if !blocksLiveNetwork,
           contains(text, ["news", "headlines", "what's happening", "whats happening", "top stories", "current events"]),
           isBareNewsRequest(text) {
            return .news
        }

        // 2a2) trending crypto — specific phrases only, so it doesn't swallow a
        // single-coin price question.
        if !blocksLiveNetwork,
           contains(text, ["trending coin", "trending coins", "trending crypto", "trending token",
                            "trending tokens", "trending cryptocurrencies", "what's trending in crypto",
                            "whats trending in crypto", "what is trending in crypto", "crypto trending",
                            "what's hot in crypto", "whats hot in crypto", "top trending coins",
                            "what coins are trending", "what crypto is trending"]) {
            return .trendingCrypto
        }

        // 2a3) crypto market overview — total cap / dominance.
        if !blocksLiveNetwork,
           contains(text, ["crypto market", "how's the crypto market", "hows the crypto market",
                            "how is the crypto market", "crypto market overview", "total market cap",
                            "total crypto market cap", "market cap of crypto", "btc dominance",
                            "bitcoin dominance", "eth dominance", "state of crypto", "state of the crypto market"]) {
            return .cryptoMarket
        }

        // 2a4) stocks — a ticker/company with a stock or price cue ("AAPL price",
        // "Tesla stock", "$NVDA"). Conservatively gated so prose isn't hijacked.
        if !blocksLiveNetwork, hasMixedKnownUnknownValueAsk(text) {
            return nil
        }
        if !blocksLiveNetwork, let stock = parseStock(text, original: trimmedRaw) {
            return .stock(symbol: stock.symbol, company: stock.company)
        }

        // 2b) weather — needs an extractable place ("weather in tokyo",
        // "tokyo forecast"). Without a place we fall through to the model.
        if !blocksLiveNetwork,
           contains(text, ["weather", "forecast", "temperature"]),
           !looksLikeNonWeatherForecast(text),
           let place = extractLocation(from: text) {
            return .weather(query: place)
        }

        // 2c) world time — "what time is it in tokyo", "london time". The
        // place gate keeps "time to go" / "what time do you close" out.
        if !blocksLiveNetwork,
           requestsWorldTime(text),
           let place = extractLocation(from: text, keywords: ["time", "clock"]) {
            return .worldTime(query: place)
        }

        // 2d) dictionary definition ("define serendipity", "what does X mean").
        if let word = parseDefineWord(text) {
            return .define(word: word)
        }

        // 2e) calculator ("12*7+3", "what's 18% of 85.50"). Gated on a digit +
        // an operator/percent that actually evaluates, so prose and the
        // currency/unit phrases ("100 usd to eur") below are untouched.
        if let math = parseMath(text, original: trimmedRaw) {
            return .math(expression: math.expression, result: math.result)
        }

        // 2f) date math ("how many days until Christmas", "what's the date in 2
        // weeks"). Needs a resolvable holiday/date or an explicit span.
        if let dateMath = parseDateMath(text, original: trimmedRaw) {
            return .dateMath(question: dateMath.question, answer: dateMath.answer)
        }

        // 2g) tip & bill split ("20% tip on $85 split 3 ways", "split $120 by 4").
        // Needs a $-amount plus a tip % or a party size to actually compute.
        if let tipSplit = parseTipSplit(text) {
            return .tipSplit(summary: tipSplit)
        }

        // 3) NEAR account — named phrases, or a .near token plus a status word.
        // A .testnet id is present but unservable (mainnet-only widget); skip the
        // whole branch so it reaches the model rather than asking for a .near id.
        let account = extractAccount(from: text)
        let mentionsTestnet = text.contains(".testnet")
        if !blocksLiveNetwork,
           !mentionsTestnet,
           contains(text, ["my near account", "near account", "near.com account", "account doing", "account balance", "wallet balance", "my wallet", "my balance"]) ||
            (account != nil && contains(text, ["doing", "balance", "holdings", "how is", "status", "account", "wallet", "worth"])) {
            return .nearAccount(account: account)
        }

        // 3b) currency conversion ("convert 100 usd to eur", "50 gbp in usd").
        // The currency-code gate keeps "translate X to spanish" out.
        if !blocksLiveNetwork, let fx = parseFX(text) {
            return .fx(amount: fx.amount, from: fx.from, to: fx.to)
        }

        // 3c) unit conversion ("5 miles in km", "100 f to c", "10 kg to lb").
        if let unit = parseUnitConversion(text) {
            return .unitConvert(value: unit.value, from: unit.from, to: unit.to)
        }

        // 4) price of a coin (a bare "?" is not enough — it swallows
        // "can you explain ethereum?" — so require an explicit price word).
        if !blocksLiveNetwork,
           let coin = matchedCoin(in: text),
           contains(text, ["price", "worth", "trading", "how much", "value", "cost"]) {
            return .price(coinID: coin.id, symbol: coin.symbol)
        }

        // 5) personal reminder — checked LAST so trackers, alerts, and data
        // lookups win first. Only fires for a "remind me…" with a real time, so
        // "remind me why the sky is blue" stays a model question.
        if let reminder = parseReminder(text, original: trimmedRaw) {
            return .createReminder(reminder)
        }

        return nil
    }
}
