import Foundation

// LiveDataService — turns auth-free public APIs into MessageWidgets so the named
// use cases ("what is ETH price", "how is my NEAR account doing", "pull daily
// news") produce real answers through the widget/briefing UX without the chat
// backend. Filled in by a ring-fenced workstream.

// Coins recognized in prompts ("eth price", "track near every morning").
struct LiveCoin: Equatable {
    let id: String      // CoinGecko id
    let symbol: String  // display symbol
    let keywords: [String]
}

let liveCoins: [LiveCoin] = [
    LiveCoin(id: "ethereum", symbol: "ETH", keywords: ["ethereum", "eth", "ether"]),
    LiveCoin(id: "near", symbol: "NEAR", keywords: ["near protocol", "near"]),
    LiveCoin(id: "bitcoin", symbol: "BTC", keywords: ["bitcoin", "btc"]),
    LiveCoin(id: "solana", symbol: "SOL", keywords: ["solana", "sol"]),
    LiveCoin(id: "dogecoin", symbol: "DOGE", keywords: ["dogecoin", "doge"])
]

func liveCoin(forID id: String) -> LiveCoin? {
    liveCoins.first { $0.id == id.lowercased() }
}

/// What a typed prompt should do, parsed locally so common data questions and
/// "create a tracker…" commands work without the chat backend.
enum QuickIntent: Equatable {
    case price(coinID: String, symbol: String)
    case trendingCrypto
    case cryptoMarket
    case briefMe
    case nearAccount(account: String?)
    case news
    case weather(query: String)
    case worldTime(query: String)
    case fx(amount: Double, from: String, to: String)
    case unitConvert(value: Double, from: String, to: String)
    case define(word: String)
    case math(expression: String, result: String)
    case dateMath(question: String, answer: String)
    case tipSplit(summary: String)
    case remember(text: String)
    case recallMemory
    case forget(text: String?)
    case forgetAutoLearned
    case setMemoryCapture(enabled: Bool)
    case activityLog
    case listTrackers
    case capabilities
    case searchHistory(query: String)
    case createReminder(PersonalReminder)
    case createTracker(TrackerSpec)
    /// "track that" — make a tracker from whatever the previous answer was about.
    case trackLast(schedule: BriefingSchedule)
}

/// A one-off personal reminder parsed from natural language ("remind me to call
/// mom at 5pm"). Delivered as a local notification at `date`.
struct PersonalReminder: Equatable {
    var title: String
    var date: Date
}

struct TrackerSpec: Equatable {
    var title: String
    var kind: BriefingKind
    var subject: String?            // coin id (price) or account (nearAccount)
    var schedule: BriefingSchedule
    var council: Bool
    var confirmation: String
    var prompt: String?             // cleaned prompt for customPrompt council trackers
    var condition: BriefingCondition?  // threshold gate ("when ETH < $2,000"); nil = plain recurring
}

enum QuickIntentParser {
    static func parse(_ raw: String) -> QuickIntent? {
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmedRaw.lowercased()
        guard !text.isEmpty else { return nil }

        // 0) memory — recall stored facts, or store a new one. Checked first so
        // "remember that …" never gets mistaken for a tracker/reminder.
        if contains(text, ["what do you remember", "what do you know about me", "what have you remembered", "what's in your memory", "whats in your memory", "show my memory", "show what you remember"]) {
            return .recallMemory
        }
        if contains(text, ["what have you done", "what did you do", "show your activity", "activity log", "what have you been up to", "show what you've done", "your recent activity"]) {
            return .activityLog
        }
        // Every needle names a tracker/alert/briefing, so ambiguous phrases like
        // "what are you watching on tv" can't be mistaken for this.
        if contains(text, ["what are you tracking", "show my trackers", "list my trackers",
                            "show my alerts", "list my alerts", "what alerts do i have",
                            "what are my trackers", "my active trackers", "show my briefings",
                            "list my briefings", "my trackers and alerts"]) {
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
        if contains(text, ["forget what you learned automatically", "forget what you auto", "forget the auto-learned",
                            "forget auto-learned", "clear auto memory", "clear what you inferred",
                            "forget what you picked up", "forget what you noticed", "forget the inferred",
                            "forget things you learned on your own"]) {
            return .forgetAutoLearned
        }
        if contains(text, ["forget everything", "forget it all", "forget all", "clear your memory", "clear my memory", "delete your memory", "wipe your memory", "erase your memory"]) {
            return .forget(text: nil)
        }
        if let toForget = parseForget(text, original: trimmedRaw) {
            return .forget(text: toForget)
        }
        if let fact = parseRemember(text, original: trimmedRaw) {
            return .remember(text: fact)
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
        if let spec = makeConditionalTracker(from: text) {
            return .createTracker(spec)
        }

        // 1) "create a tracker / watch / every morning …" — fires when the prompt
        // either names a schedule (createVerb + trackerNoun) OR asks to watch some
        // informational subject (watchVerb + an info cue like "price"/"value"),
        // so "track the price of a Rolex GMT Master II" becomes a web-grounded
        // recurring tracker while "remind me to stretch daily" stays a reminder.
        let createVerb = contains(text, ["create", "make", "set up", "set-up", "setup", "build", "schedule", "start", "add", "track", "watch", "remind"])
        let trackerNoun = contains(text, ["tracker", "watcher", "alert", "briefing", "brief", "digest", "every day", "every morning", "each morning", "each day", "every weekday", "daily", "weekly"])
        let infoCue = contains(text, ["price", "value", "cost", "worth", "quote", "rate", "index", "stock",
                                      "score", "news", "level", "status", "forecast", "floor price", "market cap",
                                      "how much", "trading at"])
        // "track that / watch it daily" → track whatever the last answer was
        // about (checked before the generic gate; the pronoun has no subject).
        if parseTrackLast(text) {
            return .trackLast(schedule: extractSchedule(from: text))
        }
        if (createVerb && trackerNoun) || (startsWithWatchCommand(text) && infoCue),
           let spec = makeTracker(from: text, original: trimmedRaw) {
            return .createTracker(spec)
        }

        // 2) news
        if contains(text, ["news", "headlines", "what's happening", "whats happening", "top stories", "current events"]) {
            return .news
        }

        // 2a2) trending crypto — specific phrases only, so it doesn't swallow a
        // single-coin price question.
        if contains(text, ["trending coin", "trending coins", "trending crypto", "trending token",
                            "trending tokens", "trending cryptocurrencies", "what's trending in crypto",
                            "whats trending in crypto", "what is trending in crypto", "crypto trending",
                            "what's hot in crypto", "whats hot in crypto", "top trending coins",
                            "what coins are trending", "what crypto is trending"]) {
            return .trendingCrypto
        }

        // 2a3) crypto market overview — total cap / dominance.
        if contains(text, ["crypto market", "how's the crypto market", "hows the crypto market",
                            "how is the crypto market", "crypto market overview", "total market cap",
                            "total crypto market cap", "market cap of crypto", "btc dominance",
                            "bitcoin dominance", "eth dominance", "state of crypto", "state of the crypto market"]) {
            return .cryptoMarket
        }

        // 2b) weather — needs an extractable place ("weather in tokyo",
        // "tokyo forecast"). Without a place we fall through to the model.
        if contains(text, ["weather", "forecast", "temperature"]),
           let place = extractLocation(from: text) {
            return .weather(query: place)
        }

        // 2c) world time — "what time is it in tokyo", "london time". The
        // place gate keeps "time to go" / "what time do you close" out.
        if contains(text, ["time", "clock"]),
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
        let account = extractAccount(from: text)
        if contains(text, ["my near account", "near account", "near.com account", "account doing", "account balance", "wallet balance", "my wallet", "my balance"]) ||
            (account != nil && contains(text, ["doing", "balance", "holdings", "how is", "status", "account", "wallet", "worth"])) {
            return .nearAccount(account: account)
        }

        // 3b) currency conversion ("convert 100 usd to eur", "50 gbp in usd").
        // The currency-code gate keeps "translate X to spanish" out.
        if let fx = parseFX(text) {
            return .fx(amount: fx.amount, from: fx.from, to: fx.to)
        }

        // 3c) unit conversion ("5 miles in km", "100 f to c", "10 kg to lb").
        if let unit = parseUnitConversion(text) {
            return .unitConvert(value: unit.value, from: unit.from, to: unit.to)
        }

        // 4) price of a coin (a bare "?" is not enough — it swallows
        // "can you explain ethereum?" — so require an explicit price word).
        if let coin = matchedCoin(in: text),
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

    /// Exact (punctuation-stripped) phrases that surface the capabilities card.
    static let capabilityPhrases: Set<String> = [
        "help", "what can you do", "what can i ask", "what can i ask you",
        "what can you help me with", "what are you capable of", "what are your features",
        "what features do you have", "show me what you can do", "what can this app do",
        "what can this do", "what else can you do", "how do you work", "what do you do"
    ]

    /// A concise tour of what the assistant can do, with copy-pasteable example
    /// prompts. Static + deterministic so it's testable and reusable.
    static func capabilitiesText() -> String {
        """
        Here’s what I can do — all on-device or over public data, no sign-in needed:

        **Live answers** — ask in plain language:
        • “What’s the ETH price?” · “What’s trending in crypto?” · “How’s my account, alice.near?”
        • “Weather in Tokyo” · “What time is it in London?”
        • “Convert 100 USD to EUR” · “5 miles in km” · “Define serendipity”
        • Top headlines · or chain them: “ETH price and weather in Lisbon”

        **Trackers & alerts** — I check on a schedule and surface results on Today:
        • Track *anything*: “Track the price of a Rolex GMT Master II every morning” — I find it on the web and build a chart over time
        • Ask something, then just say “track that” to start watching it
        • “Notify me when ETH drops below $2,000” — I alert once, then pause
        • “Brief me” — one digest of everything I’m tracking + the markets (or “brief me every morning”)
        • “What are you tracking?” to review them

        **Quick math & dates** — instant, on-device:
        • “What’s 18% of 85.50?” · “12 * 7 + 3”
        • “How many days until Christmas?” · “What’s the date in 2 weeks?”

        **Reminders & recall**:
        • “Remind me to call mom at 5pm tomorrow” — I’ll notify you, even if the app’s closed
        • “Search my chats for the Lisbon trip” · “What did I say about my budget?”

        **Memory (private, on this device)**:
        • “Remember I prefer concise answers” · “What do you remember?”
        • I also quietly note durable details you mention — say “stop learning about me” to turn that off, or “forget what you learned automatically.”

        **Hands-free**: tap the mic to dictate, or ask Siri to run your briefings.

        Just type what you want — if it’s a question I can answer live, I will; otherwise I’ll think it through.
        """
    }

    /// Splits a compound prompt ("eth price and weather in tokyo") into the
    /// individual data-lookups it chains. Returns the list only when ≥2 segments
    /// are genuine data intents — so normal prose with "and" falls through.
    static func parseCompound(_ raw: String) -> [QuickIntent]? {
        let lower = raw.lowercased()
        guard lower.contains(" and ") || lower.contains(", ") || lower.contains(" then ")
            || lower.contains(" plus ") || lower.contains(" & ") else {
            return nil
        }
        var segments = [lower]
        for separator in [" and then ", " and also ", ", and ", " and ", " then ", " plus ", " & ", "; ", ", "] {
            segments = segments.flatMap { $0.components(separatedBy: separator) }
        }
        let intents = segments
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { parse($0) }
            .filter { isCompoundable($0) }
        return intents.count >= 2 ? intents : nil
    }

    /// A proactive starter derived from what the assistant remembers — e.g. if
    /// memory mentions a coin the user holds, suggest checking its price. Pure
    /// + deterministic so it's testable; nil when nothing relevant is stored.
    static func personalizedStarter(fromMemory facts: [String]) -> (title: String, prompt: String, symbol: String)? {
        let haystack = facts.joined(separator: " ").lowercased()
        guard !haystack.isEmpty else { return nil }
        // Require finance context around a coin keyword so "I live near Toronto"
        // doesn't surface a NEAR-price starter.
        let financeContext = contains(haystack, [
            "hold", "holding", "own", "invest", "crypto", "portfolio", "bought",
            "buy", "stack", "tokens", "coins", "wallet", "trading", "trade", "hodl", "bags", "position", "price"
        ])
        if financeContext, let coin = matchedCoin(in: haystack) {
            return ("\(coin.symbol) price", "What's the \(coin.symbol) price?", "chart.line.uptrend.xyaxis")
        }
        if contains(haystack, ["news", "headlines", "current events", "world events"]) {
            return ("Today's news", "Pull today's news", "newspaper")
        }
        return nil
    }

    /// Read-only data lookups can be chained; actions (trackers, memory writes)
    /// cannot, so they never get swept into a compound run.
    private static func isCompoundable(_ intent: QuickIntent) -> Bool {
        switch intent {
        case .price, .trendingCrypto, .cryptoMarket, .nearAccount, .news, .weather, .worldTime, .fx, .unitConvert, .define:
            return true
        case .briefMe, .math, .dateMath, .tipSplit, .remember, .recallMemory, .forget, .forgetAutoLearned, .setMemoryCapture, .activityLog, .listTrackers, .capabilities, .searchHistory, .createReminder, .createTracker, .trackLast:
            return false
        }
    }

    /// Builds a tracker only when a real subject is present. Returns nil for
    /// generic "remind me …" prompts and account trackers with no id so the
    /// caller can fall through to the model instead of scheduling a dead fetch.
    private static func makeTracker(from text: String, original: String) -> TrackerSpec? {
        // `council` is recorded for a future scheduled-council runner; today the
        // briefing runner fetches live data, so we don't promise it in the label.
        let council = contains(text, ["council", "panel", "multiple models", "models debate", "debate"])
        let schedule = extractSchedule(from: text)
        let label = schedule.scheduleLabel
        let account = extractAccount(from: text)
        let mentionsAccount = contains(text, ["account", "wallet", "near.com"]) || account != nil

        // Live-data kinds are single deterministic fetches — council is
        // meaningless there, so it's always false regardless of the wording.
        if mentionsAccount, !contains(text, ["price"]) {
            // An account tracker with no id would schedule an empty fetch.
            guard let account else { return nil }
            return TrackerSpec(
                title: "NEAR account",
                kind: .nearAccount,
                subject: account,
                schedule: schedule,
                council: false,
                confirmation: "NEAR account · \(account) · \(label)"
            )
        }
        if contains(text, ["news", "headlines", "stories"]) {
            return TrackerSpec(title: "Daily news", kind: .dailyNews, subject: nil, schedule: schedule, council: false, confirmation: "Daily news · \(label)")
        }
        if let coin = matchedCoin(in: text) {
            return TrackerSpec(
                title: "\(coin.symbol) price",
                kind: .cryptoPrice,
                subject: coin.id,
                schedule: schedule,
                council: false,
                confirmation: "\(coin.symbol) price · \(label)"
            )
        }
        // Open-ended "track/watch the price/value of <X>" for ANY subject we
        // don't have a built-in feed for (a watch, a stock, a collectible…).
        // Becomes a web-grounded recurring custom-prompt tracker — the agentic-OS
        // case: "track the price of a Rolex GMT Master II every morning".
        let infoCue = contains(text, ["price", "value", "cost", "worth", "quote", "rate", "index", "stock",
                                      "score", "level", "status", "forecast", "floor price", "market cap",
                                      "how much", "trading at"])
        if startsWithWatchCommand(text) && infoCue {
            let subject = trackerSubject(from: original)
            guard subject.count >= 2 else { return nil }
            let title = prettyTrackerTitle(from: subject)
            return TrackerSpec(
                title: title,
                kind: .customPrompt,
                subject: nil,
                schedule: schedule,
                council: council,
                confirmation: "Tracking \(title) · \(label)",
                prompt: "Using web search, find the latest \(subject) and report it concisely. Lead with the current number/price (with its currency) and the as-of date, then one short line of context. If it's a price or numeric value, present it as a metric or chart widget."
            )
        }

        // A recurring briefing/digest (or a council request) becomes a scheduled
        // custom-prompt task on the user's actual question. A bare reminder with
        // no informational noun falls through so we don't manufacture trackers
        // from "remind me to stretch".
        let wantsBriefing = council || contains(text, [
            "briefing", "brief", "digest", "summary", "summarize", "summarise",
            "report", "rundown", "recap", "roundup", "round-up"
        ])
        guard wantsBriefing else { return nil }
        let prompt = cleanedTrackerPrompt(from: original)
        guard prompt.count >= 4 else { return nil }
        return TrackerSpec(
            title: council ? "Council briefing" : "Daily briefing",
            kind: .customPrompt,
            subject: nil,
            schedule: schedule,
            council: council,
            confirmation: "\(council ? "Council briefing" : "Briefing") · \(label)",
            prompt: prompt
        )
    }

    /// The subject of an open-ended tracker: the cleaned prompt with leading
    /// watch verbs and articles stripped. "track the price of a Rolex GMT Master
    /// II every morning" → "price of a Rolex GMT Master II".
    static func trackerSubject(from text: String) -> String {
        var subject = cleanedTrackerPrompt(from: text)
        let leadVerbs = ["keep an eye on ", "keep tabs on ", "keep track of ", "track ", "watch ", "monitor ", "follow "]
        var changed = true
        while changed {
            changed = false
            let lower = subject.lowercased()
            for verb in leadVerbs where lower.hasPrefix(verb) {
                subject = String(subject.dropFirst(verb.count)); changed = true; break
            }
            for article in ["the ", "a ", "an ", "my "] where subject.lowercased().hasPrefix(article) {
                subject = String(subject.dropFirst(article.count)); changed = true; break
            }
        }
        return subject.trimmingCharacters(in: CharacterSet(charactersIn: " ?.!,"))
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
        return String(title.prefix(48))
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
        if verb == "watch " && (tail.hasPrefix("out") || tail.hasPrefix("for ")) { return nil }
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
    static func makeConditionalTracker(from text: String) -> TrackerSpec? {
        let alertVerb = contains(text, ["notify", "alert", "tell me", "let me know",
                                        "ping me", "warn me", "message me", "remind me"])
        // A bare mid-sentence "if"/"when" is too loose (it would catch "explain
        // what happens if eth hits 5000"). Require an alert verb, OR a sentence
        // that opens with when/if, OR a strongly-conditional connector.
        let conditional = text.hasPrefix("when ") || text.hasPrefix("if ")
            || contains(text, [" whenever ", " as soon as "])
        guard alertVerb || conditional else { return nil }
        guard let coin = matchedCoin(in: text) else { return nil }
        guard let (comparator, threshold) = parsePriceCondition(text) else { return nil }

        let condition = BriefingCondition(coinID: coin.id, symbol: coin.symbol,
                                          comparator: comparator, threshold: threshold)
        // Honor an explicit cadence if the user gave one; otherwise watch on a
        // few-hour cycle so it actually behaves like an alert.
        let schedule = hasExplicitCadence(text) ? extractSchedule(from: text) : .everyNHours(3)
        return TrackerSpec(
            title: "\(coin.symbol) alert",
            kind: .cryptoPrice,
            subject: coin.id,
            schedule: schedule,
            council: false,
            confirmation: "Alerts when \(condition.summary) · checks \(schedule.scheduleLabel)",
            prompt: nil,
            condition: condition
        )
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

    /// True when the text names a concrete cadence/time, so we keep it instead of
    /// defaulting an alert to the few-hour watch cycle.
    private static func hasExplicitCadence(_ text: String) -> Bool {
        if text.range(of: #"\b\d{1,2}(:\d{2})?\s*(am|pm)\b"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"\bevery\s+\d+\s*(h|hr|hrs|hour|hours|min|mins|minutes)\b"#, options: .regularExpression) != nil { return true }
        return contains(text, [" every morning", " every day", " each day", " daily", " weekly",
                               " every week", " every weekday", " weekdays", " each morning",
                               " every evening", " nightly", " every hour", " hourly", " every night",
                               " at noon", " at midnight", " every monday"])
    }

    /// Strips the "create a tracker … every morning … using council" scaffolding
    /// so the scheduled briefing runs on the user's actual question.
    static func cleanedTrackerPrompt(from raw: String) -> String {
        var s = raw
        let phrases = [
            "using council", "with council", "via council", "by the council", "by council", "as a council", "council",
            "every weekday morning", "every weekday", "each weekday", "every morning", "each morning",
            "every single day", "every day", "each day", "every week", "weekly", "daily", "weekdays", "weekday"
        ]
        for p in phrases {
            s = s.replacingOccurrences(of: p, with: " ", options: .caseInsensitive)
        }
        s = s.replacingOccurrences(of: #"\b(at\s+)?\d{1,2}(:\d{2})?\s*(am|pm)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(
            of: #"^\s*(please\s+)?(create|set ?up|make|build|schedule|start|add)\s+(a|an|the)?\s*(tracker|briefing|alert|watcher|digest)\s*(to|for|that|which)?\s*"#,
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
        // A token ending in .near / .testnet, e.g. "abhishek.near".
        let words = text.replacingOccurrences(of: "?", with: " ").split(separator: " ")
        for word in words {
            let w = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if w.hasSuffix(".near") || w.hasSuffix(".testnet"), w.count > 5 {
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
                return cleanLocation(String(text[range.upperBound...]))
            }
        }
        for keyword in keywords {
            if let range = text.range(of: keyword), range.lowerBound > text.startIndex {
                return cleanLocation(String(text[..<range.lowerBound]))
            }
        }
        return nil
    }

    private static func cleanLocation(_ raw: String) -> String? {
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

    private static func currencyCode(_ raw: String?) -> String? {
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

    static func parseUnitConversion(_ text: String) -> (value: Double, from: String, to: String)? {
        let pattern = #"(-?\d[\d.,]*)\s*(°?[a-z]+)\s+(?:to|in|into|as)\s+(°?[a-z]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
        guard let valueString = group(1)?.replacingOccurrences(of: ",", with: ""),
              let value = Double(valueString),
              let from = group(2), let to = group(3),
              UnitConverter.convert(value: value, from: from, to: to) != nil else {
            return nil
        }
        return (value, from, to)
    }

    /// Pulls the fact out of "remember that …" / "note that …" commands, keeping
    /// the original casing (names, etc.). `text` is lowercased, `original` the
    /// trimmed raw with the same prefix length.
    static func parseRemember(_ text: String, original: String) -> String? {
        let triggers = [
            "remember that ", "remember to ", "remember my ", "remember ",
            "note that ", "make a note that ", "keep in mind that ", "keep in mind ",
            "don't forget that ", "dont forget that ", "don't forget to ", "dont forget to ",
            "for future reference "
        ]
        for trigger in triggers where text.hasPrefix(trigger) {
            // "remember my" keeps the "my" (e.g. "remember my anniversary is …").
            let dropCount = trigger == "remember my " ? "remember ".count : trigger.count
            let fact = String(original.dropFirst(dropCount)).trimmingCharacters(in: .whitespacesAndNewlines)
            return fact.count >= 3 ? fact : nil
        }
        return nil
    }

    /// "search my chats for X" / "what did I say about X" → the search query X.
    /// Trigger-prefixed so ordinary questions don't become history searches.
    static func parseSearchHistory(_ text: String, original: String) -> String? {
        let triggers = [
            "search my chats for ", "search my chat history for ", "search my history for ",
            "search history for ", "search chats for ", "search my conversations for ",
            "find in my chats ", "find in my history ", "find where i talked about ",
            "find where i mentioned ", "find when i talked about ", "find my chat about ",
            "what did i say about ", "what did we say about ", "where did i talk about ",
            "where did we discuss ", "find that chat about "
        ]
        for trigger in triggers where text.hasPrefix(trigger) {
            let query = String(original.dropFirst(trigger.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ?.!\"'"))
            return query.count >= 2 ? query : nil
        }
        return nil
    }

    /// "remind me to call mom at 5pm tomorrow" → a PersonalReminder. Requires a
    /// reminder trigger AND a real date/time (via NSDataDetector), so timeless or
    /// question-shaped "remind me…" prompts fall through to the model. The title
    /// is the task with the trigger prefix and every detected date phrase removed.
    static func parseReminder(_ text: String, original: String) -> PersonalReminder? {
        let triggers = ["remind me to ", "remind me that ", "remind me about ", "remind me ",
                        "set a reminder to ", "set a reminder that ", "set a reminder ", "reminder to "]
        guard let trigger = triggers.first(where: { text.hasPrefix($0) }) else { return nil }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let fullRange = NSRange(original.startIndex..<original.endIndex, in: original)
        let dateMatches = detector.matches(in: original, options: [], range: fullRange).filter { $0.date != nil }
        guard let firstDate = dateMatches.first?.date else { return nil }

        // Build the title: remove every detected date phrase (back-to-front so
        // earlier ranges stay valid), then strip the trigger prefix and tidy.
        var title = original
        for match in dateMatches.sorted(by: { $0.range.location > $1.range.location }) {
            if let r = Range(match.range, in: title) { title.removeSubrange(r) }
        }
        if let r = title.range(of: trigger, options: [.caseInsensitive, .anchored]) {
            title.removeSubrange(r)
        }
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        // Drop connectors a removed date left dangling at either end — leading
        // ("remind me on monday … to take meds" → "take meds") and trailing
        // ("… call mom at" → "call mom").
        title = title.replacingOccurrences(of: #"^(?:\b(?:at|on|by|in|this|next|every|and|to)\b[\s,]*)+"#,
                                           with: "", options: [.regularExpression, .caseInsensitive])
        title = title.replacingOccurrences(of: #"(?:[\s,]*\b(?:at|on|by|in|this|next|every|and)\b)+$"#,
                                           with: "", options: [.regularExpression, .caseInsensitive])
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?-"))
        guard title.count >= 2 else { return nil }

        // Reminders are in the future; bump a time that already passed to the next day.
        var fire = firstDate
        if fire <= Date() {
            fire = Calendar.current.date(byAdding: .day, value: 1, to: fire) ?? fire
        }
        return PersonalReminder(title: title, date: fire)
    }

    static func parseForget(_ text: String, original: String) -> String? {
        let triggers = ["forget that ", "forget about ", "forget the ", "forget my ", "forget "]
        for trigger in triggers where text.hasPrefix(trigger) {
            let dropCount = trigger == "forget my " ? "forget ".count : trigger.count
            let fact = String(original.dropFirst(dropCount)).trimmingCharacters(in: .whitespacesAndNewlines)
            return fact.count >= 2 ? fact : nil
        }
        return nil
    }

    /// Passively distils durable, high-confidence self-facts from a user turn —
    /// no "remember" keyword needed. Deliberately narrow: only first-person
    /// identity/preference statements that read as durable. Questions, negations
    /// ("i don't live in…" never matches because the verb isn't adjacent),
    /// assistant-directed phrasings ("i prefer you use…"), and transient ("right
    /// now") wording are rejected. Returns facts in the user's own first-person
    /// framing so they match how explicitly-remembered facts are stored. Capped.
    static func inferredFacts(from raw: String) -> [String] {
        let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = original.lowercased()
        guard lower.count >= 6, lower.count <= 280 else { return [] }
        if lower.contains("?") { return [] }                              // questions aren't disclosures
        if parseRemember(lower, original: original) != nil { return [] }  // explicit path already stores it
        if contains(lower, ["right now", "for now", "at the moment", "this week",
                            "currently", "just now", "these days"]) { return [] } // not durable

        // Pronoun/filler values that signal an assistant-directed or empty phrase.
        let junkValues: Set<String> = ["you", "it", "that", "this", "them", "us", "me",
                                       "not", "no", "yes", "ok", "okay", "sure", "up", "to"]
        // Stop the captured value at a clause/sentence boundary.
        let tail = #"([^.,;!?]+?)(?:\s+(?:and|but|because|so|although|though|when|while)\s|[.,;!?]|$)"#

        var facts: [String] = []
        func push(_ s: String) {
            var f = s.trimmingCharacters(in: .whitespacesAndNewlines)
            f = f.replacingOccurrences(of: #"[\s,.;:!]+$"#, with: "", options: .regularExpression)
            guard f.count >= 4, f.count <= 160 else { return }
            if !facts.contains(where: { $0.caseInsensitiveCompare(f) == .orderedSame }) { facts.append(f) }
        }
        func value(_ pattern: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            let range = NSRange(original.startIndex..<original.endIndex, in: original)
            guard let m = re.firstMatch(in: original, options: [], range: range), m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: original) else { return nil }
            let v = String(original[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Reject whole-value junk and assistant-directed phrasings whose
            // first word is a pronoun/filler ("i prefer you use bullets").
            let firstWord = v.lowercased().split(separator: " ").first.map(String.init) ?? v.lowercased()
            guard v.count >= 2, !junkValues.contains(v.lowercased()), !junkValues.contains(firstWord) else { return nil }
            return v
        }

        // 1) Preference — "I prefer X" / "I'd rather X"
        if let v = value(#"\bi (?:really |honestly |generally |usually |always |typically |strongly )?prefer\s+"# + tail) {
            push("I prefer \(v)")
        } else if let v = value(#"\bi(?:'d| would) rather\s+"# + tail) {
            push("I'd rather \(v)")
        }
        // 2) Location — "I live in X" / "I'm based in X" / "I reside in X"
        if let v = value(#"\bi (?:live|reside) in\s+"# + tail) ?? value(#"\bi(?:'m| am) based in\s+"# + tail) {
            push("I live in \(v)")
        }
        // 3) Name — "my name is X" / "my name's X"
        if let v = value(#"\bmy name(?:'s| is)\s+"# + tail) {
            push("My name is \(v)")
        }
        // 4) Go-by — "call me X" / "you can call me X"
        if let v = value(#"\b(?:you can |please |just )?call me\s+"# + tail) {
            push("I go by \(v)")
        }
        // 5) Work — "I work as a X" / "I work at X" / "I work in X"
        if let v = value(#"\bi work as\s+"# + tail) {
            push("I work as \(v)")
        } else if let v = value(#"\bi work at\s+"# + tail) {
            push("I work at \(v)")
        } else if let v = value(#"\bi work in\s+"# + tail) {
            push("I work in \(v)")
        }
        // 6) Holdings — "I own X" / "I hold X" (useful for a crypto assistant;
        // the (?!up) guard skips the "own up" idiom).
        if let v = value(#"\bi (?:own|hold)\s+(?!up\b)"# + tail) {
            push("I own \(v)")
        }
        // 7) Possessive allowlist — "my <noun> is X". Allowlisted to durable
        // identity/relationship nouns so "my point is…" / "my guess is…" never
        // get stored.
        let possessiveNouns = ["birthday", "anniversary", "timezone", "time zone", "hometown",
                               "favorite color", "favourite color", "dog", "cat", "pet",
                               "wife", "husband", "partner", "spouse", "son", "daughter",
                               "kid", "child", "manager", "boss", "company", "employer",
                               "goal", "nickname"]
        for noun in possessiveNouns {
            if let v = value(#"\bmy "# + NSRegularExpression.escapedPattern(for: noun) + #"(?:'s| is| are)\s+"# + tail) {
                push("My \(noun) is \(v)")
                break // one possessive fact per turn keeps it tidy
            }
        }

        return Array(facts.prefix(3))
    }

    /// "20% tip on $85 split 3 ways" → "Tip $17.00 (20%) · Total $102.00 ·
    /// $34.00 each (3 ways)". Needs a $-amount and either a tip % or a party
    /// size > 1, so plain prose can't trigger it.
    static func parseTipSplit(_ text: String) -> String? {
        let mentionsTip = text.contains("tip")
        let mentionsSplit = contains(text, ["split", " ways", " way ", "each", "between", "among",
                                            "per person", "per head", "divide the"])
        guard mentionsTip || mentionsSplit else { return nil }
        guard let bill = firstCurrencyAmount(in: text) else { return nil }

        var tipPercent = 0.0
        if mentionsTip, let pct = firstRegexDouble(#"([0-9]+(?:\.[0-9]+)?)\s*%"#, in: text) {
            tipPercent = pct
        }
        let party = max(1, partySize(in: text) ?? 1)
        guard tipPercent > 0 || party > 1 else { return nil } // must actually compute something

        let tip = bill * tipPercent / 100
        let total = bill + tip
        func usd(_ v: Double) -> String { String(format: "$%.2f", v) }
        func pctLabel(_ v: Double) -> String { v == v.rounded() ? "\(Int(v))%" : String(format: "%g%%", v) }

        var parts: [String] = []
        if tipPercent > 0 { parts.append("Tip \(usd(tip)) (\(pctLabel(tipPercent)))") }
        parts.append("Total \(usd(total))")
        if party > 1 { parts.append("\(usd(total / Double(party))) each (\(party) ways)") }
        return parts.joined(separator: " · ")
    }

    /// First $-prefixed amount in the text (commas stripped).
    private static func firstCurrencyAmount(in text: String) -> Double? {
        guard let value = firstRegexDouble(#"\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)"#, in: text, stripCommas: true) else { return nil }
        return value
    }

    /// Party size from "N ways/people", "between/among/by/for N", or "split … N".
    private static func partySize(in text: String) -> Int? {
        for pattern in [#"([0-9]+)\s*(?:ways|way|people|persons|guests|of us|of them)"#,
                        #"(?:between|among|by|for|split into|split it)\s+([0-9]+)"#] {
            if let value = firstRegexDouble(pattern, in: text) { return Int(value) }
        }
        return nil
    }

    /// First capture group of `pattern` in `text`, parsed as Double.
    private static func firstRegexDouble(_ pattern: String, in text: String, stripCommas: Bool = false) -> Double? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2, let r = Range(match.range(at: 1), in: text) else { return nil }
        let raw = stripCommas ? text[r].replacingOccurrences(of: ",", with: "") : String(text[r])
        return Double(raw)
    }

    /// Recognizes a calculation and returns the cleaned expression + formatted
    /// result. Requires a digit AND an operator/percent (literal or spelled) that
    /// MathEvaluator can actually evaluate — so "what is bitcoin" or "5 apples"
    /// never become math.
    static func parseMath(_ text: String, original: String) -> (expression: String, result: String)? {
        var expr = original
        let lower = original.lowercased()
        for lead in ["what's ", "whats ", "what is ", "calculate ", "compute ", "evaluate ", "how much is ", "solve "]
        where lower.hasPrefix(lead) {
            expr = String(original.dropFirst(lead.count))
            break
        }
        expr = expr.trimmingCharacters(in: CharacterSet(charactersIn: " ?=."))
        let low = expr.lowercased()
        let hasDigit = low.contains { $0.isNumber }
        let hasRealOperator = low.range(of: #"[-+*/×÷]"#, options: .regularExpression) != nil
            || ["plus", "minus", "times", "divided by", "multiplied by", " x "].contains { low.contains($0) }
        // A "%" only counts as math when it's part of an expression (with an
        // operator or "of"), so "i'm 50% sure" / a bare "50%" stay model questions.
        let hasPercentMath = low.contains("%") && (hasRealOperator || low.contains(" of "))
        guard hasDigit, hasRealOperator || hasPercentMath else { return nil }
        guard let value = MathEvaluator.evaluate(expr) else { return nil }
        return (expr.trimmingCharacters(in: .whitespaces), MathEvaluator.format(value))
    }

    /// "how many days until <holiday/date>" or "what's the date in N days/weeks/
    /// months/years". Returns a question + a ready-to-show answer, or nil. `now`
    /// is injectable for deterministic tests.
    static func parseDateMath(_ text: String, original: String, now: Date = Date()) -> (question: String, answer: String)? {
        // A) days until …
        let untilTriggers = ["how many days until ", "how many days till ", "how many days to ",
                             "days until ", "days till ", "how long until ", "how long till "]
        if let trigger = untilTriggers.first(where: { text.hasPrefix($0) }) {
            let restLower = String(text.dropFirst(trigger.count))
            let restOriginal = String(original.dropFirst(trigger.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ?.!"))
            var target: Date?
            for holiday in DateMath.holidays where holiday.names.contains(where: { restLower.contains($0) }) {
                target = DateMath.nextOccurrence(month: holiday.month, day: holiday.day, now: now)
                break
            }
            if target == nil { target = firstDate(in: restOriginal) }
            guard let date = target else { return nil }
            let days = DateMath.daysUntil(date, now: now)
            guard days >= 0 else { return nil }
            let label = restOriginal.isEmpty ? DateMath.longDate(date) : restOriginal
            let answer = days == 0
                ? "That’s today — \(DateMath.longDate(date))."
                : "**\(days)** day\(days == 1 ? "" : "s") until \(label) — \(DateMath.longDate(date))."
            return (original, answer)
        }
        // B) date in N units
        if contains(text, ["date in ", "what's the date", "whats the date", "what is the date",
                           "from now", "from today", "what day is it in", "what day will it be"]),
           let range = text.range(of: #"(\d+)\s*(day|days|week|weeks|month|months|year|years)"#, options: .regularExpression) {
            let token = String(text[range])
            guard let value = Int(token.prefix(while: { $0.isNumber })) else { return nil }
            let unit: Calendar.Component = token.contains("week") ? .weekOfYear
                : token.contains("month") ? .month
                : token.contains("year") ? .year : .day
            guard let future = DateMath.adding(value, unit, to: now) else { return nil }
            return (original, "That’ll be **\(DateMath.longDate(future))**.")
        }
        return nil
    }

    /// First absolute date NSDataDetector finds in a string (nil if none).
    private static func firstDate(in text: String) -> Date? {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.date
    }

    static func parseDefineWord(_ text: String) -> String? {
        // "what does X mean" — strict: only the bare definition form, so
        // "what does SOL mean for crypto?" stays a model question.
        if text.hasPrefix("what does ") {
            guard let range = text.range(of: #"^what does ([a-z][a-z-]+) means?[?.!]?$"#, options: .regularExpression) else {
                return nil
            }
            let word = text[range].dropFirst("what does ".count).split(separator: " ").first.map(String.init)
            return (word?.count ?? 0) >= 2 ? word : nil
        }
        let prefixes = ["what's the definition of ", "whats the definition of ", "what is the definition of ",
                        "definition of ", "define the word ", "define ", "meaning of "]
        for prefix in prefixes where text.hasPrefix(prefix) {
            var rest = String(text.dropFirst(prefix.count))
            for suffix in [" mean", " means", " defined", " definition"] where rest.hasSuffix(suffix) {
                rest = String(rest.dropLast(suffix.count))
            }
            rest = rest.replacingOccurrences(of: "[?.,!\"']", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            // The dictionary API is per-word; take the first token.
            guard let word = rest.split(separator: " ").first.map(String.init),
                  word.count >= 2, word.allSatisfy({ $0.isLetter || $0 == "-" }) else { return nil }
            return word
        }
        return nil
    }

    private static func extractSchedule(from text: String) -> BriefingSchedule {
        var hour = 8
        var minute = 0
        if contains(text, ["evening", "night", "9pm", "9 pm"]) { hour = 21 }
        if contains(text, ["noon", "midday"]) { hour = 12 }
        // explicit "8am", "7:30 am", "at 9 pm"
        if let r = text.range(of: #"(\d{1,2})(:(\d{2}))?\s*(am|pm)"#, options: .regularExpression) {
            let token = String(text[r])
            let digits = token.components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted).filter { !$0.isEmpty }
            if let h = digits.first.flatMap({ Int($0) }) {
                hour = h % 12
                if token.contains("pm") { hour += 12 }
                if token.contains("am") && h == 12 { hour = 0 }
            }
            if digits.count > 1, let m = Int(digits[1]) { minute = m }
        }
        if contains(text, ["weekday", "weekdays", "every weekday"]) {
            return .weekdays(hour: hour, minute: minute)
        }
        if contains(text, ["weekly", "every week", "every monday"]) {
            return .weekly(weekday: 2, hour: hour, minute: minute)
        }
        return .daily(hour: hour, minute: minute)
    }

    private static func contains(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func wordPresent(_ word: String, in text: String) -> Bool {
        if word.contains(" ") { return text.contains(word) }
        // whole-word match for short symbols like "eth"/"sol"
        let padded = " \(text.replacingOccurrences(of: "?", with: " ").replacingOccurrences(of: ",", with: " ")) "
        return padded.contains(" \(word) ") || padded.contains(" \(word)'") || text == word
    }
}

extension LiveDataService {
    /// Symbol for a CoinGecko id (for cryptoPrice briefings).
    static func symbol(forCoinID id: String) -> String {
        liveCoin(forID: id)?.symbol ?? id.uppercased()
    }
}

/// On-device arithmetic evaluator. Hand-rolled tokenizer + recursive-descent
/// parser (NOT NSExpression(format:), which throws uncatchable ObjC exceptions
/// on malformed input). Pure, deterministic, crash-proof: any unparseable input
/// returns nil. Handles + - * / and parentheses, spelled operators ("plus",
/// "times", "divided by"), ×/÷/x, and percentages ("18% of 85", "50%").
enum MathEvaluator {
    static func evaluate(_ raw: String) -> Double? {
        var s = raw.lowercased()
        s = s.replacingOccurrences(of: ",", with: "")            // 1,000 → 1000
        s = s.replacingOccurrences(of: "multiplied by", with: "*")
        s = s.replacingOccurrences(of: "divided by", with: "/")
        s = s.replacingOccurrences(of: "divide by", with: "/")
        s = s.replacingOccurrences(of: "plus", with: "+")
        s = s.replacingOccurrences(of: "minus", with: "-")
        s = s.replacingOccurrences(of: "times", with: "*")
        s = s.replacingOccurrences(of: "÷", with: "/")
        s = s.replacingOccurrences(of: "×", with: "*")
        // "x" as multiply, only between numbers/parens (so it can't eat words).
        s = s.replacingOccurrences(of: #"(?<=[0-9).])\s*x\s*(?=[0-9(.])"#, with: "*", options: .regularExpression)
        // "18% of 85" → "(18*0.01)*85"; then a standalone "50%" → "(50*0.01)".
        s = s.replacingOccurrences(of: #"([0-9.]+)\s*%\s*of\s+"#, with: "($1*0.01)*", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([0-9.]+)\s*%"#, with: "($1*0.01)", options: .regularExpression)

        guard let tokens = tokenize(s) else { return nil }
        var parser = RecursiveParser(tokens: tokens)
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    /// "84" for integers, trimmed decimals otherwise ("15.39", "0.6667").
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        var s = String(format: "%.4f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private enum Token: Equatable { case number(Double), plus, minus, mul, div, lParen, rParen }

    private static func tokenize(_ s: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == " " { i += 1; continue }
            switch c {
            case "+": tokens.append(.plus); i += 1
            case "-": tokens.append(.minus); i += 1
            case "*": tokens.append(.mul); i += 1
            case "/": tokens.append(.div); i += 1
            case "(": tokens.append(.lParen); i += 1
            case ")": tokens.append(.rParen); i += 1
            case "0"..."9", ".":
                var num = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    num.append(chars[i]); i += 1
                }
                guard let value = Double(num) else { return nil }
                tokens.append(.number(value))
            default:
                return nil // any non-math character rejects the whole input
            }
        }
        return tokens
    }

    /// expr := term (('+'|'-') term)*; term := factor (('*'|'/') factor)*;
    /// factor := number | '(' expr ')' | ('-'|'+') factor
    private struct RecursiveParser {
        let tokens: [Token]
        var index = 0
        var isAtEnd: Bool { index >= tokens.count }
        private func peek() -> Token? { index < tokens.count ? tokens[index] : nil }
        private mutating func advance() -> Token? { defer { index += 1 }; return peek() }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let op = peek(), op == .plus || op == .minus {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                value = (op == .plus) ? value + rhs : value - rhs
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while let op = peek(), op == .mul || op == .div {
                index += 1
                guard let rhs = parseFactor() else { return nil }
                value = (op == .mul) ? value * rhs : value / rhs
            }
            return value
        }

        private mutating func parseFactor() -> Double? {
            switch peek() {
            case .minus: index += 1; return parseFactor().map { -$0 }
            case .plus: index += 1; return parseFactor()
            case let .number(value): index += 1; return value
            case .lParen:
                index += 1
                guard let value = parseExpression(), peek() == .rParen else { return nil }
                index += 1
                return value
            default:
                return nil
            }
        }
    }
}

/// On-device date arithmetic — whole-day counts, future dates, and the next
/// occurrence of a fixed-date holiday. Pure + deterministic (every function
/// takes `now`), so it's fully unit-testable.
enum DateMath {
    /// Whole-day count from today to the target day (negative if already past).
    static func daysUntil(_ target: Date, now: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: target)).day ?? 0
    }

    static func adding(_ value: Int, _ unit: Calendar.Component, to now: Date) -> Date? {
        Calendar.current.date(byAdding: unit, value: value, to: now)
    }

    /// "Friday, December 25, 2026"
    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    /// The next occurrence (today or later) of a fixed month/day.
    static func nextOccurrence(month: Int, day: Int, now: Date) -> Date? {
        let cal = Calendar.current
        let year = cal.component(.year, from: now)
        var components = DateComponents()
        components.month = month
        components.day = day
        for candidateYear in [year, year + 1] {
            components.year = candidateYear
            if let date = cal.date(from: components),
               cal.startOfDay(for: date) >= cal.startOfDay(for: now) {
                return date
            }
        }
        return nil
    }

    /// Fixed-date holidays we can resolve by name (no movable feasts).
    static let holidays: [(names: [String], month: Int, day: Int)] = [
        (["new year's eve", "new years eve"], 12, 31),
        (["christmas eve"], 12, 24),
        (["christmas", "xmas"], 12, 25),
        (["new year", "new years", "new year's"], 1, 1),
        (["valentine's day", "valentines day", "valentine's", "valentines", "valentine"], 2, 14),
        (["halloween"], 10, 31),
        (["independence day", "fourth of july", "4th of july", "july 4th"], 7, 4),
    ]
}

/// On-device unit conversion (length / mass / temperature). Linear units carry
/// a factor to a base unit; temperature is handled by formula.
enum UnitConverter {
    private struct LinearUnit { let symbol: String; let category: String; let toBase: Double }

    private static let linear: [String: LinearUnit] = {
        var map: [String: LinearUnit] = [:]
        func add(_ aliases: [String], _ symbol: String, _ category: String, _ toBase: Double) {
            for alias in aliases { map[alias] = LinearUnit(symbol: symbol, category: category, toBase: toBase) }
        }
        // length (base: meter)
        add(["m", "meter", "meters", "metre", "metres"], "m", "length", 1)
        add(["km", "kilometer", "kilometers", "kilometre", "kilometres"], "km", "length", 1000)
        add(["cm", "centimeter", "centimeters"], "cm", "length", 0.01)
        add(["mm", "millimeter", "millimeters"], "mm", "length", 0.001)
        add(["mi", "mile", "miles"], "mi", "length", 1609.344)
        add(["ft", "foot", "feet"], "ft", "length", 0.3048)
        add(["yd", "yard", "yards"], "yd", "length", 0.9144)
        add(["in", "inch", "inches"], "in", "length", 0.0254)
        // mass (base: gram)
        add(["g", "gram", "grams"], "g", "mass", 1)
        add(["kg", "kilogram", "kilograms", "kilo", "kilos"], "kg", "mass", 1000)
        add(["mg", "milligram", "milligrams"], "mg", "mass", 0.001)
        add(["lb", "lbs", "pound", "pounds"], "lb", "mass", 453.59237)
        add(["oz", "ounce", "ounces"], "oz", "mass", 28.349523)
        add(["ton", "tonne", "tonnes", "tons"], "t", "mass", 1_000_000)
        return map
    }()

    private static func canonicalTemp(_ raw: String) -> String? {
        switch raw.replacingOccurrences(of: "°", with: "") {
        case "c", "celsius", "centigrade": return "°C"
        case "f", "fahrenheit": return "°F"
        case "k", "kelvin": return "K"
        default: return nil
        }
    }

    static func convert(value: Double, from: String, to: String) -> (result: Double, fromSymbol: String, toSymbol: String)? {
        let f = from.lowercased(), t = to.lowercased()
        if let cf = canonicalTemp(f), let ct = canonicalTemp(t) {
            return (convertTemperature(value, from: cf, to: ct), cf, ct)
        }
        let key = { (s: String) in s.replacingOccurrences(of: "°", with: "") }
        guard let fu = linear[key(f)], let tu = linear[key(t)], fu.category == tu.category else { return nil }
        return (value * fu.toBase / tu.toBase, fu.symbol, tu.symbol)
    }

    private static func convertTemperature(_ value: Double, from: String, to: String) -> Double {
        let celsius: Double
        switch from {
        case "°F": celsius = (value - 32) * 5 / 9
        case "K": celsius = value - 273.15
        default: celsius = value
        }
        switch to {
        case "°F": return celsius * 9 / 5 + 32
        case "K": return celsius + 273.15
        default: return celsius
        }
    }
}

enum LiveDataService {
    /// ETH price + 24h sparkline (CoinGecko) → chart widget.
    static func ethPriceWidget() async -> MessageWidget? {
        await cryptoPriceWidget(coinID: "ethereum", symbol: "ETH")
    }

    /// Raw USD spot price for any CoinGecko id — the deterministic value a
    /// conditional tracker evaluates its threshold against. nil on fetch failure.
    static func coinUSDPrice(coinID: String) async -> Double? {
        let id = coinID.lowercased()
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(id)&vs_currencies=usd") else {
            return nil
        }
        guard let data = try? await fetchData(from: url),
              let coin = (try? JSONDecoder().decode([String: CoinSimplePrice].self, from: data))?[id] else {
            return nil
        }
        return coin.usd
    }

    /// "$2,000" / "$1.95" — USD price label for alert copy.
    static func usdPriceString(_ value: Double) -> String {
        currencyFormatter(maximumFractionDigits: value < 10 ? 2 : 0).string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    /// Compact USD for big figures: "$2.34T", "$58.1B", "$420.0M".
    static func compactUSD(_ value: Double) -> String {
        let magnitude = Swift.abs(value)
        if magnitude >= 1e12 { return String(format: "$%.2fT", value / 1e12) }
        if magnitude >= 1e9 { return String(format: "$%.1fB", value / 1e9) }
        if magnitude >= 1e6 { return String(format: "$%.1fM", value / 1e6) }
        return usdPriceString(value)
    }

    /// Global crypto market overview (total cap, 24h change, BTC/ETH dominance)
    /// → comparison widget. Auth-free (`/global`).
    static func cryptoMarketWidget() async -> MessageWidget? {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/global") else { return nil }
        guard let data = try? await fetchData(from: url),
              let response = try? JSONDecoder().decode(CoinGeckoGlobalResponse.self, from: data),
              let totalUSD = response.data.totalMarketCap["usd"] else {
            return nil
        }
        let change = response.data.marketCapChangePercentage24HUsd ?? 0
        var rows: [WidgetComparisonRow] = [
            WidgetComparisonRow(label: "Total market cap", cells: [WidgetComparisonCell(text: compactUSD(totalUSD), tone: nil)]),
            WidgetComparisonRow(label: "24h change", cells: [WidgetComparisonCell(text: String(format: "%+.1f%%", change), tone: change >= 0 ? .good : .warn)])
        ]
        if let btc = response.data.marketCapPercentage["btc"] {
            rows.append(WidgetComparisonRow(label: "BTC dominance", cells: [WidgetComparisonCell(text: String(format: "%.1f%%", btc), tone: nil)]))
        }
        if let eth = response.data.marketCapPercentage["eth"] {
            rows.append(WidgetComparisonRow(label: "ETH dominance", cells: [WidgetComparisonCell(text: String(format: "%.1f%%", eth), tone: nil)]))
        }
        return MessageWidget(
            kind: .comparison,
            title: "Crypto market",
            freshness: .fresh,
            time: shortCurrentTimeString(),
            followUp: "What’s trending?",
            note: nil,
            chart: nil,
            metric: nil,
            comparison: WidgetComparison(subtitle: "Global overview", columns: ["Value"], rows: rows),
            newsBrief: nil
        )
    }

    /// Coins trending on CoinGecko right now → a comparison widget (coin ·
    /// symbol · market-cap rank). Auth-free (`/search/trending`).
    static func trendingCryptoWidget() async -> MessageWidget? {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/search/trending") else { return nil }
        guard let data = try? await fetchData(from: url),
              let response = try? JSONDecoder().decode(CoinGeckoTrendingResponse.self, from: data),
              !response.coins.isEmpty else {
            return nil
        }
        let rows = response.coins.prefix(7).map { wrapper -> WidgetComparisonRow in
            let coin = wrapper.item
            let rank = coin.marketCapRank.map { "#\($0)" } ?? "—"
            return WidgetComparisonRow(
                label: coin.name,
                cells: [
                    WidgetComparisonCell(text: coin.symbol.uppercased(), tone: nil),
                    WidgetComparisonCell(text: rank, tone: nil)
                ]
            )
        }
        return MessageWidget(
            kind: .comparison,
            title: "Trending on CoinGecko",
            freshness: .fresh,
            time: shortCurrentTimeString(),
            followUp: "Want a price on any of these?",
            note: nil,
            chart: nil,
            metric: nil,
            comparison: WidgetComparison(subtitle: "Trending now", columns: ["Symbol", "Rank"], rows: Array(rows)),
            newsBrief: nil
        )
    }

    /// Price + 24h sparkline for any CoinGecko coin id → chart widget.
    /// The sparkline is best-effort: CoinGecko rate-limits the heavier chart
    /// endpoint first, so if it fails we still surface the live price as a
    /// metric widget rather than failing the whole answer.
    static func cryptoPriceWidget(coinID: String, symbol: String) async -> MessageWidget? {
        let id = coinID.lowercased()
        guard let priceURL = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(id)&vs_currencies=usd&include_24hr_change=true") else {
            return nil
        }

        let decoder = JSONDecoder()
        guard let priceData = try? await fetchData(from: priceURL),
              let coin = (try? decoder.decode([String: CoinSimplePrice].self, from: priceData))?[id],
              let price = coin.usd, let change = coin.usd24HourChange else {
            return nil
        }

        let valueString = currencyFormatter(maximumFractionDigits: price < 10 ? 2 : 0)
            .string(from: NSNumber(value: price)) ?? "$\(price)"
        let deltaString = percentChangeFormatter().string(from: NSNumber(value: change / 100))
        let trend: WidgetTrend = change >= 0 ? .up : .down

        // Sparkline is best-effort; a rate-limited chart call still yields a price.
        var points: [Double] = []
        if let chartURL = URL(string: "https://api.coingecko.com/api/v3/coins/\(id)/market_chart?vs_currency=usd&days=1"),
           let chartData = try? await fetchData(from: chartURL),
           let chartResponse = try? decoder.decode(CoinGeckoMarketChartResponse.self, from: chartData) {
            points = downsample(chartResponse.prices.compactMap(\.price), targetCount: 30)
        }

        if !points.isEmpty {
            return MessageWidget(
                kind: .chart,
                title: "\(symbol) watcher",
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "Track \(symbol) price",
                note: nil,
                chart: WidgetChart(
                    label: "\(symbol) / USD",
                    value: valueString,
                    delta: deltaString,
                    trend: trend,
                    points: points,
                    caption: "past 24h",
                    timeframe: "24h"
                ),
                metric: nil,
                comparison: nil,
                newsBrief: nil
            )
        }

        // No sparkline available — still show the live price as a metric.
        return MessageWidget(
            kind: .metric,
            title: "\(symbol) price",
            freshness: .fresh,
            time: shortCurrentTimeString(),
            followUp: "Track \(symbol) price",
            note: nil,
            chart: nil,
            metric: WidgetMetric(
                label: "\(symbol) / USD",
                value: valueString,
                delta: deltaString,
                trend: trend,
                caption: "24h change"
            ),
            comparison: nil,
            newsBrief: nil
        )
    }

    /// NEAR account balance / holdings (NEAR RPC + FastNEAR) → metric widget.
    static func nearAccountWidget(account: String) async -> MessageWidget? {
        let accountID = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountID.isEmpty,
              let rpcURL = URL(string: "https://rpc.mainnet.near.org") else {
            return nil
        }

        do {
            var request = URLRequest(url: rpcURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(NEARAccountRPCRequest(accountID: accountID))

            let response = try JSONDecoder().decode(NEARAccountRPCResponse.self, from: try await fetchData(for: request))
            guard response.error == nil,
                  response.result?.error == nil,
                  let amount = response.result?.amount,
                  let balance = nearBalance(fromYoctoNEAR: amount) else {
                return accountNotFoundWidget(accountID: accountID)
            }

            async let holdings = fetchFastNEARHoldings(accountID: accountID)
            async let nearUSDPrice = fetchNEARUSDPrice()

            let caption = await nearCaption(balance: balance, holdings: holdings, usdPrice: nearUSDPrice)

            return MessageWidget(
                kind: .metric,
                title: accountID,
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "Show recent activity",
                note: nil,
                chart: nil,
                metric: WidgetMetric(
                    label: "NEAR balance",
                    value: nearBalanceFormatter().string(from: balance as NSDecimalNumber) ?? "\(balance) NEAR",
                    delta: nil,
                    trend: .flat,
                    caption: caption
                ),
                comparison: nil,
                newsBrief: nil
            )
        } catch {
            return nil
        }
    }

    /// Top headlines (public RSS) → news-brief widget.
    static func newsBriefWidget() async -> MessageWidget? {
        guard let url = URL(string: "https://feeds.bbci.co.uk/news/rss.xml") else {
            return nil
        }

        do {
            let parser = BBCNewsRSSParser()
            let items = parser.parse(data: try await fetchData(from: url)).prefix(4)
            guard !items.isEmpty else { return nil }

            let source = WidgetNewsSource(label: "B", color: "#990000", domain: "bbc.com")
            let stories = items.map { item in
                WidgetNewsStory(title: item.title, tag: nil, sources: [source], url: item.link)
            }

            return MessageWidget(
                kind: .newsBrief,
                title: "Daily news brief",
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "What's the biggest story?",
                note: nil,
                chart: nil,
                metric: nil,
                comparison: nil,
                newsBrief: WidgetNewsBrief(
                    heading: "Today · \(stories.count) stories",
                    stories: stories
                )
            )
        } catch {
            return nil
        }
    }

    /// Current conditions + today's high/low for a named place (open-meteo
    /// geocoding + forecast, both auth-free) → metric widget.
    static func weatherWidget(query: String) async -> MessageWidget? {
        let place = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty,
              let encoded = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let geoURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json") else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let geo = try decoder.decode(GeocodingResponse.self, from: try await fetchData(from: geoURL))
            guard let match = geo.results?.first else { return nil }

            guard let forecastURL = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(match.latitude)&longitude=\(match.longitude)&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&timezone=auto&forecast_days=1") else {
                return nil
            }
            let forecast = try decoder.decode(WeatherForecastResponse.self, from: try await fetchData(from: forecastURL))
            guard let temperature = forecast.current?.temperature2m else { return nil }

            let condition = weatherDescription(forCode: forecast.current?.weatherCode ?? -1)
            var captionParts = [condition]
            if let high = forecast.daily?.temperatureMax?.first, let low = forecast.daily?.temperatureMin?.first {
                captionParts.append("H \(Int(high.rounded()))° · L \(Int(low.rounded()))°")
            }
            let region = [match.admin1, match.country].compactMap { $0 }.first

            return MessageWidget(
                kind: .metric,
                title: match.name ?? place.capitalized,
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "What should I wear?",
                note: nil,
                chart: nil,
                metric: WidgetMetric(
                    label: region ?? "Weather",
                    value: "\(Int(temperature.rounded()))°F",
                    delta: nil,
                    trend: .flat,
                    caption: captionParts.joined(separator: " · ")
                ),
                comparison: nil,
                newsBrief: nil
            )
        } catch {
            return nil
        }
    }

    /// Human label for a WMO weather-interpretation code.
    static func weatherDescription(forCode code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67: return "Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm + hail"
        default: return "—"
        }
    }

    /// Current local time for a named place (open-meteo geocoding gives the
    /// IANA timezone; the time itself is computed on-device) → metric widget.
    static func worldTimeWidget(query: String) async -> MessageWidget? {
        let place = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty,
              let encoded = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let geoURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json") else {
            return nil
        }
        do {
            let geo = try JSONDecoder().decode(GeocodingResponse.self, from: try await fetchData(from: geoURL))
            guard let match = geo.results?.first,
                  let timeZoneID = match.timezone,
                  let timeZone = TimeZone(identifier: timeZoneID) else {
                return nil
            }
            let now = Date()
            let timeFormatter = DateFormatter()
            timeFormatter.timeZone = timeZone
            timeFormatter.dateFormat = "h:mm a"
            let dayFormatter = DateFormatter()
            dayFormatter.timeZone = timeZone
            dayFormatter.dateFormat = "EEEE"

            let offsetHours = Double(timeZone.secondsFromGMT(for: now)) / 3600
            let offsetString = String(format: "GMT%+g", offsetHours)
            let region = [match.admin1, match.country].compactMap { $0 }.first

            return MessageWidget(
                kind: .metric,
                title: match.name ?? place.capitalized,
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "Schedule something there?",
                note: nil,
                chart: nil,
                metric: WidgetMetric(
                    label: region ?? "Local time",
                    value: timeFormatter.string(from: now),
                    delta: nil,
                    trend: .flat,
                    caption: "\(dayFormatter.string(from: now)) · \(offsetString)"
                ),
                comparison: nil,
                newsBrief: nil
            )
        } catch {
            return nil
        }
    }

    /// Dictionary definition (dictionaryapi.dev, auth-free) → generic widget.
    static func defineWidget(word: String) async -> MessageWidget? {
        let term = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty,
              let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)") else {
            return nil
        }
        do {
            let entries = try JSONDecoder().decode([DictionaryEntry].self, from: try await fetchData(from: url))
            guard let meaning = entries.first?.meanings?.first,
                  let definition = meaning.definitions?.first?.definition, !definition.isEmpty else {
                return nil
            }
            let partOfSpeech = meaning.partOfSpeech.map { "\($0) · " } ?? ""
            return MessageWidget(
                kind: .generic,
                title: word.capitalized,
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "Use it in a sentence?",
                note: "\(partOfSpeech)\(definition)",
                chart: nil,
                metric: nil,
                comparison: nil,
                newsBrief: nil
            )
        } catch {
            return nil
        }
    }

    /// On-device unit conversion → metric widget (no network).
    static func unitConvertWidget(value: Double, from: String, to: String) async -> MessageWidget? {
        guard let converted = UnitConverter.convert(value: value, from: from, to: to) else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        let valueString = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        let resultString = formatter.string(from: NSNumber(value: converted.result)) ?? "\(converted.result)"
        return MessageWidget(
            kind: .metric,
            title: "\(converted.fromSymbol) → \(converted.toSymbol)",
            freshness: .fresh,
            time: shortCurrentTimeString(),
            followUp: nil,
            note: nil,
            chart: nil,
            metric: WidgetMetric(
                label: "\(valueString) \(converted.fromSymbol)",
                value: "\(resultString) \(converted.toSymbol)",
                delta: nil,
                trend: .flat,
                caption: nil
            ),
            comparison: nil,
            newsBrief: nil
        )
    }

    /// Currency conversion via frankfurter.app (ECB rates, auth-free) → metric.
    static func fxWidget(amount: Double, from: String, to: String) async -> MessageWidget? {
        let amountString = amount.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(amount))
            : String(format: "%.2f", amount)
        guard let url = URL(string: "https://api.frankfurter.app/latest?amount=\(amountString)&from=\(from)&to=\(to)") else {
            return nil
        }
        do {
            let response = try JSONDecoder().decode(FrankfurterResponse.self, from: try await fetchData(from: url))
            guard let converted = response.rates?[to] else { return nil }
            let rate = amount != 0 ? converted / amount : converted

            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            let convertedString = formatter.string(from: NSNumber(value: converted)) ?? String(format: "%.2f", converted)
            formatter.maximumFractionDigits = 4
            let rateString = formatter.string(from: NSNumber(value: rate)) ?? String(format: "%.4f", rate)

            return MessageWidget(
                kind: .metric,
                title: "\(from) → \(to)",
                freshness: .fresh,
                time: shortCurrentTimeString(),
                followUp: "Convert a different amount?",
                note: nil,
                chart: nil,
                metric: WidgetMetric(
                    label: "\(amountString) \(from)",
                    value: "\(convertedString) \(to)",
                    delta: nil,
                    trend: .flat,
                    caption: "1 \(from) = \(rateString) \(to)"
                ),
                comparison: nil,
                newsBrief: nil
            )
        } catch {
            return nil
        }
    }
}

private extension LiveDataService {
    struct CoinSimplePrice: Decodable {
        let usd: Double?
        let usd24HourChange: Double?

        enum CodingKeys: String, CodingKey {
            case usd
            case usd24HourChange = "usd_24h_change"
        }
    }

    struct CoinGeckoMarketChartResponse: Decodable {
        let prices: [CoinGeckoPricePoint]
    }

    struct CoinGeckoGlobalResponse: Decodable {
        let data: GlobalData

        struct GlobalData: Decodable {
            let totalMarketCap: [String: Double]
            let marketCapChangePercentage24HUsd: Double?
            let marketCapPercentage: [String: Double]

            enum CodingKeys: String, CodingKey {
                case totalMarketCap = "total_market_cap"
                case marketCapChangePercentage24HUsd = "market_cap_change_percentage_24h_usd"
                case marketCapPercentage = "market_cap_percentage"
            }
        }
    }

    struct CoinGeckoTrendingResponse: Decodable {
        let coins: [TrendingWrapper]

        struct TrendingWrapper: Decodable { let item: TrendingCoin }

        struct TrendingCoin: Decodable {
            let name: String
            let symbol: String
            let marketCapRank: Int?

            enum CodingKeys: String, CodingKey {
                case name, symbol
                case marketCapRank = "market_cap_rank"
            }
        }
    }

    struct GeocodingResponse: Decodable {
        let results: [GeocodingPlace]?
    }

    struct GeocodingPlace: Decodable {
        let name: String?
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?
        let timezone: String?
    }

    struct WeatherForecastResponse: Decodable {
        let current: WeatherCurrent?
        let daily: WeatherDaily?
    }

    struct WeatherCurrent: Decodable {
        let temperature2m: Double?
        let weatherCode: Int?

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }

    struct WeatherDaily: Decodable {
        let temperatureMax: [Double]?
        let temperatureMin: [Double]?

        enum CodingKeys: String, CodingKey {
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
        }
    }

    struct FrankfurterResponse: Decodable {
        let amount: Double?
        let base: String?
        let rates: [String: Double]?
    }

    struct DictionaryEntry: Decodable {
        let word: String?
        let meanings: [DictionaryMeaning]?
    }

    struct DictionaryMeaning: Decodable {
        let partOfSpeech: String?
        let definitions: [DictionaryDefinition]?
    }

    struct DictionaryDefinition: Decodable {
        let definition: String?
    }

    struct CoinGeckoPricePoint: Decodable {
        let price: Double?

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            _ = try? container.decode(Double.self)
            price = try? container.decode(Double.self)
        }
    }

    struct NEARAccountRPCRequest: Encodable {
        let jsonrpc = "2.0"
        let id = "1"
        let method = "query"
        let params: Params

        init(accountID: String) {
            params = Params(accountID: accountID)
        }

        enum CodingKeys: String, CodingKey {
            case jsonrpc, id, method, params
        }

        struct Params: Encodable {
            let requestType = "view_account"
            let finality = "final"
            let accountID: String

            enum CodingKeys: String, CodingKey {
                case requestType = "request_type"
                case finality
                case accountID = "account_id"
            }
        }
    }

    struct NEARAccountRPCResponse: Decodable {
        let result: NEARAccountResult?
        let error: NEARRPCError?
    }

    struct NEARAccountResult: Decodable {
        let amount: String?
        let storageUsage: Int?
        let error: NEARRPCError?

        enum CodingKeys: String, CodingKey {
            case amount
            case storageUsage = "storage_usage"
            case error
        }
    }

    struct NEARRPCError: Decodable {
        let message: String?
    }

    struct FastNEARAccountResponse: Decodable {
        let tokens: [FastNEARToken]?
        let nfts: [FastNEARNFT]?
    }

    struct FastNEARToken: Decodable {}

    struct FastNEARNFT: Decodable {}

    struct NEARPriceResponse: Decodable {
        let near: NEARPrice
    }

    struct NEARPrice: Decodable {
        let usd: Double?
    }

    struct FastNEARHoldings {
        let tokenCount: Int
        let nftCount: Int
    }

    static func fetchData(from url: URL) async throws -> Data {
        try await fetchData(for: URLRequest(url: url))
    }

    static func fetchData(for request: URLRequest) async throws -> Data {
        // Clamp every live fetch to a short timeout so a stalled endpoint can't
        // tie up a manual or background briefing run.
        var timedRequest = request
        timedRequest.timeoutInterval = min(timedRequest.timeoutInterval, 12)
        let (data, response) = try await URLSession.shared.data(for: timedRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    static func downsample(_ values: [Double], targetCount: Int) -> [Double] {
        guard values.count > targetCount, targetCount > 1 else {
            return values
        }

        let maxIndex = values.count - 1
        let denominator = targetCount - 1
        var points: [Double] = []
        points.reserveCapacity(targetCount)

        for index in 0..<targetCount {
            let sourceIndex = (index * maxIndex + denominator / 2) / denominator
            points.append(values[sourceIndex])
        }

        return points
    }

    static func nearBalance(fromYoctoNEAR amount: String) -> Decimal? {
        guard let yocto = Decimal(string: amount),
              let divisor = Decimal(string: "1000000000000000000000000") else {
            return nil
        }
        return yocto / divisor
    }

    static func fetchFastNEARHoldings(accountID: String) async -> FastNEARHoldings? {
        guard let encodedAccount = accountID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.fastnear.com/v1/account/\(encodedAccount)/full") else {
            return nil
        }

        do {
            let response = try JSONDecoder().decode(FastNEARAccountResponse.self, from: try await fetchData(from: url))
            return FastNEARHoldings(
                tokenCount: response.tokens?.count ?? 0,
                nftCount: response.nfts?.count ?? 0
            )
        } catch {
            return nil
        }
    }

    static func fetchNEARUSDPrice() async -> Double? {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=near&vs_currencies=usd") else {
            return nil
        }

        do {
            return try JSONDecoder().decode(NEARPriceResponse.self, from: try await fetchData(from: url)).near.usd
        } catch {
            return nil
        }
    }

    static func nearCaption(balance: Decimal, holdings: FastNEARHoldings?, usdPrice: Double?) -> String? {
        var parts: [String] = []

        if let usdPrice {
            let balanceNumber = balance as NSDecimalNumber
            let usdValue = balanceNumber.doubleValue * usdPrice
            if let formattedUSD = currencyFormatter(maximumFractionDigits: 2).string(from: NSNumber(value: usdValue)) {
                parts.append(formattedUSD)
            }
        }

        if let holdings {
            parts.append("\(holdings.tokenCount) tokens · \(holdings.nftCount) NFTs")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func accountNotFoundWidget(accountID: String) -> MessageWidget {
        MessageWidget(
            kind: .generic,
            title: accountID,
            freshness: .fresh,
            time: shortCurrentTimeString(),
            followUp: nil,
            note: "Account \(accountID) wasn’t found on NEAR mainnet.",
            chart: nil,
            metric: nil,
            comparison: nil,
            newsBrief: nil
        )
    }

    static func currencyFormatter(maximumFractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 0
        return formatter
    }

    static func nearBalanceFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 2
        formatter.positiveSuffix = " NEAR"
        formatter.negativeSuffix = " NEAR"
        return formatter
    }

    static func percentChangeFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        formatter.plusSign = "+"
        formatter.minusSign = "−"
        formatter.positivePrefix = "+"
        return formatter
    }

    static func shortCurrentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Date())
    }
}

private final class BBCNewsRSSParser: NSObject, XMLParserDelegate {
    private(set) var items: [Item] = []

    private var isInsideItem = false
    private var currentElement: String?
    private var currentTitle = ""
    private var currentLink = ""

    struct Item {
        let title: String
        let link: String
    }

    func parse(data: Data) -> [Item] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse() ? items : []
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        if name == "item" {
            isInsideItem = true
            currentTitle = ""
            currentLink = ""
        }
        currentElement = isInsideItem ? name : nil
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if name == "item" {
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !link.isEmpty {
                items.append(Item(title: title, link: link))
            }
            isInsideItem = false
            currentElement = nil
            return
        }

        if currentElement == name {
            currentElement = nil
        }
    }

    private func append(_ string: String) {
        guard isInsideItem else { return }
        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        default:
            break
        }
    }
}

// MARK: - On-device personal memory

/// How a fact entered memory. `.explicit` = the user told us to remember it
/// ("remember I prefer X"); `.inferred` = we distilled it passively from what
/// they said. Inferred facts are held to a higher confidence bar and labelled
/// for the user so the distinction is never hidden.
enum MemorySource: String, Codable {
    case explicit
    case inferred
}

struct MemoryItem: Codable, Hashable, Identifiable {
    var id: UUID
    var text: String
    var createdAt: Date
    var source: MemorySource

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), source: MemorySource = .explicit) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.source = source
    }

    private enum CodingKeys: String, CodingKey { case id, text, createdAt, source }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        // Back-compat: facts saved before sources existed are treated as
        // explicit (the only kind that existed then).
        source = try c.decodeIfPresent(MemorySource.self, forKey: .source) ?? .explicit
    }
}

/// Privacy-first personal memory: user-taught facts/preferences persisted on
/// device (account-scoped), injected into the model's system prompt so answers
/// are personalized. Nothing leaves the device except as private-inference
/// context the user already trusts.
final class MemoryStore {
    private(set) var items: [MemoryItem] = []
    private var fileURL: URL?

    init(fileURL: URL? = nil) {
        if let fileURL { configure(fileURL: fileURL) }
    }

    func configure(accountID: String?) {
        configure(fileURL: Self.defaultFileURL(accountID: accountID))
    }

    func configure(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    /// Stores a fact (de-duped, newest first, capped). Returns nil if too short.
    /// When a fact already exists, an explicit "remember this" upgrades a
    /// previously-inferred entry (the user just confirmed it) but an inferred
    /// re-derivation never downgrades an explicit one.
    @discardableResult
    func add(_ text: String, source: MemorySource = .explicit) -> MemoryItem? {
        // Clamp a single fact so one huge entry can't dominate the prompt.
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
        guard trimmed.count >= 3 else { return nil }
        if let idx = items.firstIndex(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            if source == .explicit && items[idx].source == .inferred {
                items[idx].source = .explicit
                save()
            }
            return items[idx]
        }
        let item = MemoryItem(text: trimmed, source: source)
        items.insert(item, at: 0)
        if items.count > 200 { items = Array(items.prefix(200)) }
        save()
        return item
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    /// Removes facts matching a phrase (either contains the other,
    /// case-insensitive). Returns how many were removed.
    @discardableResult
    func remove(matching query: String) -> Int {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return 0 }
        let before = items.count
        items.removeAll { item in
            let text = item.text.lowercased()
            return text.contains(needle) || needle.contains(text)
        }
        let removed = before - items.count
        if removed > 0 { save() }
        return removed
    }

    func clear() {
        items.removeAll()
        save()
    }

    /// Drops only passively-learned (.inferred) facts, keeping everything the
    /// user explicitly asked us to remember. Returns how many were removed.
    @discardableResult
    func removeInferred() -> Int {
        let before = items.count
        items.removeAll { $0.source == .inferred }
        let removed = before - items.count
        if removed > 0 { save() }
        return removed
    }

    /// A system-prompt block of the most recent facts within a character
    /// budget, or nil when empty — keeps memory from blowing up the prompt.
    func contextBlock(limit: Int = 12, budget: Int = 1500) -> String? {
        guard !items.isEmpty else { return nil }
        var remaining = budget
        var lines: [String] = []
        for item in items.prefix(limit) {
            let line = "- \(item.text)"
            guard line.count <= remaining else { break }
            remaining -= line.count
            lines.append(line)
        }
        guard !lines.isEmpty else { return nil }
        return "What you know about the user (apply when relevant; never recite this list verbatim):\n" + lines.joined(separator: "\n")
    }

    private static func defaultFileURL(accountID: String?) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        // Hash the FULL id so distinct accounts can't collide on a sanitized
        // form (e.g. "alice.near" vs "alicenear").
        let scope = stableScope(accountID ?? "default")
        return base
            .appendingPathComponent("NEARPrivateChat", isDirectory: true)
            .appendingPathComponent("memory-\(scope).json")
    }

    /// Deterministic, collision-safe filename scope from an account id.
    static func stableScope(_ raw: String) -> String {
        var hash: UInt64 = 5381
        for byte in raw.utf8 { hash = (hash &* 33) ^ UInt64(byte) }
        return String(hash, radix: 16)
    }
}

struct AgentActivityRecord: Codable, Hashable, Identifiable {
    var id: UUID
    var summary: String
    var date: Date

    init(id: UUID = UUID(), summary: String, date: Date = Date()) {
        self.id = id
        self.summary = summary
        self.date = date
    }
}

/// A transparency log of what the assistant did on the user's behalf —
/// scheduled briefing runs, tracker creation, etc. On-device, account-scoped.
final class AgentActivityLog {
    private(set) var entries: [AgentActivityRecord] = []
    private var fileURL: URL?

    init(fileURL: URL? = nil) {
        if let fileURL { configure(fileURL: fileURL) }
    }

    func configure(accountID: String?) {
        configure(fileURL: Self.defaultFileURL(accountID: accountID))
    }

    func configure(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([AgentActivityRecord].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    func record(_ summary: String) {
        let trimmed = String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !trimmed.isEmpty else { return }
        entries.insert(AgentActivityRecord(summary: trimmed), at: 0)
        if entries.count > 200 { entries = Array(entries.prefix(200)) }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private static func defaultFileURL(accountID: String?) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("NEARPrivateChat", isDirectory: true)
            .appendingPathComponent("activity-\(MemoryStore.stableScope(accountID ?? "default")).json")
    }
}
