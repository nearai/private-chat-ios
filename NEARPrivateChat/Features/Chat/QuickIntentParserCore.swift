import Foundation

extension QuickIntentParser {
    /// Exact (punctuation-stripped) phrases that surface the capabilities card.
    static let capabilityPhrases: Set<String> = [
        "help", "what can you do", "what can i ask", "what can i ask you",
        "what can you help me with", "what are you capable of", "what are your features",
        "what features do you have", "show me what you can do", "what can this app do",
        "what can this do", "what else can you do", "how do you work", "what do you do"
    ]

    static func normalizedCommandText(_ text: String) -> String {
        var normalized = text
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ?.!"))
        if normalized.hasPrefix("please ") {
            normalized = String(normalized.dropFirst("please ".count))
        }
        return normalized
    }

    static func isQuestionLike(_ text: String) -> Bool {
        let normalized = normalizedCommandText(text)
        if text.contains("?") { return true }
        return [
            "can i ", "could i ", "should i ", "do i ", "do we ",
            "should we ", "is it ", "are we ", "what happens if ",
            "why ", "how do i ", "how should i "
        ].contains { normalized.hasPrefix($0) }
    }

    static func isActivityLogRequest(_ text: String) -> Bool {
        let normalized = normalizedCommandText(text)
        return [
            "what have you done", "what have you done recently",
            "what did you do", "show your activity", "activity log",
            "what have you been up to", "show what you've done",
            "show what youve done", "your recent activity"
        ].contains(normalized)
    }

    static func isListTrackersRequest(_ text: String) -> Bool {
        let normalized = normalizedCommandText(text)
        return [
            "what are you tracking", "show my trackers", "list my trackers",
            "show my alerts", "list my alerts", "what alerts do i have",
            "what are my trackers", "my active trackers", "show my briefings",
            "list my briefings", "my trackers and alerts"
        ].contains(normalized)
    }

    static func documentPrivacyCommand(_ text: String) -> Bool? {
        guard !isQuestionLike(text) else { return nil }
        let normalized = normalizedCommandText(text)
        let onDevicePrefixes = [
            "keep documents on device", "keep my documents on device",
            "keep files on device", "keep documents private",
            "keep my documents private", "don't upload my documents",
            "dont upload my documents", "don't upload documents",
            "dont upload documents", "private documents on",
            "process documents on device", "keep my docs on device",
            "private document mode"
        ]
        if onDevicePrefixes.contains(where: { normalized == $0 || normalized.hasPrefix($0 + " ") }) {
            return true
        }
        let offDevicePrefixes = [
            "upload documents normally", "documents off device",
            "turn off private documents", "stop keeping documents on device",
            "private documents off", "upload my documents"
        ]
        if offDevicePrefixes.contains(where: { normalized == $0 || normalized.hasPrefix($0 + " ") }) {
            return false
        }
        return nil
    }

    static func isClearAllMemoryCommand(_ text: String) -> Bool {
        let normalized = normalizedCommandText(text)
        return [
            "forget everything", "forget it all", "forget all",
            "clear your memory", "clear my memory", "delete your memory",
            "wipe your memory", "erase your memory"
        ].contains(normalized)
    }

    static func requestsWorldTime(_ text: String) -> Bool {
        if contains(text, [
            "what time is it", "current time", "local time", "time in ",
            "time at ", "time for ", "clock in ", "clock at ", "clock for "
        ]) {
            return true
        }
        let simplePlaceTimePattern = #"^[a-z][a-z .'-]{1,40}\s+(time|clock)\??$"#
        return text.range(of: simplePlaceTimePattern, options: .regularExpression) != nil
    }

    static func looksLikeNonWeatherForecast(_ text: String) -> Bool {
        guard text.contains("forecast"),
              !contains(text, ["weather", "temperature"]) else {
            return false
        }
        if knownStocks.contains(where: { stock in
            wordPresent(stock.symbol.lowercased(), in: text) ||
                stock.names.contains { wordPresent($0, in: text) }
        }) {
            return true
        }
        return contains(text, [
            "revenue", "earnings", "sales", "growth", "demand", "roadmap",
            "backlog", "sprint", "launch", "product", "pricing", "retention",
            "churn", "adoption", "runway", "burn", "pipeline", "strategy",
            "market", "marketing", "users", "customers", "conversion"
        ])
    }

    static func blocksLiveNetwork(_ text: String) -> Bool {
        let normalized = " " + text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) + " "
        let looseNormalized = " " + text
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) + " "
        let phrases = [
            "no web", "without web", "no browsing", "do not browse", "don't browse",
            "do not search the web", "don't search the web", "no internet",
            "offline only", "do not use web", "don't use web"
        ]
        return phrases.contains { phrase in
            let loosePhrase = phrase
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.contains(" \(phrase) ") ||
                (!loosePhrase.isEmpty && looseNormalized.contains(" \(loosePhrase) "))
        }
    }

    /// A concise tour of what the assistant can do, with copy-pasteable example
    /// prompts. Static + deterministic so it's testable and reusable.
    static func capabilitiesText() -> String {
        """
        Here’s what this app can do:

        **Chat about anything** — sign in for the general assistant:
        • “Write a concise client follow-up email”
        • “Summarize this PDF and pull out next actions”
        • “Debug this Swift error” · “Compare these options”
        • “Research this topic and make a decision brief”

        **Model-routed live questions** — use the assistant for current, contextual answers:
        • “Weather in Tokyo” · “What time is it in London?”
        • “Convert 100 USD to EUR” · “5 miles in km” · “Define serendipity”
        • “Top headlines” · “What’s the ETH price?” · “How’s my account, alice.near?”

        **Automations & alerts** — I can stage recurring checks and surface approved results:
        • “Check this topic every morning” — I’ll draft the workflow before creating anything
        • Ask something, then say “track that” to start a recurring check
        • “Remind me to review the grant draft every Friday”
        • “Brief me” — one digest of your active automations and approved results
        • “What are you tracking?” to review them

        **Math & dates** — ask naturally in chat:
        • “What’s 18% of 85.50?” · “12 * 7 + 3”
        • “How many days until Christmas?” · “What’s the date in 2 weeks?”

        **Reminders & recall**:
        • “Remind me to call mom at 5pm tomorrow” — I’ll notify you, even if the app’s closed
        • “Search my chats for the Lisbon trip” · “What did I say about my budget?”

        **Memory (private, on this device)**:
        • “Remember I prefer concise answers” · “What do you remember?”
        • I also quietly note durable details you mention — say “stop learning about me” to turn that off, or “forget what you learned automatically.”

        **Hands-free**: tap the mic to dictate, or ask Siri to run your briefings.

        Just type what you want. If it is an answer request, I route it through chat; if it is an explicit app command, I handle the local state change directly.
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
        // Split the ORIGINAL-case text (separators are lowercase but user input
        // typically is too) so a segment like "AAPL price" keeps the caps the
        // ticker parser needs — parse() lowercases internally anyway.
        var segments = [raw]
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
    static func isCompoundable(_ intent: QuickIntent) -> Bool {
        switch intent {
        case .price, .stock, .trendingCrypto, .cryptoMarket, .nearAccount, .news, .weather, .worldTime, .fx, .unitConvert, .define:
            return true
        case .watchlist, .briefMe, .math, .dateMath, .tipSplit, .remember, .recallMemory, .forget, .forgetAutoLearned, .setMemoryCapture, .setDocumentPrivacy, .activityLog, .listTrackers, .capabilities, .searchHistory, .createReminder, .createTracker, .requestNearAccountTracker, .trackLast:
            return false
        }
    }

    /// Builds a tracker only when a real subject is present. Returns nil for
    /// generic "remind me …" prompts and account trackers with no id so the
    /// caller can fall through to the model instead of scheduling a dead fetch.
}
