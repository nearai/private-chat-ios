import Foundation

enum WidgetSystemActionKind: String, Equatable {
    case calendarEvent
    case reminder

    var label: String {
        switch self {
        case .calendarEvent:
            return "Calendar Event"
        case .reminder:
            return "Reminder"
        }
    }
}

struct WidgetSystemActionDraft: Equatable {
    var kind: WidgetSystemActionKind
    var title: String
    var startDate: Date
    var endDate: Date?
    var notes: String?
    var location: String?
    var recurrence: String?
    var timezone: String?
    var attendees: [String] = []
}

enum WidgetAppActionKind: String, Equatable {
    case tracker

    var label: String {
        switch self {
        case .tracker:
            return "Tracker"
        }
    }
}

struct WidgetAppActionDraft: Equatable {
    var kind: WidgetAppActionKind
    var title: String
    var prompt: String
    var schedule: BriefingSchedule
    var source: String?
    var command: String?
    var missingFields: [String] = []

    var isReady: Bool { missingFields.isEmpty }
    var confirmation: String { "\(title) · \(schedule.scheduleLabel)" }
}

extension WidgetActionItem {
    var systemActionKind: WidgetSystemActionKind? {
        let normalized = (type ?? "").lowercased()
        if normalized.contains("calendar") || normalized.contains("invite") || normalized.contains("event") {
            return .calendarEvent
        }
        if normalized.contains("reminder") || normalized.contains("remind") {
            return .reminder
        }
        let commandText = (command ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if commandText.hasPrefix("remind me") ||
            commandText.hasPrefix("set a reminder") ||
            commandText.hasPrefix("reminder to") {
            return .reminder
        }
        if commandText.contains("add to calendar") ||
            commandText.contains("calendar invite") ||
            commandText.contains("create a calendar") ||
            commandText.contains("schedule a meeting") {
            return .calendarEvent
        }
        return nil
    }

    func systemActionDraft(now: Date = Date(), calendar: Calendar = .current) -> WidgetSystemActionDraft? {
        guard let kind = systemActionKind else { return nil }
        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        var parsingCalendar = calendar
        if let timeZone = Self.actionTimeZone(from: timezone) {
            parsingCalendar.timeZone = timeZone
        }
        let parsedDate = Self.parsedActionDate(
            date: date,
            time: time,
            schedule: schedule,
            command: command,
            now: now,
            calendar: parsingCalendar
        )
        guard let startDate = parsedDate else { return nil }
        guard Self.hasConcreteTime(date: date, time: time, schedule: schedule, command: command) else {
            return nil
        }
        if kind == .calendarEvent, !Self.hasConcreteDate(date: date, time: time, schedule: schedule, command: command) {
            return nil
        }

        let durationSeconds = Self.durationSeconds(from: duration) ?? 30 * 60
        let endDate = kind == .calendarEvent ? startDate.addingTimeInterval(durationSeconds) : nil
        return WidgetSystemActionDraft(
            kind: kind,
            title: title,
            startDate: startDate,
            endDate: endDate,
            notes: Self.notes(for: self),
            location: widgetActionNonBlank(location),
            recurrence: widgetActionNonBlank(recurrence),
            timezone: widgetActionNonBlank(timezone),
            attendees: attendees
        )
    }

    private static func parsedActionDate(
        date: String?,
        time: String?,
        schedule: String?,
        command: String?,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let pieces = [
            [date, time].compactMap { widgetActionNonBlank($0) }.joined(separator: " "),
            schedule,
            command
        ]
        .compactMap { widgetActionNonBlank($0) }

        for piece in pieces {
            if let parsed = parsedExplicitDate(piece, now: now, calendar: calendar) {
                return parsed
            }
        }
        return nil
    }

    private static func actionTimeZone(from rawValue: String?) -> TimeZone? {
        guard let value = widgetActionNonBlank(rawValue) else { return nil }
        return TimeZone(identifier: value) ?? TimeZone(abbreviation: value)
    }

    private static func parsedExplicitDate(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: text), date > now {
            return date
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: text), date > now {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        for format in ["yyyy-MM-dd h:mm a", "yyyy-MM-dd HH:mm", "yyyy/MM/dd h:mm a", "yyyy/MM/dd HH:mm", "MMM d yyyy h:mm a", "MMMM d yyyy h:mm a"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date > now ? date : nil
            }
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        guard let date = matches.compactMap(\.date).first else { return nil }
        if date > now {
            return date
        }
        if containsAbsoluteDate(text) {
            return nil
        }
        return nextFutureDate(from: date, now: now, calendar: calendar)
    }

    private static func containsAbsoluteDate(_ text: String) -> Bool {
        text.range(of: #"\b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b"#, options: .regularExpression) != nil ||
            text.range(of: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:,?\s+\d{4})?\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func nextFutureDate(from date: Date, now: Date, calendar: Calendar) -> Date? {
        var candidate = date
        for _ in 0..<370 where candidate <= now {
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = next
        }
        return candidate > now ? candidate : nil
    }

    private static func hasConcreteDate(date: String?, time: String?, schedule: String?, command: String?) -> Bool {
        [date, time, schedule, command]
            .compactMap { widgetActionNonBlank($0)?.lowercased() }
            .contains { value in
                value.range(of: #"\b(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#, options: .regularExpression) != nil ||
                    value.range(of: #"\b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b"#, options: .regularExpression) != nil ||
                    value.range(of: #"\b\d{4}-\d{2}-\d{2}t\d{2}:\d{2}"#, options: .regularExpression) != nil ||
                    value.range(of: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2}\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            }
    }

    private static func hasConcreteTime(date: String?, time: String?, schedule: String?, command: String?) -> Bool {
        [date, time, schedule, command]
            .compactMap { widgetActionNonBlank($0)?.lowercased() }
            .contains { value in
                value.range(of: #"\b\d{1,2}(:\d{2})?\s*(am|pm)\b"#, options: .regularExpression) != nil ||
                    value.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil ||
                    value.range(of: #"t\d{2}:\d{2}"#, options: .regularExpression) != nil ||
                    value.range(of: #"\b(noon|midday|midnight)\b"#, options: .regularExpression) != nil
            }
    }

    private static func durationSeconds(from rawValue: String?) -> TimeInterval? {
        guard let rawValue = widgetActionNonBlank(rawValue)?.lowercased() else { return nil }
        let pattern = #"(\d+(?:\.\d+)?)\s*(minutes?|mins?|m|hours?|hrs?|h)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: rawValue, range: NSRange(rawValue.startIndex..<rawValue.endIndex, in: rawValue)),
              match.numberOfRanges >= 3,
              let amountRange = Range(match.range(at: 1), in: rawValue),
              let unitRange = Range(match.range(at: 2), in: rawValue),
              let amount = Double(rawValue[amountRange]) else {
            return nil
        }
        let unit = rawValue[unitRange]
        return unit.hasPrefix("h") ? amount * 3_600 : amount * 60
    }

    private static func notes(for action: WidgetActionItem) -> String? {
        let value = [
            widgetActionNonBlank(action.detail),
            widgetActionNonBlank(action.source).map { "Source: \($0)" },
            widgetActionNonBlank(action.timezone).map { "Timezone: \($0)" },
            action.attendees.isEmpty ? nil : "Attendees: \(action.attendees.joined(separator: ", "))",
            widgetActionNonBlank(action.command).map { "Command: \($0)" },
            action.missingFields.isEmpty ? nil : "Missing fields: \(action.missingFields.joined(separator: ", "))"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

extension WidgetActionItem {
    var appActionKind: WidgetAppActionKind? {
        let normalized = (type ?? "").lowercased()
        if normalized.contains("tracker") ||
            normalized.contains("watcher") ||
            normalized.contains("watch") ||
            normalized.contains("briefing") ||
            normalized.contains("brief") ||
            normalized.contains("digest") ||
            normalized.contains("cron") ||
            normalized.contains("recurring") ||
            normalized.contains("scheduled") ||
            normalized.contains("workflow") ||
            normalized.contains("automation") {
            return .tracker
        }
        if systemActionKind == nil {
            let scheduleText = [
                recurrence,
                schedule,
                time,
                command
            ]
                .compactMap { widgetActionNonBlank($0) }
                .joined(separator: " ")
            if Self.hasTrackerCadence(scheduleText) {
                return .tracker
            }
        }
        return nil
    }

    func appActionDraft() -> WidgetAppActionDraft? {
        guard appActionKind == .tracker else { return nil }
        let title = Self.trackerTitle(from: self)
        guard !title.isEmpty else { return nil }

        let scheduleText = [
            recurrence,
            schedule,
            time,
            command
        ]
            .compactMap { widgetActionNonBlank($0) }
            .joined(separator: " ")

        var missing = missingFields
        if !Self.hasTrackerCadence(scheduleText) &&
            !missing.contains(where: { $0.localizedCaseInsensitiveContains("schedule") || $0.localizedCaseInsensitiveContains("recurrence") }) {
            missing.append("recurrence")
        }

        let schedule = QuickIntentParser.schedule(from: scheduleText)
        return WidgetAppActionDraft(
            kind: .tracker,
            title: title,
            prompt: Self.trackerPrompt(for: self, title: title, schedule: schedule),
            schedule: schedule,
            source: widgetActionNonBlank(source),
            command: widgetActionNonBlank(command),
            missingFields: missing.uniquedNonEmpty()
        )
    }

    private static func trackerTitle(from action: WidgetActionItem) -> String {
        let explicit = widgetActionNonBlank(action.title)
        let subject = widgetActionNonBlank(action.command)
            .map { QuickIntentParser.cleanedTrackerPrompt(from: $0) }
            .flatMap(widgetActionNonBlank)
        let title = explicit ?? subject.map(QuickIntentParser.prettyTrackerTitle(from:)) ?? "Tracker"
        return String(title.prefix(64)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trackerPrompt(for action: WidgetActionItem, title: String, schedule: BriefingSchedule) -> String {
        let commandSubject = widgetActionNonBlank(action.command)
            .map { QuickIntentParser.cleanedTrackerPrompt(from: $0) }
            .flatMap(widgetActionNonBlank)
        let task = commandSubject
            ?? widgetActionNonBlank(action.detail)
            ?? widgetActionNonBlank(action.title)
            ?? title

        var lines = [
            "Run this recurring tracker: \(task)",
            "",
            "Schedule: \(schedule.scheduleLabel).",
            "Return a concise update with what changed, why it matters, any calendar-worthy or tracker-worthy follow-ups, and the next useful action."
        ]
        if let source = widgetActionNonBlank(action.source) {
            lines.append("Source: \(source).")
        }
        if let schedule = widgetActionNonBlank(action.schedule) {
            lines.append("Original schedule cue: \(schedule).")
        }
        if let recurrence = widgetActionNonBlank(action.recurrence) {
            lines.append("Original recurrence cue: \(recurrence).")
        }
        if let time = widgetActionNonBlank(action.time) {
            lines.append("Original time cue: \(time).")
        }
        if !action.missingFields.isEmpty {
            lines.append("Known missing details: \(action.missingFields.joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }

    private static func hasTrackerCadence(_ text: String) -> Bool {
        let normalized = " \(text.lowercased()) "
        if normalized.range(of: #"\b\d{1,2}(:\d{2})?\s*(am|pm)\b"#, options: .regularExpression) != nil { return true }
        if normalized.range(of: #"\bevery\s+\d+\s*(h|hr|hrs|hour|hours|min|mins|minutes)\b"#, options: .regularExpression) != nil { return true }
        let cues = [
            " daily ", " weekday ", " weekdays ", " weekly ", " biweekly ",
            " bi-weekly ", " monthly ", " hourly ",
            " every day ", " every morning ", " every evening ", " every night ",
            " every week ", " every other week ", " every month ", " once a month ",
            " every weekday ", " every hour ", " each day ",
            " each morning ", " nightly ", " morning ", " evening ", " noon "
        ]
        return cues.contains { normalized.contains($0) }
    }
}

private extension Array where Element == String {
    func uniquedNonEmpty() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in self {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }
}

private func widgetActionNonBlank(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

struct WidgetActionPlan: Codable, Hashable {
    var heading: String? = nil
    var summary: String? = nil
    var actions: [WidgetActionItem] = []
}

extension WidgetActionPlan {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            heading: try? c.decode(String.self, forKey: .heading),
            summary: try? c.decode(String.self, forKey: .summary),
            actions: (try? c.decode([WidgetActionItem].self, forKey: .actions)) ?? []
        )
    }
}

struct MessageWidget: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var kind: WidgetKind = .generic
    var title: String? = nil       // meta-strip source label "ETH watcher · threshold alert"
    var freshness: WidgetFreshness? = nil
    var time: String? = nil        // "8:02am", "1h ago"
    var followUp: String? = nil    // micro-composer placeholder, "Why is it dropping?"
    var note: String? = nil        // generic body / fallback prose
    var chart: WidgetChart? = nil
    var metric: WidgetMetric? = nil
    var comparison: WidgetComparison? = nil
    var newsBrief: WidgetNewsBrief? = nil
    var actionPlan: WidgetActionPlan? = nil

    enum CodingKeys: String, CodingKey {
        case id, kind, title, freshness, time
        case followUp = "follow_up"
        case note, chart, metric, comparison
        case newsBrief = "news_brief"
        case actionPlan = "action_plan"
    }
}

extension MessageWidget {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let chart = try? c.decode(WidgetChart.self, forKey: .chart)
        let metric = try? c.decode(WidgetMetric.self, forKey: .metric)
        let comparison = try? c.decode(WidgetComparison.self, forKey: .comparison)
        let news = try? c.decode(WidgetNewsBrief.self, forKey: .newsBrief)
        let actionPlan = try? c.decode(WidgetActionPlan.self, forKey: .actionPlan)

        var kind = (try? c.decode(WidgetKind.self, forKey: .kind)) ?? .generic
        if kind == .generic {
            if chart != nil { kind = .chart }
            else if metric != nil { kind = .metric }
            else if comparison != nil { kind = .comparison }
            else if news != nil { kind = .newsBrief }
            else if actionPlan != nil { kind = .actionPlan }
        }

        self.init(
            id: (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString,
            kind: kind,
            title: try? c.decode(String.self, forKey: .title),
            freshness: try? c.decode(WidgetFreshness.self, forKey: .freshness),
            time: try? c.decode(String.self, forKey: .time),
            followUp: try? c.decode(String.self, forKey: .followUp),
            note: try? c.decode(String.self, forKey: .note),
            chart: chart,
            metric: metric,
            comparison: comparison,
            newsBrief: news,
            actionPlan: actionPlan
        )
    }

    /// True when the payload carries something renderable for its kind.
    var hasRenderableBody: Bool {
        switch kind {
        case .chart: return chart != nil
        case .metric: return metric != nil
        case .comparison: return (comparison?.rows.isEmpty == false)
        case .newsBrief: return (newsBrief?.stories.isEmpty == false)
        case .actionPlan: return (actionPlan?.actions.isEmpty == false)
        case .generic: return (note?.isEmpty == false)
        }
    }

    private static let fenceTokens = ["```near-widget", "```near_widget", "```widget"]

    /// Scans assistant text for the first valid fenced near-widget JSON block.
    /// Returns the parsed widget (or nil) and the text with that block removed.
    /// On any parse failure the original text is returned untouched, so a
    /// malformed block degrades to visible prose rather than being lost.
    /// Earliest fenced opener (any alias) at or after `from`.
    private static func nextFenceOpener(in text: String, from: String.Index) -> (tokenStart: String.Index, tokenEnd: String.Index)? {
        var best: (start: String.Index, end: String.Index)?
        for token in fenceTokens {
            if let r = text.range(of: token, options: .caseInsensitive, range: from..<text.endIndex) {
                if best == nil || r.lowerBound < best!.start {
                    best = (r.lowerBound, r.upperBound)
                }
            }
        }
        return best.map { ($0.start, $0.end) }
    }

    static func extract(from text: String) -> (widget: MessageWidget?, cleanedText: String) {
        var searchStart = text.startIndex
        while let opener = nextFenceOpener(in: text, from: searchStart) {
            guard let closeRange = text.range(of: "```", range: opener.tokenEnd..<text.endIndex) else {
                break // unclosed fence — nothing parseable beyond here
            }
            var jsonString = text[opener.tokenEnd..<closeRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Drop a leading info-string line (e.g. ```near-widget json) before the JSON body.
            if let firstChar = jsonString.first, firstChar != "{", firstChar != "[",
               let newline = jsonString.firstIndex(of: "\n") {
                jsonString = String(jsonString[jsonString.index(after: newline)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let data = jsonString.data(using: .utf8),
               let widget = try? JSONDecoder().decode(MessageWidget.self, from: data),
               widget.hasRenderableBody {
                var cleaned = text
                cleaned.removeSubrange(opener.tokenStart..<closeRange.upperBound)
                return (widget, cleaned.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            searchStart = closeRange.upperBound // skip this block, keep scanning for a valid one
        }
        return (nil, text)
    }

    /// During streaming, hide an as-yet-unclosed near-widget fence so the user
    /// never sees raw JSON mid-stream.
    static func strippedStreamingPreview(_ text: String) -> String {
        // Remove a fully-closed widget block if one already landed mid-stream,
        // so its raw JSON never shows.
        let withoutClosed = extract(from: text).cleanedText
        // Then hide a still-open trailing fence.
        for token in fenceTokens {
            if let openRange = withoutClosed.range(of: token, options: .caseInsensitive),
               withoutClosed.range(of: "```", range: openRange.upperBound..<withoutClosed.endIndex) == nil {
                return String(withoutClosed[withoutClosed.startIndex..<openRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return withoutClosed
    }
}

#if DEBUG
extension MessageWidget {
    static var demoChart: MessageWidget {
        MessageWidget(
            kind: .chart,
            title: "ETH watcher · threshold alert",
            freshness: .fresh,
            time: "1h ago",
            followUp: "Why is it dropping?",
            chart: WidgetChart(
                label: "ETH / USD",
                value: "$3,124",
                delta: "−$74.20 (−2.3%)",
                trend: .down,
                points: [3210, 3198, 3205, 3180, 3192, 3164, 3150, 3158, 3132, 3124],
                caption: "Threshold $3,180 broken at 9:47am",
                timeframe: "past 1h"
            )
        )
    }

    static var demoMetric: MessageWidget {
        MessageWidget(
            kind: .metric,
            title: "Portfolio",
            freshness: .fresh,
            time: "just now",
            followUp: "What changed today?",
            metric: WidgetMetric(
                label: "Total value",
                value: "$48,210",
                delta: "+1.8% today",
                trend: .up,
                caption: "3 positions · last synced 2m ago"
            )
        )
    }

    static var demoComparison: MessageWidget {
        MessageWidget(
            kind: .comparison,
            title: "Comparison · TEE hardware",
            freshness: .stale,
            time: "from yesterday's chat",
            followUp: "Which should we ship on?",
            comparison: WidgetComparison(
                subtitle: "SEV-SNP vs TDX",
                columns: ["SEV-SNP", "TDX"],
                rows: [
                    WidgetComparisonRow(label: "Memory encryption", cells: [
                        WidgetComparisonCell(text: "AES-128 XEX", tone: .good),
                        WidgetComparisonCell(text: "AES-128 XTS", tone: .good)
                    ]),
                    WidgetComparisonRow(label: "Attestation", cells: [
                        WidgetComparisonCell(text: "VCEK + report", tone: .neutral),
                        WidgetComparisonCell(text: "Quote + TDREPORT", tone: .neutral)
                    ]),
                    WidgetComparisonRow(label: "VM isolation", cells: [
                        WidgetComparisonCell(text: "RMP-based", tone: .neutral),
                        WidgetComparisonCell(text: "Stage-2 paging", tone: .neutral)
                    ]),
                    WidgetComparisonRow(label: "Live migration", cells: [
                        WidgetComparisonCell(text: "preview", tone: .warn),
                        WidgetComparisonCell(text: "—", tone: .off)
                    ])
                ]
            )
        )
    }

    static var demoNewsBrief: MessageWidget {
        MessageWidget(
            kind: .newsBrief,
            title: "Daily news brief",
            freshness: .fresh,
            time: "8:02am",
            followUp: "Drill into the ceasefire story…",
            newsBrief: WidgetNewsBrief(
                heading: "Today · 3 stories",
                stories: [
                    WidgetNewsStory(title: "US–Iran ceasefire under strain", tag: "Conflict", sources: [
                        WidgetNewsSource(label: "W", color: "#ff7e1c", domain: "wsj.com"),
                        WidgetNewsSource(label: "A", color: "#000000", domain: "apnews.com")
                    ]),
                    WidgetNewsStory(title: "Israel strikes Beirut as Lebanon conflict escalates", tag: "Conflict", sources: [
                        WidgetNewsSource(label: "B", color: "#CC0000", domain: "bbc.com")
                    ]),
                    WidgetNewsStory(title: "Oil down on talks of reopening Hormuz", tag: "Markets", sources: [
                        WidgetNewsSource(label: "R", color: "#FF6B35", domain: "reuters.com"),
                        WidgetNewsSource(label: "B", color: "#000000", domain: "bloomberg.com")
                    ])
                ]
            )
        )
    }

    static var demoAll: [MessageWidget] {
        [demoNewsBrief, demoChart, demoComparison, demoMetric]
    }
}
#endif
