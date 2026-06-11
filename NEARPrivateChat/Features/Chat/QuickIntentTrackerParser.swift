import Foundation

extension QuickIntentParser {
    static func makeTracker(from text: String, original: String) -> TrackerSpec? {
        // `council` is recorded for a future scheduled-council runner; today the
        // briefing runner fetches live data, so we don't promise it in the label.
        let council = contains(text, ["council", "panel", "multiple models", "models debate", "debate"])
        let schedule = extractSchedule(from: text)
        let label = schedule.scheduleLabel
        let account = extractAccount(from: text)
        let mentionsAccount = isNearAccountTrackerRequest(text) || account != nil

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
        // A request that explicitly asks for a "briefing/digest/report/summary"
        // — even if it mentions "news" — is honored by the general briefing
        // branch below, which keeps the user's own phrasing as a web-grounded
        // prompt (e.g. "create a global politics briefing that pulls from top
        // politics news"). Only PLAIN news feeds are handled here.
        let asksForBriefingDoc = contains(text, [
            "briefing", "digest", "report", "rundown", "recap", "roundup",
            "round-up", "summary", "summarize", "summarise"
        ])
        if contains(text, ["news", "headlines", "stories"]), !asksForBriefingDoc {
            // Topic-less ("daily news", "headlines every morning") → generic
            // multi-source feed. A short, clean topic ("global politics news
            // every morning") → a web-grounded recurring briefing on that
            // topic, so the user gets real coverage — not a generic dump.
            if isBareNewsRequest(text) {
                return TrackerSpec(title: "Daily news", kind: .dailyNews, subject: nil, schedule: schedule, council: false, confirmation: "Daily news · \(label)")
            }
            let topic = newsTopic(from: original)
            let topicWords = topic.split(separator: " ").map(String.init)
            // Token-based (not substring) so legitimate topics aren't rejected by
            // an accidental match — e.g. "sand mining" must not trip on "and".
            let commandNoise: Set<String> = [
                "create", "make", "build", "set", "setup", "pull", "pulls",
                "surface", "surfaces", "please", "tracker", "briefing", "every",
                "each", "that", "which", "and"
            ]
            let topicIsClean = topic.count >= 2 && (1...5).contains(topicWords.count)
                && Set(topicWords).isDisjoint(with: commandNoise)
            if topicIsClean {
                let display = prettyTrackerTitle(from: topic)
                let title = display.prefix(1).uppercased() + display.dropFirst()
                return TrackerSpec(
                    title: "\(title) news",
                    kind: .customPrompt,
                    subject: nil,
                    schedule: schedule,
                    council: council,
                    confirmation: "\(council ? "Council news" : "News") · \(title) · \(label)",
                    prompt: "Using web search, give me the latest news on \(topic): the top 3–5 developments from the last day or two, each as a one-line headline with its source. Lead with the single most important update. Be concise."
                )
            }
            return TrackerSpec(title: "Daily news", kind: .dailyNews, subject: nil, schedule: schedule, council: false, confirmation: "Daily news · \(label)")
        }
        let infoCue = contains(text, ["price", "value", "cost", "worth", "quote", "rate", "index", "stock",
                                      "score", "level", "status", "forecast", "floor price", "market cap",
                                      "how much", "trading at"])
        if startsWithWatchCommand(text), infoCue, hasUnresolvedAssetListSubject(text),
           let generic = makeOpenEndedInfoTracker(from: original, text: text, schedule: schedule, council: council, label: label) {
            return generic
        }
        if let serialized = parseWatchlistAssets(text) {
            let count = serialized.split(separator: "|").count
            return TrackerSpec(
                title: "Watchlist",
                kind: .watchlist,
                subject: serialized,
                schedule: schedule,
                council: false,
                confirmation: "Watchlist · \(count) assets · \(label)"
            )
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
        if let stock = parseStock(text, original: original) {
            let title = stock.company.isEmpty ? stock.symbol : stock.company
            return TrackerSpec(
                title: "\(title) stock",
                kind: .stockPrice,
                subject: stock.symbol,
                schedule: schedule,
                council: false,
                confirmation: "\(stock.symbol) · \(label)"
            )
        }
        // Open-ended "track/watch the price/value of <X>" for ANY subject we
        // don't have a built-in feed for (a watch, a stock, a collectible…).
        // Becomes a web-grounded recurring custom-prompt tracker — the agentic-OS
        // case: "track the price of a Rolex GMT Master II every morning".
        if startsWithWatchCommand(text) && infoCue {
            return makeOpenEndedInfoTracker(from: original, text: text, schedule: schedule, council: council, label: label)
        }

        if let generic = genericScheduledTaskSubject(from: text, original: original) {
            let title = prettyTrackerTitle(from: generic)
            return TrackerSpec(
                title: title,
                kind: .customPrompt,
                subject: nil,
                schedule: schedule,
                council: council,
                confirmation: "Tracking \(title) · \(label)",
                prompt: "Run this recurring task: \(generic). Use web search when fresh facts are needed, include dates/sources when relevant, and lead with what changed or what needs attention."
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

    static func makeOpenEndedInfoTracker(
        from original: String,
        text: String,
        schedule: BriefingSchedule,
        council: Bool,
        label: String
    ) -> TrackerSpec? {
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

    /// The subject of an open-ended tracker: the cleaned prompt with leading
    /// watch verbs and articles stripped. "track the price of a Rolex GMT Master
    /// II every morning" → "price of a Rolex GMT Master II".
    static func trackerSubject(from text: String) -> String {
        var subject = cleanedTrackerPrompt(from: text)
        let leadVerbs = [
            "keep an eye on ", "keep tabs on ", "keep track of ", "track ",
            "watch for ", "watch ", "monitor ", "follow ", "check on ", "check ",
            "research ", "scan for ", "scan ", "look up ", "look for ",
            "find ", "investigate ", "run "
        ]
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

    static func hasUnresolvedAssetListSubject(_ text: String) -> Bool {
        guard contains(text, ["watchlist", "watch list", " and ", ",", " vs ", " versus ", " plus ", " with "]) else {
            return false
        }
        let subject = trackerSubject(from: text)
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}$]+"#, with: " ", options: .regularExpression)
        let noise: Set<String> = [
            "a", "an", "the", "my", "me", "please", "for", "of", "to", "from",
            "what", "whats", "what's", "is", "are", "and", "or", "vs", "versus", "plus", "with", "every", "each",
            "daily", "weekly", "monthly", "morning", "evening", "night", "nightly",
            "weekday", "weekdays", "week", "weeks", "month", "months", "day", "days",
            "at", "am", "pm", "price", "prices", "value", "values", "cost",
            "costs", "worth", "quote", "quotes", "rate", "rates", "index",
            "watchlist", "watch", "list", "stock", "stocks", "share", "shares", "ticker", "tickers", "crypto",
            "coin", "coins", "token", "tokens", "market", "cap", "floor",
            "trading", "protocol", "network", "asset", "assets"
        ]

        for token in subject.split(separator: " ").map(String.init) where token.count >= 2 {
            let stripped = token.trimmingCharacters(in: CharacterSet(charactersIn: "$"))
            if stripped.isEmpty || Double(stripped) != nil || noise.contains(stripped) {
                continue
            }
            if matchedCoin(in: stripped) != nil || resolveStockToken(stripped) != nil {
                continue
            }
            return true
        }
        return false
    }

    static func hasMixedKnownUnknownValueAsk(_ text: String) -> Bool {
        let valueCue = contains(text, [
            "price", "prices", "value", "values", "cost", "costs", "worth",
            "quote", "quotes", "rate", "rates", "market cap", "floor price"
        ])
        guard valueCue,
              contains(text, [" and ", ",", " vs ", " versus ", " plus ", " with "]),
              hasUnresolvedAssetListSubject(text) else {
            return false
        }
        return matchedCoin(in: text) != nil || parseWatchlistAssets(text) != nil
    }

    static func isNearAccountTrackerRequest(_ text: String) -> Bool {
        contains(text, ["near account", "near wallet", "near.com account", "account balance", "wallet balance"])
    }

    static func shouldPreviewInsteadOfCreate(_ text: String) -> Bool {
        contains(text, [
            "only if", "if there is", "if there's", "if it finds", "if you find",
            "make a tracker if", "create a tracker if", "add a tracker if",
            "otherwise list", "preview before creating", "preview before you create"
        ])
    }

    static func hasUnsupportedRecurringCadence(_ text: String) -> Bool {
        if text.range(of: #"\bevery\s+\d+\s*(min|mins|minute|minutes)\b"#, options: .regularExpression) != nil {
            return true
        }
        return contains(text, [
            "twice daily", "twice a day", "twice per day",
            "twice weekly", "twice a week", "twice per week",
            "twice monthly", "twice a month", "twice per month",
            "quarterly", "every quarter", "yearly", "annually",
            "semiweekly", "semi-weekly"
        ])
    }

    static func genericScheduledTaskSubject(from text: String, original: String) -> String? {
        guard hasExplicitCadence(text) || contains(text, ["tracker", "watcher", "cron", "recurring", "scheduled task"]) else {
            return nil
        }
        let subject = trackerSubject(from: original)
        guard subject.count >= 3 else { return nil }
        let lower = subject.lowercased()
        if lower.hasPrefix("remind me ") || lower.hasPrefix("reminder ") { return nil }
        if contains(lower, ["this video", "this movie", "tv tonight", "watch tonight"]) { return nil }
        return subject
    }

    static func makeRecurringReminderTracker(from text: String, original: String) -> TrackerSpec? {
        let triggers = [
            "remind me to ", "remind me about ", "remind me ",
            "set a reminder to ", "set a reminder for ", "set a reminder ",
            "reminder to "
        ]
        guard let trigger = triggers.first(where: { text.hasPrefix($0) }),
              hasRecurringCadence(text) else {
            return nil
        }
        let hasClockTime = text.range(of: #"\b\d{1,2}(:\d{2})?\s*(am|pm)\b"#, options: .regularExpression) != nil ||
            contains(text, ["at noon", "at midnight", "noon", "midday"])
        guard hasClockTime else {
            return nil
        }

        var task = String(original.dropFirst(trigger.count))
        let schedulePhrases = [
            "every weekday morning", "every weekday", "each weekday", "every morning",
            "each morning", "every single day", "every day", "each day", "every evening",
            "every night", "every week", "weekly", "daily", "weekdays", "weekday",
            "hourly", "nightly", "at noon", "at midnight", "noon", "midday",
            "every sunday", "every monday", "every tuesday", "every wednesday",
            "every thursday", "every friday", "every saturday", "each sunday",
            "each monday", "each tuesday", "each wednesday", "each thursday",
            "each friday", "each saturday"
        ]
        for phrase in schedulePhrases {
            task = task.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive)
        }
        for phrase in ["no web", "without web", "no browsing", "no internet", "offline only"] {
            task = task.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive)
        }
        task = task.replacingOccurrences(of: #"\bevery\s+\d+\s*(h|hr|hrs|hour|hours|min|mins|minutes)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        task = task.replacingOccurrences(of: #"\b(at\s+)?\d{1,2}(:\d{2})?\s*(am|pm)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        task = task.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ?.!,"))
        guard task.count >= 2 else { return nil }

        let schedule = extractSchedule(from: text)
        let title = prettyTrackerTitle(from: task)
        return TrackerSpec(
            title: title,
            kind: .customPrompt,
            subject: nil,
            schedule: schedule,
            council: false,
            confirmation: "Recurring reminder · \(title) · \(schedule.scheduleLabel)",
            prompt: "Recurring reminder: \(task). When this tracker runs, return a short notification-ready reminder, any relevant caveat, and whether the cadence still makes sense."
        )
    }

    /// Big-cap tickers ↔ company names. `ambiguous` marks names that are common
    /// English words ("apple", "meta", "visa"), which only resolve with an
    /// explicit stock cue so we don't hijack "apple pie" or "meta question".
}
