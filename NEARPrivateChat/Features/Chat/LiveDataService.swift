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
    case nearAccount(account: String?)
    case news
    case weather(query: String)
    case worldTime(query: String)
    case fx(amount: Double, from: String, to: String)
    case unitConvert(value: Double, from: String, to: String)
    case define(word: String)
    case remember(text: String)
    case recallMemory
    case forget(text: String?)
    case createTracker(TrackerSpec)
}

struct TrackerSpec: Equatable {
    var title: String
    var kind: BriefingKind
    var subject: String?            // coin id (price) or account (nearAccount)
    var schedule: BriefingSchedule
    var council: Bool
    var confirmation: String
    var prompt: String?             // cleaned prompt for customPrompt council trackers
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
        if contains(text, ["forget everything", "forget it all", "forget all", "clear your memory", "clear my memory", "delete your memory", "wipe your memory", "erase your memory"]) {
            return .forget(text: nil)
        }
        if let toForget = parseForget(text, original: trimmedRaw) {
            return .forget(text: toForget)
        }
        if let fact = parseRemember(text, original: trimmedRaw) {
            return .remember(text: fact)
        }

        // 1) "create a tracker / watch / every morning …" — only when the
        // prompt names a subject we can actually track. Otherwise fall through
        // so "remind me to stretch daily" goes to the model, not an ETH tracker.
        let createVerb = contains(text, ["create", "make", "set up", "set-up", "setup", "build", "schedule", "start", "add", "track", "watch", "remind"])
        let trackerNoun = contains(text, ["tracker", "watcher", "alert", "briefing", "brief", "digest", "every day", "every morning", "each morning", "each day", "every weekday", "daily", "weekly"])
        if createVerb && trackerNoun, let spec = makeTracker(from: text) {
            return .createTracker(spec)
        }

        // 2) news
        if contains(text, ["news", "headlines", "what's happening", "whats happening", "top stories", "current events"]) {
            return .news
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

        return nil
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

    /// Read-only data lookups can be chained; actions (trackers, memory writes)
    /// cannot, so they never get swept into a compound run.
    private static func isCompoundable(_ intent: QuickIntent) -> Bool {
        switch intent {
        case .price, .nearAccount, .news, .weather, .worldTime, .fx, .unitConvert, .define:
            return true
        case .remember, .recallMemory, .forget, .createTracker:
            return false
        }
    }

    /// Builds a tracker only when a real subject is present. Returns nil for
    /// generic "remind me …" prompts and account trackers with no id so the
    /// caller can fall through to the model instead of scheduling a dead fetch.
    private static func makeTracker(from text: String) -> TrackerSpec? {
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
        // No live-data subject. A recurring briefing/digest (or a council
        // request) becomes a scheduled custom-prompt task on the user's actual
        // question — run on schedule by a single model, or the council if asked.
        // A bare reminder with no informational noun falls through to the model
        // so we don't manufacture trackers from "remind me to stretch".
        let wantsBriefing = council || contains(text, [
            "briefing", "brief", "digest", "summary", "summarize", "summarise",
            "report", "rundown", "recap", "roundup", "round-up"
        ])
        guard wantsBriefing else { return nil }
        let prompt = cleanedTrackerPrompt(from: text)
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

    static func parseForget(_ text: String, original: String) -> String? {
        let triggers = ["forget that ", "forget about ", "forget the ", "forget my ", "forget "]
        for trigger in triggers where text.hasPrefix(trigger) {
            let dropCount = trigger == "forget my " ? "forget ".count : trigger.count
            let fact = String(original.dropFirst(dropCount)).trimmingCharacters(in: .whitespacesAndNewlines)
            return fact.count >= 2 ? fact : nil
        }
        return nil
    }

    static func parseDefineWord(_ text: String) -> String? {
        let prefixes = ["what's the definition of ", "whats the definition of ", "what is the definition of ",
                        "definition of ", "define the word ", "define ", "meaning of ", "what does "]
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
                followUp: "Why is it moving?",
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
            followUp: "Why is it moving?",
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

struct MemoryItem: Codable, Hashable, Identifiable {
    var id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
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
    @discardableResult
    func add(_ text: String) -> MemoryItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }
        if let existing = items.first(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let item = MemoryItem(text: trimmed)
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

    /// A system-prompt block of the most recent facts, or nil when empty.
    func contextBlock(limit: Int = 12) -> String? {
        guard !items.isEmpty else { return nil }
        let lines = items.prefix(limit).map { "- \($0.text)" }.joined(separator: "\n")
        return "What you know about the user (apply when relevant; never recite this list verbatim):\n\(lines)"
    }

    private static func defaultFileURL(accountID: String?) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let raw = accountID ?? "default"
        let scope = String(raw.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        return base
            .appendingPathComponent("NEARPrivateChat", isDirectory: true)
            .appendingPathComponent("memory-\(scope.isEmpty ? "default" : scope).json")
    }
}
