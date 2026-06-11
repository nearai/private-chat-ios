import Foundation

extension QuickIntentParser {
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
        guard hasConcreteReminderTime(original.lowercased()) else { return nil }

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

    static func hasConcreteReminderTime(_ text: String) -> Bool {
        text.range(of: #"\b\d{1,2}(:\d{2})?\s*(am|pm)\b"#, options: .regularExpression) != nil ||
            text.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil ||
            text.range(of: #"t\d{2}:\d{2}"#, options: .regularExpression) != nil ||
            text.range(of: #"\b(noon|midday|midnight)\b"#, options: .regularExpression) != nil
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
}
