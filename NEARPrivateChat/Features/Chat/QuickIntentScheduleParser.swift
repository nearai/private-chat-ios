import Foundation

extension QuickIntentParser {
    static func schedule(from text: String) -> BriefingSchedule {
        extractSchedule(from: text.lowercased())
    }

    static func extractSchedule(from text: String) -> BriefingSchedule {
        var hour = 8
        var minute = 0
        if contains(text, ["hourly", "every hour"]) {
            return .everyNHours(1)
        }
        if let r = text.range(of: #"\bevery\s+(\d+)\s*(h|hr|hrs|hour|hours)\b"#, options: .regularExpression) {
            let token = String(text[r])
            let digits = token.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            if let interval = digits.first.flatMap(Int.init) {
                return .everyNHours(max(1, interval))
            }
        }
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
        if contains(text, ["weekday", "weekdays", "every weekday", "business day", "business days"]) {
            return .weekdays(hour: hour, minute: minute)
        }
        if contains(text, ["biweekly", "bi-weekly", "every other week"]) {
            let weekday = mentionedWeekday(in: text)?.value ?? 2
            return .biweekly(weekday: weekday, hour: hour, minute: minute)
        }
        if contains(text, ["monthly", "every month", "once a month"]) {
            return .monthly(day: mentionedMonthDay(in: text) ?? 1, hour: hour, minute: minute)
        }
        if let weekday = mentionedWeekday(in: text),
           contains(text, ["every", "each", "weekly", "on \(weekday.name)"]) {
            return .weekly(weekday: weekday.value, hour: hour, minute: minute)
        }
        if contains(text, ["weekly", "every week"]) {
            return .weekly(weekday: 2, hour: hour, minute: minute)
        }
        return .daily(hour: hour, minute: minute)
    }

    static func mentionedWeekday(in text: String) -> (name: String, value: Int)? {
        let weekdays: [(String, Int)] = [
            ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
            ("thursday", 5), ("friday", 6), ("saturday", 7)
        ]
        return weekdays.first { wordPresent($0.0, in: text) }
    }

    static func mentionedMonthDay(in text: String) -> Int? {
        let patterns = [
            #"\b(?:day|on day)\s+(\d{1,2})\b"#,
            #"\b(\d{1,2})(st|nd|rd|th)\b"#,
            #"\bon the\s+(\d{1,2})\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text),
                  let value = Int(text[range]) else {
                continue
            }
            return min(31, max(1, value))
        }
        return nil
    }

    static func contains(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    static func wordPresent(_ word: String, in text: String) -> Bool {
        if word.contains(" ") { return text.contains(word) }
        // whole-word match for short symbols like "eth"/"sol". Treat "$" as a
        // separator too, so a cashtag ("$eth price") still matches the coin.
        let padded = " \(text.replacingOccurrences(of: "?", with: " ").replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "$", with: " ")) "
        return padded.contains(" \(word) ") || padded.contains(" \(word)'") || text == word
    }
}
