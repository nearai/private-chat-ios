import Foundation

extension JSONEncoder {
    static var briefing: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var briefing: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

func briefingSort(_ lhs: Briefing, _ rhs: Briefing) -> Bool {
    if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
    if lhs.isPaused != rhs.isPaused { return !lhs.isPaused }
    let now = Date()
    let lhsNext = lhs.schedule.nextRun(after: lhs.lastRunAt ?? now) ?? .distantFuture
    let rhsNext = rhs.schedule.nextRun(after: rhs.lastRunAt ?? now) ?? .distantFuture
    if lhsNext != rhsNext { return lhsNext < rhsNext }
    return lhs.createdAt > rhs.createdAt
}

func relativeNextRun(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}

var briefingTimeFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateFormat = "h:mma"
    formatter.amSymbol = "AM"
    formatter.pmSymbol = "PM"
    return formatter
}

func clampedHour(_ hour: Int) -> Int {
    min(max(hour, 0), 23)
}

func clampedMinute(_ minute: Int) -> Int {
    min(max(minute, 0), 59)
}

func clampedWeekday(_ weekday: Int) -> Int {
    min(max(weekday, 1), 7)
}

enum BriefingPresentationText {
    static func displayTitle(_ rawTitle: String) -> String {
        let collapsed = rawTitle
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t?.!,"))
        guard !collapsed.isEmpty else { return "Briefing" }
        return removingDanglingTail(from: collapsed)
    }

    static func conciseAboutText(for briefing: Briefing) -> String {
        let prompt = briefing.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            return "Runs on schedule and saves each answer here."
        }

        if let subject = firstCapture(
            in: prompt,
            pattern: #"(?i)^using web search,\s*find the latest\s+(.+?)\s+and report it concisely\."#
        ) {
            return "Tracks the latest \(cleanedTrackedSubject(subject)). Uses current sources and saves each run here."
        }

        if let topic = firstCapture(
            in: prompt,
            pattern: #"(?i)^using web search,\s*give me the latest news on\s+(.+?):"#
        ) {
            return "Briefs you on the latest \(topic) news with current sources."
        }

        if let task = firstCapture(
            in: prompt,
            pattern: #"(?i)^run this recurring task:\s+(.+?)\.\s+use web search"#
        ) {
            return "Runs \(task). Uses current sources when needed and saves each answer here."
        }

        return strippingInternalPromptInstructions(prompt)
    }

    static func wordBoundaryTitle(_ rawTitle: String, maxCharacters: Int = 48) -> String {
        let title = displayTitle(rawTitle)
        guard title.count > maxCharacters else { return title }
        let end = title.index(title.startIndex, offsetBy: maxCharacters)
        let rawClip = String(title[..<end])
        let endedAtBoundary = rawClip.last.map { character in
            character.isWhitespace || character.unicodeScalars.first.map { CharacterSet(charactersIn: "?.!,").contains($0) } == true
        } == true
        var clipped = rawClip
            .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t?.!,"))
        if !clipped.isEmpty, endedAtBoundary {
            return removingDanglingTail(from: clipped)
        }
        if let lastSpace = clipped.lastIndex(where: { $0 == " " || $0 == "," }),
           clipped.distance(from: clipped.startIndex, to: lastSpace) >= 12 {
            clipped = String(clipped[..<lastSpace])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t?.!,"))
        }
        return removingDanglingTail(from: clipped)
    }

    private static func strippingInternalPromptInstructions(_ prompt: String) -> String {
        var text = prompt
        let instructionPatterns = [
            #"(?i)\s*Lead with the current number/price.*?(?=\.|$)\.?"#,
            #"(?i)\s*If it's a price or numeric value, present it as a metric or chart widget\.?"#,
            #"(?i)\s*Return a concise update with what changed.*$"#
        ]
        for pattern in instructionPatterns {
            text = text.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression]
            )
        }
        text = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t"))
        return text.isEmpty ? "Runs on schedule and saves each answer here." : text
    }

    private static func removingDanglingTail(from value: String) -> String {
        var cleaned = value
        let danglingPatterns = [
            #",\s*(and\s+)?la(?:u(?:n(?:c(?:h)?)?)?)?$"#,
            #"\s+(and|or|with|for|to)$"#
        ]
        for pattern in danglingPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t?.!,"))
    }

    private static func cleanedTrackedSubject(_ subject: String) -> String {
        subject
            .replacingOccurrences(
                of: #"\s+with\s+(?:current|fresh|live)\s+sources$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t?.!,"))
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let capture = String(text[range])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t?.!,"))
        return capture.isEmpty ? nil : capture
    }
}
