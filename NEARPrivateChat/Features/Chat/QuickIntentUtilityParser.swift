import Foundation

extension QuickIntentParser {
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
    static func firstCurrencyAmount(in text: String) -> Double? {
        guard let value = firstRegexDouble(#"\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)"#, in: text, stripCommas: true) else { return nil }
        return value
    }

    /// Party size from "N ways/people", "between/among/by/for N", or "split … N".
    static func partySize(in text: String) -> Int? {
        for pattern in [#"([0-9]+)\s*(?:ways|way|people|persons|guests|of us|of them)"#,
                        #"(?:between|among|by|for|split into|split it)\s+([0-9]+)"#] {
            if let value = firstRegexDouble(pattern, in: text) { return Int(value) }
        }
        return nil
    }

    /// First capture group of `pattern` in `text`, parsed as Double.
    static func firstRegexDouble(_ pattern: String, in text: String, stripCommas: Bool = false) -> Double? {
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
    static func firstDate(in text: String) -> Date? {
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
            // The dictionary API is per-word. Only a SINGLE-word target is a
            // definition lookup — "define success for me as a founder" and
            // "meaning of machine learning" carry extra words the card would
            // silently discard, so they fall through to the model instead.
            let tokens = rest.split(separator: " ")
            guard tokens.count == 1,
                  let word = tokens.first.map(String.init),
                  word.count >= 2, word.allSatisfy({ $0.isLetter || $0 == "-" }) else { return nil }
            return word
        }
        return nil
    }
}
