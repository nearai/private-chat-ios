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
    var reviewMissingFields: [String] {
        var missing = missingFields
        if let appDraft = appActionDraft() {
            missing.append(contentsOf: appDraft.missingFields)
        }
        return missing.uniquedNonEmpty()
    }

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
        if Self.hasFuzzyTimingCue(scheduleText),
           !Self.hasConcreteTime(date: date, time: time, schedule: schedule, command: command),
           !missing.contains(where: { $0.localizedCaseInsensitiveContains("exact time") || $0.localizedCaseInsensitiveContains("time") }) {
            missing.append("exact time")
        }
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

    private static func hasFuzzyTimingCue(_ text: String) -> Bool {
        let normalized = " \(text.lowercased()) "
        let cues = [
            " upon waking ", " on waking ", " after waking ", " wake up ", " wake-up ",
            " before bed ", " at bedtime ", " bedtime ", " before sleep ",
            " with breakfast ", " with lunch ", " with dinner ", " with meals ",
            " with food ", " before meal ", " before meals ", " after meal ",
            " after meals ", " post-workout ", " pre-workout "
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
        case heading, stories, summary, actions
    }
}

extension MessageWidget {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let chart = try? c.decode(WidgetChart.self, forKey: .chart)
        let metric = try? c.decode(WidgetMetric.self, forKey: .metric)
        let comparison = try? c.decode(WidgetComparison.self, forKey: .comparison)
        let nestedNews = try? c.decode(WidgetNewsBrief.self, forKey: .newsBrief)
        let flatStories = (try? c.decode([WidgetNewsStory].self, forKey: .stories)) ?? []
        let flatNews = flatStories.isEmpty
            ? nil
            : WidgetNewsBrief(
                heading: try? c.decode(String.self, forKey: .heading),
                stories: flatStories
            )
        let news = nestedNews ?? flatNews
        let nestedActionPlan = try? c.decode(WidgetActionPlan.self, forKey: .actionPlan)
        let flatActions = (try? c.decode([WidgetActionItem].self, forKey: .actions)) ?? []
        let flatActionPlan = flatActions.isEmpty
            ? nil
            : WidgetActionPlan(
                heading: try? c.decode(String.self, forKey: .heading),
                summary: try? c.decode(String.self, forKey: .summary),
                actions: flatActions
            )
        let actionPlan = nestedActionPlan ?? flatActionPlan

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

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(freshness, forKey: .freshness)
        try c.encodeIfPresent(time, forKey: .time)
        try c.encodeIfPresent(followUp, forKey: .followUp)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(chart, forKey: .chart)
        try c.encodeIfPresent(metric, forKey: .metric)
        try c.encodeIfPresent(comparison, forKey: .comparison)
        try c.encodeIfPresent(newsBrief, forKey: .newsBrief)
        try c.encodeIfPresent(actionPlan, forKey: .actionPlan)
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

    var followUpLabel: String? {
        if usesTrackChoiceFollowUp {
            return "Track one of these stories"
        }
        return widgetNonBlank(followUp)
    }

    var followUpDraft: String? {
        if usesTrackChoiceFollowUp {
            return newsBriefTrackerDraft
        }
        return widgetNonBlank(followUp)
    }

    private var usesTrackChoiceFollowUp: Bool {
        guard kind == .newsBrief else { return false }
        let normalized = widgetNonBlank(followUp)?.lowercased() ?? ""
        return normalized.contains("which") &&
            normalized.contains("track") &&
            (normalized.contains("story") || normalized.contains("stories"))
    }

    private var newsBriefTrackerDraft: String {
        let stories = newsBrief?.stories
            .prefix(3)
            .map(\.title)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "; ")
        let optionsText = stories?.isEmpty == false ? " Options: \(stories!)." : ""
        return "Create a watcher for one story from this brief.\(optionsText) Ask me which story to track if needed, then propose cadence, sources, and what will be monitored before creating anything."
    }

    private static let widgetSentinelTokens = ["near-widget", "near_widget", "near widget", "widget"]

    /// Scans assistant text for the first valid fenced near-widget JSON block.
    /// Returns the parsed widget (or nil) and the text with that block removed.
    /// On any parse failure the original text is returned untouched, so a
    /// malformed block degrades to visible prose rather than being lost.
    private struct WidgetFence {
        var tokenStart: String.Index
        var payloadStart: String.Index
        var closeRange: Range<String.Index>
    }

    static func extract(from text: String) -> (widget: MessageWidget?, cleanedText: String) {
        var searchStart = text.startIndex
        while let fence = nextWidgetFence(in: text, from: searchStart) {
            var jsonString = text[fence.payloadStart..<fence.closeRange.lowerBound]
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
                cleaned.removeSubrange(fence.tokenStart..<fence.closeRange.upperBound)
                return (widget, cleaned.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            searchStart = fence.closeRange.upperBound // skip this block, keep scanning for a valid one
        }
        return (nil, text)
    }

    /// Earliest fenced widget block at or after `from`.
    ///
    /// The model is instructed to emit ```near-widget blocks, but live models
    /// sometimes choose a generic ```json fence and put NEAR-WIDGET as the
    /// first body line. Treat that sentinel as sanctioned widget markup too so
    /// raw JSON never leaks into the chat transcript.
    private static func nextWidgetFence(in text: String, from: String.Index) -> WidgetFence? {
        var searchStart = from
        while let openRange = text.range(of: "```", range: searchStart..<text.endIndex) {
            let headerStart = openRange.upperBound
            let headerEnd = text[headerStart..<text.endIndex].firstIndex(of: "\n") ?? text.endIndex
            let infoString = text[headerStart..<headerEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            let payloadStart = headerEnd < text.endIndex ? text.index(after: headerEnd) : headerEnd

            guard let closeRange = text.range(of: "```", range: payloadStart..<text.endIndex) else {
                return widgetFenceInfoLooksSanctioned(infoString) ||
                    payloadStartsWithWidgetSentinel(text[payloadStart..<text.endIndex])
                    ? WidgetFence(tokenStart: openRange.lowerBound, payloadStart: payloadStart, closeRange: text.endIndex..<text.endIndex)
                    : nil
            }

            if widgetFenceInfoLooksSanctioned(infoString) ||
                payloadStartsWithWidgetSentinel(text[payloadStart..<closeRange.lowerBound]) {
                return WidgetFence(tokenStart: openRange.lowerBound, payloadStart: payloadStart, closeRange: closeRange)
            }

            searchStart = closeRange.upperBound
        }
        return nil
    }

    private static func widgetFenceInfoLooksSanctioned(_ infoString: String) -> Bool {
        let normalized = normalizedWidgetMarker(infoString)
        return widgetSentinelTokens.contains { normalized.hasPrefix(normalizedWidgetMarker($0)) }
    }

    private static func payloadStartsWithWidgetSentinel(_ payload: Substring) -> Bool {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstLine = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return false
        }
        let marker = normalizedWidgetMarker(String(firstLine))
        return widgetSentinelTokens.contains { marker == normalizedWidgetMarker($0) }
    }

    private static func normalizedWidgetMarker(_ marker: String) -> String {
        marker
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    /// During streaming, hide an as-yet-unclosed near-widget fence so the user
    /// never sees raw JSON mid-stream.
    static func strippedStreamingPreview(_ text: String) -> String {
        // Remove a fully-closed widget block if one already landed mid-stream,
        // so its raw JSON never shows.
        let withoutClosed = extract(from: text).cleanedText
        // Then hide a still-open trailing fence.
        if let fence = nextWidgetFence(in: withoutClosed, from: withoutClosed.startIndex),
           fence.closeRange.isEmpty {
            return String(withoutClosed[withoutClosed.startIndex..<fence.tokenStart])
                .trimmingCharacters(in: .whitespacesAndNewlines)
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
