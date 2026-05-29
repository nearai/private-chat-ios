/**
 INTEGRATION

 The integrator must wire these points elsewhere:
 1. Own one `BriefingStore` and inject the real `runner` that sends `briefing.prompt` through the chat send path, then uses `MessageWidget.extract` on the answer.
 2. Insert `TodaySection(...)` at the top of `ConversationListView`'s main `LazyVStack` around line 252, gated to the default filter plus empty search.
 3. Register `BGTaskScheduler` and `UNUserNotificationCenter`, and call `store.runDue` on foreground.
 4. Add Info.plist keys: `UIBackgroundModes` with processing/fetch, and `BGTaskSchedulerPermittedIdentifiers`.
 */

import Foundation
import SwiftUI
@preconcurrency import UserNotifications

/// What produces a briefing's result. Live kinds fetch real data from auth-free
/// public APIs (no chat backend needed); .customPrompt runs the chat model.
enum BriefingKind: String, Codable, Hashable {
    case customPrompt
    case ethPrice
    case cryptoPrice
    case nearAccount
    case dailyNews
    /// Composed client-side from the user's other trackers + a market snapshot.
    case dailyBrief

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? "customPrompt"
        self = BriefingKind(rawValue: raw) ?? .customPrompt
    }

    var isLiveData: Bool { self != .customPrompt }
}

/// Direction of a threshold comparison for a conditional tracker.
enum BriefingComparator: String, Codable, Hashable {
    case below
    case above

    func evaluate(_ value: Double, _ threshold: Double) -> Bool {
        switch self {
        case .below: return value < threshold
        case .above: return value > threshold
        }
    }

    var phrase: String { self == .below ? "below" : "above" }
}

/// A condition gating a tracker so it only delivers when met — e.g. "notify me
/// when ETH drops below $2,000". Today this is a coin-price threshold (the one
/// signal we can check deterministically from auth-free public data); the shape
/// leaves room for other condition types later.
struct BriefingCondition: Codable, Hashable {
    var coinID: String          // CoinGecko id, e.g. "ethereum"
    var symbol: String          // display symbol, e.g. "ETH"
    var comparator: BriefingComparator
    var threshold: Double
    var currency: String        // ISO code lowercased, e.g. "usd"

    init(coinID: String, symbol: String, comparator: BriefingComparator, threshold: Double, currency: String = "usd") {
        self.coinID = coinID
        self.symbol = symbol
        self.comparator = comparator
        self.threshold = threshold
        self.currency = currency
    }

    func isSatisfied(by value: Double) -> Bool { comparator.evaluate(value, threshold) }

    var thresholdLabel: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency.uppercased()
        f.maximumFractionDigits = threshold < 10 ? 2 : 0
        return f.string(from: NSNumber(value: threshold)) ?? "\(threshold)"
    }

    /// "ETH below $2,000"
    var summary: String { "\(symbol) \(comparator.phrase) \(thresholdLabel)" }
}

/// Renders the active trackers into a chat reply for "what are you tracking?".
/// Pure + deterministic so it's unit-testable without the store.
enum TrackerListFormatter {
    static func summary(for briefings: [Briefing], now: Date = Date()) -> String {
        guard !briefings.isEmpty else {
            return "You don’t have any trackers yet. Try “notify me when ETH drops below $2,000” or “every morning, give me a news briefing.”"
        }
        // Active first, then by creation order.
        let sorted = briefings.sorted { a, b in
            a.isPaused == b.isPaused ? a.createdAt < b.createdAt : !a.isPaused
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        let lines = sorted.prefix(20).map { briefing -> String in
            var parts = ["**\(briefing.title)**"]
            if let condition = briefing.condition {
                parts.append("alerts when \(condition.summary)")
            }
            parts.append(briefing.schedule.scheduleLabel)
            if briefing.isPaused { parts.append("paused") }
            if let last = briefing.lastRunAt {
                parts.append("last ran \(relative.localizedString(for: last, relativeTo: now))")
            }
            return "• " + parts.joined(separator: " · ")
        }.joined(separator: "\n")
        return "Here’s what I’m tracking for you (\(briefings.count)):\n\n\(lines)"
    }
}

/// One recorded data point for a tracker — the numeric value parsed from a run
/// plus its original display string. Accumulated across runs to chart a trend.
struct TrackerSample: Codable, Hashable {
    var date: Date
    var value: Double
    var display: String
}

/// Turns a tracker's per-run values into a trend chart over time. Pure +
/// deterministic so it's unit-testable; the on-device "watch chart" magic.
enum TrackerHistory {
    static let maxSamples = 90

    /// First numeric value in a display string: "$14,500" → 14500, "$2.3M" →
    /// 2_300_000, "1,234.50" → 1234.5. nil when there's no number.
    static func numericValue(from string: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: #"([0-9][0-9,]*(?:\.[0-9]+)?)\s*([kmb])?"#, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let m = re.firstMatch(in: string, options: [], range: range),
              let numRange = Range(m.range(at: 1), in: string),
              var value = Double(string[numRange].replacingOccurrences(of: ",", with: "")) else { return nil }
        if m.range(at: 2).location != NSNotFound, let sufRange = Range(m.range(at: 2), in: string) {
            switch string[sufRange].lowercased() {
            case "k": value *= 1_000
            case "m": value *= 1_000_000
            case "b": value *= 1_000_000_000
            default: break
            }
        }
        return value
    }

    /// The headline value to record from a run's widget (chart → metric → note).
    static func sampleDisplay(from widget: MessageWidget) -> String? {
        if let v = widget.chart?.value, !v.isEmpty { return v }
        if let v = widget.metric?.value, !v.isEmpty { return v }
        if let note = widget.note,
           let re = try? NSRegularExpression(pattern: #"\$\s*[0-9][0-9,]*(?:\.[0-9]+)?\s*[kmb]?"#, options: [.caseInsensitive]),
           let m = re.firstMatch(in: note, options: [], range: NSRange(note.startIndex..<note.endIndex, in: note)),
           let r = Range(m.range, in: note) {
            return String(note[r]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// An informative notification body — surfaces the actual value/move instead
    /// of a generic "ready". "$14,800 (+4.2% since last check)" when there's
    /// history; otherwise the widget's headline value/headline/note.
    static func notificationBody(history: [TrackerSample], fallback widget: MessageWidget) -> String {
        if let last = history.last {
            if history.count >= 2 {
                let prev = history[history.count - 2].value
                if prev != 0 {
                    let pct = (last.value - prev) / prev * 100
                    return "\(last.display) (\(String(format: "%+.1f%%", pct)) since last check)"
                }
            }
            return last.display
        }
        if let display = sampleDisplay(from: widget) { return display }
        if let headline = widget.newsBrief?.stories.first?.title, !headline.isEmpty { return headline }
        if let note = widget.note, !note.isEmpty { return String(note.prefix(140)) }
        return "Your update is ready."
    }

    /// Default "meaningful move" threshold (fractional, e.g. 0.03 = 3%).
    static let significantMoveThreshold = 0.03

    /// The fractional change from the previous sample if it's a meaningful move
    /// (|change| ≥ threshold), else nil — so trackers can ping on signal, not
    /// every quiet check.
    static func significantMove(in history: [TrackerSample], threshold: Double = significantMoveThreshold) -> Double? {
        guard history.count >= 2 else { return nil }
        let last = history[history.count - 1].value
        let prev = history[history.count - 2].value
        guard prev != 0 else { return nil }
        let change = (last - prev) / prev
        return abs(change) >= threshold ? change : nil
    }

    /// A chart widget over the samples (oldest → newest), or nil with < 2 points.
    static func chartWidget(title: String, history: [TrackerSample]) -> MessageWidget? {
        guard history.count >= 2, let first = history.first, let last = history.last else { return nil }
        let change = last.value - first.value
        let trend: WidgetTrend = change > 0 ? .up : (change < 0 ? .down : .flat)
        let deltaPct = first.value != 0 ? change / first.value * 100 : 0
        let delta = String(format: "%+.1f%% over %d checks", deltaPct, history.count)
        return MessageWidget(
            kind: .chart,
            title: title,
            freshness: .fresh,
            time: "just now",
            chart: WidgetChart(
                label: title,
                value: last.display,
                delta: delta,
                trend: trend,
                points: history.map(\.value),
                caption: "tracked over time",
                timeframe: "\(history.count) checks"
            )
        )
    }
}

/// Composes the agentic Daily Brief — every active tracker's latest value plus
/// a market snapshot — into one digest widget. Pure + deterministic so it's
/// unit-testable; the "surface what matters on my behalf" capstone.
enum BriefDigest {
    static func compose(trackers: [Briefing], market: [(label: String, value: String)], now: Date = Date()) -> MessageWidget {
        var rows: [WidgetComparisonRow] = []
        // Skip paused trackers and the brief itself (a dailyBrief tracker
        // shouldn't list itself).
        let active = trackers.filter { !$0.isPaused && $0.kind != .dailyBrief }
        for tracker in active.prefix(8) {
            let value = tracker.latestResult.flatMap { TrackerHistory.sampleDisplay(from: $0) }
                ?? tracker.latestResult?.newsBrief?.stories.first?.title
                ?? (tracker.lastRunAt == nil ? "pending" : "—")
            rows.append(WidgetComparisonRow(label: tracker.title, cells: [WidgetComparisonCell(text: value, tone: nil)]))
        }
        for line in market {
            rows.append(WidgetComparisonRow(label: line.label, cells: [WidgetComparisonCell(text: line.value, tone: nil)]))
        }
        if rows.isEmpty {
            rows.append(WidgetComparisonRow(label: "Nothing tracked yet", cells: [WidgetComparisonCell(text: "—", tone: nil)]))
        }
        let count = active.count
        let subtitle = count == 0 ? "Market snapshot" : "\(count) tracker\(count == 1 ? "" : "s") · markets"
        return MessageWidget(
            kind: .comparison,
            title: "Your brief",
            freshness: .fresh,
            time: "just now",
            followUp: "Track something else?",
            comparison: WidgetComparison(subtitle: subtitle, columns: ["Now"], rows: rows)
        )
    }
}

struct Briefing: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var prompt: String
    var schedule: BriefingSchedule
    var isPaused: Bool
    var createdAt: Date
    var lastRunAt: Date?
    var latestResult: MessageWidget?
    var kind: BriefingKind
    var accountID: String?
    /// Run a multi-model council + synthesis on each scheduled run (customPrompt
    /// only; live-data kinds are single API fetches where council is meaningless).
    var council: Bool
    /// When set, the tracker only delivers on runs where the condition is met
    /// (e.g. a price threshold). nil = a plain recurring briefing.
    var condition: BriefingCondition?
    /// Numeric values recorded across runs (oldest → newest), so a tracker can
    /// chart its trend over time. Empty for trackers whose runs aren't numeric.
    var history: [TrackerSample]

    enum CodingKeys: String, CodingKey {
        case id, title, prompt, schedule, isPaused, createdAt, lastRunAt, latestResult, kind, accountID, council, condition, history
    }

    init(
        id: UUID = UUID(),
        title: String,
        prompt: String,
        schedule: BriefingSchedule,
        isPaused: Bool = false,
        createdAt: Date = Date(),
        lastRunAt: Date? = nil,
        latestResult: MessageWidget? = nil,
        kind: BriefingKind = .customPrompt,
        accountID: String? = nil,
        council: Bool = false,
        condition: BriefingCondition? = nil,
        history: [TrackerSample] = []
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.schedule = schedule
        self.isPaused = isPaused
        self.createdAt = createdAt
        self.lastRunAt = lastRunAt
        self.latestResult = latestResult
        self.kind = kind
        self.accountID = accountID
        self.council = council
        self.condition = condition
        self.history = history
    }

    /// True when this tracker is gated on a condition (a threshold alert).
    var isConditional: Bool { condition != nil }

    var status: BriefingStatus {
        if isPaused { return .paused }
        if latestResult != nil { return .live }
        return .scheduled
    }
}

extension Briefing {
    // Forgiving decode so a briefings.json written before `kind`/`accountID`
    // existed still loads (back-compat for upgrading users).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try? c.decode(UUID.self, forKey: .id)) ?? UUID(),
            title: (try? c.decode(String.self, forKey: .title)) ?? "Briefing",
            prompt: (try? c.decode(String.self, forKey: .prompt)) ?? "",
            schedule: (try? c.decode(BriefingSchedule.self, forKey: .schedule)) ?? .daily(hour: 8, minute: 0),
            isPaused: (try? c.decode(Bool.self, forKey: .isPaused)) ?? false,
            createdAt: (try? c.decode(Date.self, forKey: .createdAt)) ?? Date(),
            lastRunAt: try? c.decode(Date.self, forKey: .lastRunAt),
            latestResult: try? c.decode(MessageWidget.self, forKey: .latestResult),
            kind: (try? c.decode(BriefingKind.self, forKey: .kind)) ?? .customPrompt,
            accountID: try? c.decode(String.self, forKey: .accountID),
            council: (try? c.decode(Bool.self, forKey: .council)) ?? false,
            condition: try? c.decode(BriefingCondition.self, forKey: .condition),
            history: (try? c.decode([TrackerSample].self, forKey: .history)) ?? []
        )
    }
}

enum BriefingStatus: String, Codable, Hashable {
    case live
    case scheduled
    case paused
}

enum BriefingSchedule: Codable, Hashable {
    case daily(hour: Int, minute: Int)
    case weekdays(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)
    case everyNHours(Int)

    private enum Kind: String, Codable {
        case daily
        case weekdays
        case weekly
        case everyNHours
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case weekday
        case hour
        case minute
        case intervalHours
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let hour = (try? container.decode(Int.self, forKey: .hour)) ?? 9
        let minute = (try? container.decode(Int.self, forKey: .minute)) ?? 0
        switch kind {
        case .daily:
            self = .daily(hour: hour, minute: minute)
        case .weekdays:
            self = .weekdays(hour: hour, minute: minute)
        case .weekly:
            self = .weekly(
                weekday: (try? container.decode(Int.self, forKey: .weekday)) ?? 2,
                hour: hour,
                minute: minute
            )
        case .everyNHours:
            self = .everyNHours(max(1, (try? container.decode(Int.self, forKey: .intervalHours)) ?? 6))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .daily(hour, minute):
            try container.encode(Kind.daily, forKey: .kind)
            try container.encode(clampedHour(hour), forKey: .hour)
            try container.encode(clampedMinute(minute), forKey: .minute)
        case let .weekdays(hour, minute):
            try container.encode(Kind.weekdays, forKey: .kind)
            try container.encode(clampedHour(hour), forKey: .hour)
            try container.encode(clampedMinute(minute), forKey: .minute)
        case let .weekly(weekday, hour, minute):
            try container.encode(Kind.weekly, forKey: .kind)
            try container.encode(clampedWeekday(weekday), forKey: .weekday)
            try container.encode(clampedHour(hour), forKey: .hour)
            try container.encode(clampedMinute(minute), forKey: .minute)
        case let .everyNHours(interval):
            try container.encode(Kind.everyNHours, forKey: .kind)
            try container.encode(max(1, interval), forKey: .intervalHours)
        }
    }

    func nextRun(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case let .daily(hour, minute):
            return nextMatchingDate(after: date, hour: hour, minute: minute, calendar: calendar) { _ in true }
        case let .weekdays(hour, minute):
            return nextMatchingDate(after: date, hour: hour, minute: minute, calendar: calendar) { candidate in
                let weekday = calendar.component(.weekday, from: candidate)
                return (2...6).contains(weekday)
            }
        case let .weekly(weekday, hour, minute):
            let targetWeekday = clampedWeekday(weekday)
            return nextMatchingDate(after: date, hour: hour, minute: minute, calendar: calendar) { candidate in
                calendar.component(.weekday, from: candidate) == targetWeekday
            }
        case let .everyNHours(interval):
            guard interval > 0 else { return nil }
            return calendar.date(byAdding: .hour, value: interval, to: date)
        }
    }

    /// Repeating local-notification triggers so a scheduled briefing pings the
    /// user at its time even if background refresh is throttled. Weekday
    /// schedules expand to one weekly trigger per business day.
    func notificationTriggers() -> [UNNotificationTrigger] {
        switch self {
        case let .daily(hour, minute):
            var components = DateComponents()
            components.hour = clampedHour(hour)
            components.minute = clampedMinute(minute)
            return [UNCalendarNotificationTrigger(dateMatching: components, repeats: true)]
        case let .weekdays(hour, minute):
            return (2...6).map { weekday in
                var components = DateComponents()
                components.weekday = weekday
                components.hour = clampedHour(hour)
                components.minute = clampedMinute(minute)
                return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            }
        case let .weekly(weekday, hour, minute):
            var components = DateComponents()
            components.weekday = clampedWeekday(weekday)
            components.hour = clampedHour(hour)
            components.minute = clampedMinute(minute)
            return [UNCalendarNotificationTrigger(dateMatching: components, repeats: true)]
        case let .everyNHours(interval):
            let seconds = TimeInterval(max(1, interval) * 3600)
            return [UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: true)]
        }
    }

    var scheduleLabel: String {
        switch self {
        case let .daily(hour, minute):
            return "Daily · \(Self.timeLabel(hour: hour, minute: minute))"
        case let .weekdays(hour, minute):
            return "Weekdays · \(Self.timeLabel(hour: hour, minute: minute))"
        case let .weekly(weekday, hour, minute):
            return "\(Self.weekdayLabel(weekday)) · \(Self.timeLabel(hour: hour, minute: minute))"
        case let .everyNHours(interval):
            return "Every \(max(1, interval))h"
        }
    }

    var timeComponents: (hour: Int, minute: Int)? {
        switch self {
        case let .daily(hour, minute),
             let .weekdays(hour, minute),
             let .weekly(_, hour, minute):
            return (clampedHour(hour), clampedMinute(minute))
        case .everyNHours:
            return nil
        }
    }

    var frequency: BriefingScheduleFrequency {
        switch self {
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .weekly: return .weekly
        case .everyNHours: return .everyNHours
        }
    }

    private func nextMatchingDate(
        after date: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar,
        matches: (Date) -> Bool
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = clampedHour(hour)
        components.minute = clampedMinute(minute)
        components.second = 0

        guard let startOfCandidateDay = calendar.date(from: components) else {
            return nil
        }

        for dayOffset in 0...14 {
            guard let candidate = calendar.date(byAdding: .day, value: dayOffset, to: startOfCandidateDay) else {
                continue
            }
            if candidate > date, matches(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func timeLabel(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = clampedHour(hour)
        components.minute = clampedMinute(minute)
        let date = Calendar.current.date(from: components) ?? Date()
        return briefingTimeFormatter.string(from: date)
    }

    private static func weekdayLabel(_ weekday: Int) -> String {
        let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return labels[clampedWeekday(weekday) - 1]
    }
}

enum BriefingScheduleFrequency: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekdays = "Weekdays"
    case weekly = "Weekly"
    case everyNHours = "Every N hours"

    var id: String { rawValue }
}

@MainActor
final class BriefingStore: ObservableObject {
    @Published private(set) var briefings: [Briefing]
    var runner: (Briefing) async -> MessageWidget?

    private let fileURL: URL

    init(
        briefings: [Briefing] = [],
        fileURL: URL? = nil,
        runner: @escaping (Briefing) async -> MessageWidget? = { briefing in
            BriefingSamples.sampleWidget(title: briefing.title)
        }
    ) {
        self.briefings = briefings
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.runner = runner
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.briefing.decode([Briefing].self, from: data) else {
            return
        }
        briefings = decoded.sorted(by: briefingSort)
    }

    func add(_ briefing: Briefing) {
        briefings.append(briefing)
        briefings.sort(by: briefingSort)
        save()
        Self.requestNotificationAuthorizationIfNeeded()
        Self.scheduleReminderNotifications(for: briefing)
    }

    func update(_ briefing: Briefing) {
        guard let index = briefings.firstIndex(where: { $0.id == briefing.id }) else {
            add(briefing)
            return
        }
        briefings[index] = briefing
        briefings.sort(by: briefingSort)
        save()
        Self.scheduleReminderNotifications(for: briefing)
    }

    func remove(_ briefing: Briefing) {
        briefings.removeAll { $0.id == briefing.id }
        save()
        Self.cancelReminderNotifications(for: briefing.id)
    }

    func setPaused(_ briefing: Briefing, _ isPaused: Bool) {
        guard let index = briefings.firstIndex(where: { $0.id == briefing.id }) else { return }
        briefings[index].isPaused = isPaused
        save()
        Self.scheduleReminderNotifications(for: briefings[index])
    }

    func run(_ briefing: Briefing) async {
        guard let snapshot = briefings.first(where: { $0.id == briefing.id }) else { return }
        let result = await runner(snapshot)
        // Re-resolve after the await; the list may have changed during the call.
        guard let index = briefings.firstIndex(where: { $0.id == briefing.id }) else { return }
        // On failure (e.g. signed out), leave lastRunAt untouched so the briefing
        // stays due and retries, rather than silently skipping its next run.
        guard let result else { return }
        // Accumulate a numeric value from this run, then — once there are ≥2
        // points — surface the trend over time as a chart ("watch chart"). Runs
        // that yield no number just deliver the result as-is.
        var delivered = result
        // Only for open-ended (customPrompt) trackers — live-data kinds already
        // return purpose-built widgets (e.g. crypto's 24h sparkline) we shouldn't
        // overwrite with a few run-points.
        if briefings[index].kind == .customPrompt,
           let display = TrackerHistory.sampleDisplay(from: result),
           let value = TrackerHistory.numericValue(from: display) {
            briefings[index].history.append(TrackerSample(date: Date(), value: value, display: display))
            if briefings[index].history.count > TrackerHistory.maxSamples {
                briefings[index].history.removeFirst(briefings[index].history.count - TrackerHistory.maxSamples)
            }
            if let chart = TrackerHistory.chartWidget(title: briefings[index].title, history: briefings[index].history) {
                delivered = chart
            }
        }
        briefings[index].latestResult = delivered
        briefings[index].lastRunAt = Date()
        // A conditional alert is one-shot: it only delivers when its threshold is
        // crossed, so once it fires we pause it rather than re-notifying every
        // cycle while the condition still holds. It stays on Today as a record the
        // user can re-enable.
        if briefings[index].isConditional {
            briefings[index].isPaused = true
        }
        save()
        // Signal, not noise: a numeric tracker pings only on its first reading or
        // a meaningful move; quiet checks update Today silently. Non-numeric
        // trackers (news digests, the daily brief) notify each run as before.
        let history = briefings[index].history
        let isNumericTracker = briefings[index].kind == .customPrompt && !history.isEmpty
        let shouldNotify = !isNumericTracker || history.count == 1 || TrackerHistory.significantMove(in: history) != nil
        if shouldNotify {
            Self.postBriefingReadyNotification(
                title: briefings[index].title,
                body: TrackerHistory.notificationBody(history: history, fallback: delivered)
            )
        }
    }

    /// Schedules a one-off personal reminder ("remind me to call mom at 5pm") as
    /// a local notification. Best-effort: requests authorization if undetermined,
    /// then adds the request (the system drops it if access is denied).
    nonisolated static func schedulePersonalReminder(title: String, date: Date, id: String = UUID().uuidString) {
        requestNotificationAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        content.body = title
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "reminder-\(id)", content: content, trigger: trigger)
        )
    }

    /// Requested contextually when the user creates their first briefing.
    nonisolated static func requestNotificationAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Schedules repeating local notifications at the briefing's time so it
    /// surfaces proactively even when background refresh doesn't fire. Replaces
    /// any previously scheduled reminders for this briefing; paused briefings
    /// just get their reminders cleared.
    /// Deterministic reminder identifiers for a briefing. A fixed upper bound
    /// (≥ any schedule's trigger count, e.g. 5 weekday triggers) lets us clear
    /// them synchronously without an async getPending round-trip.
    private nonisolated static func reminderIdentifiers(for id: UUID) -> [String] {
        (0..<8).map { "briefing-scheduled-\(id.uuidString)-\($0)" }
    }

    nonisolated static func scheduleReminderNotifications(for briefing: Briefing) {
        let center = UNUserNotificationCenter.current()
        // Remove this briefing's existing reminders SYNCHRONOUSLY (deterministic
        // ids) before adding new ones — an async getPending-based cancel could
        // otherwise fire late and delete the reminders we add just below.
        center.removePendingNotificationRequests(withIdentifiers: reminderIdentifiers(for: briefing.id))
        guard !briefing.isPaused else { return }
        // Conditional trackers must NOT pre-schedule guaranteed pings — that would
        // fire even when the threshold isn't met. They notify only on a met run,
        // via postBriefingReadyNotification when runBriefing returns a result.
        guard briefing.condition == nil else { return }
        let triggers = briefing.schedule.notificationTriggers()
        let title = briefing.title
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            for (index, trigger) in triggers.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = "Your scheduled briefing is ready — tap to open."
                content.sound = .default
                let identifier = "briefing-scheduled-\(briefing.id.uuidString)-\(index)"
                center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            }
        }
    }

    nonisolated static func cancelReminderNotifications(for id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: reminderIdentifiers(for: id))
    }

    /// Posts when a briefing produces a fresh result. iOS suppresses foreground
    /// banners by default, so app-open runs don't spam; background runs surface.
    nonisolated static func postBriefingReadyNotification(title: String, body: String = "Your briefing is ready.") {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: "briefing-\(UUID().uuidString)", content: content, trigger: nil))
        }
    }

    func runDue(now: Date = Date()) async {
        let dueIDs = Set(dueBriefings(now: now).map(\.id))
        for briefing in briefings where dueIDs.contains(briefing.id) {
            await run(briefing)
        }
    }

    func dueBriefings(now: Date = Date()) -> [Briefing] {
        briefings.filter { briefing in
            guard !briefing.isPaused else { return false }
            let baseline = briefing.lastRunAt ?? briefing.createdAt
            guard let nextRun = briefing.schedule.nextRun(after: baseline) else { return false }
            return nextRun <= now
        }
    }

    #if DEBUG
    func seedDemoSamples() {
        briefings = BriefingSamples.sampleBriefings
    }
    #endif

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.briefing.encode(briefings)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            return
        }
        writeWidgetSnapshot()
    }

    /// Mirror the current briefings into the App Group as a flattened snapshot
    /// the widget can decode without compiling any app view code. Best-effort:
    /// failures (e.g. missing entitlement) just leave the widget on its last
    /// snapshot.
    private func writeWidgetSnapshot() {
        #if DEBUG
        // A demo-capture run uses seeded sample trackers; don't let them
        // overwrite the real home-screen widget snapshot.
        if DemoCapture.isEnabled { return }
        #endif
        guard let snapshotURL = BriefingSharedStore.sharedFileURL(BriefingSharedStore.snapshotFileName) else {
            return
        }
        let snapshots = briefings.map { briefing in
            BriefingSnapshot(
                id: briefing.id.uuidString,
                title: briefing.title,
                summary: Self.widgetSummary(for: briefing),
                lastRunAt: briefing.lastRunAt
            )
        }
        do {
            try FileManager.default.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.briefingSnapshot.encode(snapshots)
            try data.write(to: snapshotURL, options: [.atomic])
            BriefingWidgetRefresher.reload()
        } catch {
            return
        }
    }

    /// One-line summary for the widget, derived from the briefing's latest
    /// result. Prefers a concrete metric/chart value, then a news headline,
    /// then the generic note, then a scheduled-state fallback.
    static func widgetSummary(for briefing: Briefing) -> String {
        guard let widget = briefing.latestResult else {
            return briefing.isPaused ? "Paused" : "Scheduled — \(briefing.schedule.scheduleLabel)"
        }
        switch widget.kind {
        case .metric:
            if let metric = widget.metric, !metric.value.isEmpty {
                if let delta = metric.delta, !delta.isEmpty { return "\(metric.value) · \(delta)" }
                return metric.value
            }
        case .chart:
            if let value = widget.chart?.value ?? widget.chart?.label, !value.isEmpty {
                if let delta = widget.chart?.delta, !delta.isEmpty { return "\(value) · \(delta)" }
                return value
            }
        case .newsBrief:
            if let headline = widget.newsBrief?.stories.first?.title ?? widget.newsBrief?.heading,
               !headline.isEmpty {
                return headline
            }
        case .comparison:
            if let subtitle = widget.comparison?.subtitle, !subtitle.isEmpty { return subtitle }
        case .generic:
            break
        }
        if let note = widget.note, !note.isEmpty { return note }
        return "Updated"
    }

    private static func defaultFileURL() -> URL {
        // Prefer the App Group container so the home-screen widget can read the
        // same briefings file. Fall back to Application Support if the
        // entitlement is unavailable (e.g. a stripped build).
        if let shared = BriefingSharedStore.sharedFileURL(BriefingSharedStore.briefingsFileName) {
            migrateLegacyFileIfNeeded(to: shared)
            return shared
        }
        return legacyFileURL()
    }

    private static func legacyFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(BriefingSharedStore.directoryName, isDirectory: true)
            .appendingPathComponent(BriefingSharedStore.briefingsFileName)
    }

    #if DEBUG
    /// Demo-capture briefings live in their own file so seeded samples (and the
    /// saves their scheduled runs trigger) never leak into the real
    /// `briefings.json` that an interactive/real session loads. Without this,
    /// a screenshot run's sample trackers ("Daily news @ 9am") would reappear
    /// on Today the next time the app opened for real.
    static func demoFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(BriefingSharedStore.directoryName, isDirectory: true)
            .appendingPathComponent("briefings-demo.json")
    }
    #endif

    /// One-time move of a pre-App-Group briefings.json into the shared
    /// container so upgrading users keep their briefings and the widget sees
    /// them. No-op once the shared file exists.
    private static func migrateLegacyFileIfNeeded(to shared: URL) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: shared.path) else { return }
        let legacy = legacyFileURL()
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        do {
            try fileManager.createDirectory(
                at: shared.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: legacy, to: shared)
        } catch {
            return
        }
    }
}

struct TodaySection: View {
    @ObservedObject var store: BriefingStore
    var onOpenBriefing: (Briefing) -> Void
    var onNewBriefing: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if store.briefings.isEmpty {
                Text("Pull live briefings into your day. They refresh on schedule and land right here.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SuggestedBriefingsView(store: store, onOpen: onOpenBriefing)
            } else {
                let liveBriefings = store.briefings.filter { $0.latestResult != nil }
                if !liveBriefings.isEmpty {
                    labeledSection("Live", count: "\(liveBriefings.count) active")
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(liveBriefings) { briefing in
                            BriefingTile(briefing: briefing) {
                                onOpenBriefing(briefing)
                            }
                        }
                    }
                }

                labeledSection("Scheduled", count: "\(store.briefings.count) upcoming")
                    .padding(.top, liveBriefings.isEmpty ? 0 : 2)
                VStack(spacing: 0) {
                    ForEach(store.briefings) { briefing in
                        ScheduleRow(briefing: briefing) {
                            onOpenBriefing(briefing)
                        }
                        if briefing.id != store.briefings.last?.id {
                            Divider()
                                .overlay(Color.appHairline)
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }

                SuggestedBriefingsView(store: store, onOpen: onOpenBriefing)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today")
                    .font(.title3.weight(.semibold))
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 12)
            Button(action: onNewBriefing) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appPanelBackground)
                    .frame(width: 32, height: 32)
                    .background(Color.actionPrimary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New briefing")
        }
    }

    private func labeledSection(_ title: String, count: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.textSecondary)
            Spacer(minLength: 8)
            if let count {
                Text(count)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}

struct BriefingTile: View {
    let briefing: Briefing
    var action: () -> Void = {}

    private var widget: MessageWidget? { briefing.latestResult }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    BriefingIconChip(briefing: briefing, widget: widget)
                    Spacer(minLength: 8)
                    if widget != nil {
                        Circle()
                            .fill(Color.actionPrimary)
                            .frame(width: 7, height: 7)
                            .padding(.top, 2)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(briefing.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    tileBody
                }

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(footerText)
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(deliveredTime)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tileBody: some View {
        switch widget?.kind {
        case .metric:
            if let metric = widget?.metric {
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.value)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let delta = metric.delta {
                        Text(delta)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(trendColor(metric.trend))
                            .lineLimit(1)
                    }
                }
            }
        case .chart:
            VStack(alignment: .leading, spacing: 3) {
                Text(widget?.chart?.value ?? widget?.chart?.label ?? "Updated")
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let delta = widget?.chart?.delta {
                    Text(delta)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(trendColor(widget?.chart?.trend))
                        .lineLimit(1)
                }
            }
        case .comparison:
            Text(widget?.comparison?.subtitle ?? widget?.note ?? "Comparison ready")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        case .newsBrief:
            Text(widget?.newsBrief?.stories.first?.title ?? widget?.newsBrief?.heading ?? "News brief ready")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        case .generic, .none:
            Text(widget?.note ?? "No result yet")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footerText: String {
        guard let widget else { return "Scheduled" }
        switch widget.kind {
        case .newsBrief:
            let stories = widget.newsBrief?.stories.count ?? 0
            let sources = widget.newsBrief?.stories.reduce(0) { $0 + $1.sources.count } ?? 0
            if stories > 0, sources > 0 { return "\(stories) stories · \(sources) sources" }
            if stories > 0 { return "\(stories) stories" }
            return "News brief"
        case .comparison:
            let rows = widget.comparison?.rows.count ?? 0
            return rows == 1 ? "1 row" : "\(rows) rows"
        case .chart:
            return widget.chart?.timeframe ?? widget.chart?.caption ?? "Chart"
        case .metric:
            return widget.metric?.caption ?? widget.metric?.label ?? "Metric"
        case .generic:
            return "Brief"
        }
    }

    private var deliveredTime: String {
        if let time = widget?.time, !time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return time
        }
        if let lastRunAt = briefing.lastRunAt {
            return briefingTimeFormatter.string(from: lastRunAt)
        }
        return "pending"
    }

    private func trendColor(_ trend: WidgetTrend?) -> Color {
        switch trend {
        case .up: return Color.proofVerified
        case .down: return Color.proofMismatch
        case .flat, .none: return Color.textSecondary
        }
    }
}

struct ScheduleRow: View {
    let briefing: Briefing
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                BriefingIconChip(briefing: briefing, widget: briefing.latestResult)

                VStack(alignment: .leading, spacing: 3) {
                    Text(briefing.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(briefing.schedule.scheduleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .opacity(briefing.isPaused ? 0.48 : 1)
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if briefing.isPaused { return "paused" }
        guard let next = briefing.schedule.nextRun(after: briefing.lastRunAt ?? Date()) else {
            return "not scheduled"
        }
        return "next run \(relativeNextRun(next))"
    }
}

struct BriefingEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let existingBriefing: Briefing?
    private let onSave: (Briefing) -> Void
    private let onDelete: ((Briefing) -> Void)?

    @State private var title: String
    @State private var prompt: String
    @State private var frequency: BriefingScheduleFrequency
    @State private var time: Date
    @State private var weekday: Int
    @State private var intervalHours: Int
    @State private var isPaused: Bool

    init(
        briefing: Briefing? = nil,
        onSave: @escaping (Briefing) -> Void = { _ in },
        onDelete: ((Briefing) -> Void)? = nil
    ) {
        self.existingBriefing = briefing
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: briefing?.title ?? "")
        _prompt = State(initialValue: briefing?.prompt ?? "")
        _frequency = State(initialValue: briefing?.schedule.frequency ?? .weekdays)
        _time = State(initialValue: Self.dateForTime(briefing?.schedule.timeComponents ?? (8, 0)))
        _weekday = State(initialValue: Self.weekday(from: briefing?.schedule) ?? 2)
        _intervalHours = State(initialValue: Self.interval(from: briefing?.schedule) ?? 6)
        _isPaused = State(initialValue: briefing?.isPaused ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Briefing") {
                    TextField("Title", text: $title)
                    TextField("Prompt", text: $prompt, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(BriefingScheduleFrequency.allCases) { frequency in
                            Text(frequency.rawValue).tag(frequency)
                        }
                    }

                    if frequency == .weekly {
                        Picker("Day", selection: $weekday) {
                            ForEach(1...7, id: \.self) { value in
                                Text(weekdayName(value)).tag(value)
                            }
                        }
                    }

                    if frequency == .everyNHours {
                        Stepper("Every \(intervalHours) hours", value: $intervalHours, in: 1...24)
                    } else {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }

                    Toggle("Paused", isOn: $isPaused)
                        .tint(Color.actionPrimary)
                }

                if let existingBriefing, onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            onDelete?(existingBriefing)
                            dismiss()
                        } label: {
                            Text("Delete Briefing")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle(existingBriefing == nil ? "New Briefing" : "Edit Briefing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(makeBriefing())
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func makeBriefing() -> Briefing {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? 8
        let minute = components.minute ?? 0
        return Briefing(
            id: existingBriefing?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: makeSchedule(hour: hour, minute: minute),
            isPaused: isPaused,
            createdAt: existingBriefing?.createdAt ?? Date(),
            lastRunAt: existingBriefing?.lastRunAt,
            latestResult: existingBriefing?.latestResult,
            // Preserve the live kind + account when editing, or the edit would
            // silently revert a live briefing to a custom prompt.
            kind: existingBriefing?.kind ?? .customPrompt,
            accountID: existingBriefing?.accountID,
            // Preserve council + condition too — otherwise editing a conditional
            // alert would silently turn it into a plain recurring price briefing
            // that fires every cycle.
            council: existingBriefing?.council ?? false,
            condition: existingBriefing?.condition
        )
    }

    private func makeSchedule(hour: Int, minute: Int) -> BriefingSchedule {
        switch frequency {
        case .daily:
            return .daily(hour: hour, minute: minute)
        case .weekdays:
            return .weekdays(hour: hour, minute: minute)
        case .weekly:
            return .weekly(weekday: weekday, hour: hour, minute: minute)
        case .everyNHours:
            return .everyNHours(intervalHours)
        }
    }

    private func weekdayName(_ value: Int) -> String {
        let labels = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return labels[clampedWeekday(value) - 1]
    }

    private static func dateForTime(_ time: (hour: Int, minute: Int)) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = clampedHour(time.hour)
        components.minute = clampedMinute(time.minute)
        return Calendar.current.date(from: components) ?? Date()
    }

    private static func weekday(from schedule: BriefingSchedule?) -> Int? {
        if case let .weekly(weekday, _, _) = schedule {
            return weekday
        }
        return nil
    }

    private static func interval(from schedule: BriefingSchedule?) -> Int? {
        if case let .everyNHours(interval) = schedule {
            return interval
        }
        return nil
    }
}

struct BriefingDetailView: View {
    @ObservedObject var store: BriefingStore
    let briefing: Briefing
    var onFollowUp: (String) -> Void = { _ in }

    @State private var isRunning = false

    private var currentBriefing: Briefing {
        store.briefings.first(where: { $0.id == briefing.id }) ?? briefing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        BriefingIconChip(briefing: currentBriefing, widget: currentBriefing.latestResult)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentBriefing.title)
                                .font(.title3.weight(.semibold))
                            Text(currentBriefing.schedule.scheduleLabel)
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }

                    Text(lastRunText)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(14)
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }

                Button {
                    Task {
                        isRunning = true
                        await store.run(currentBriefing)
                        isRunning = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(isRunning ? "Running" : "Run now")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color.appPanelBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isRunning)

                if let widget = currentBriefing.latestResult {
                    MessageWidgetCard(widget: widget, onFollowUp: onFollowUp)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No result yet")
                            .font(.headline)
                        Text("Run this briefing to generate its first Today card.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 1)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.appBackground)
        .navigationTitle("Briefing")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lastRunText: String {
        guard let lastRunAt = currentBriefing.lastRunAt else {
            return "Last run: never"
        }
        return "Last run: \(lastRunAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct TodayEmptyState: View {
    var onNewBriefing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BriefingIconChip(symbolName: "calendar.badge.plus", tint: Color.actionPrimary)
            Text("No briefings yet")
                .font(.headline)
            Text("Create a recurring prompt and its latest result will appear here.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onNewBriefing) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("New briefing")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.appPanelBackground)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}

private struct BriefingIconChip: View {
    let symbolName: String
    let tint: Color

    init(briefing: Briefing, widget: MessageWidget?) {
        let palette = Self.palette(for: briefing.id)
        self.symbolName = Self.symbolName(for: widget?.kind)
        self.tint = briefing.isPaused ? Color.textSecondary : palette
    }

    init(symbolName: String, tint: Color) {
        self.symbolName = symbolName
        self.tint = tint
    }

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            }
    }

    private static func symbolName(for kind: WidgetKind?) -> String {
        switch kind {
        case .chart: return "chart.xyaxis.line"
        case .metric: return "number"
        case .comparison: return "tablecells"
        case .newsBrief: return "newspaper"
        case .generic, .none: return "sparkles"
        }
    }

    private static func palette(for id: UUID) -> Color {
        let colors: [Color] = [
            Color.actionPrimary,
            Color.brandBlue,
            Color.proofVerified,
            Color.proofStale,
            Color.proofMismatch,
            Color.textSecondary
        ]
        let index = abs(id.uuidString.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - One-tap templates for the named use cases

struct BriefingTemplate: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let kind: BriefingKind
    let schedule: BriefingSchedule
    let prompt: String
    let needsAccount: Bool

    static let suggested: [BriefingTemplate] = [
        BriefingTemplate(
            title: "Daily news brief",
            subtitle: "Top headlines, every weekday morning",
            symbol: "newspaper.fill",
            tint: .actionPrimary,
            kind: .dailyNews,
            schedule: .weekdays(hour: 8, minute: 0),
            prompt: "Today's top news",
            needsAccount: false
        ),
        BriefingTemplate(
            title: "ETH price watcher",
            subtitle: "Ethereum price + 24h trend, daily",
            symbol: "chart.line.uptrend.xyaxis",
            tint: .proofVerified,
            kind: .ethPrice,
            schedule: .daily(hour: 9, minute: 0),
            prompt: "What is the ETH price?",
            needsAccount: false
        ),
        BriefingTemplate(
            title: "My NEAR account",
            subtitle: "Balance & holdings for your account",
            symbol: "person.crop.circle.badge.checkmark",
            tint: .brandBlue,
            kind: .nearAccount,
            schedule: .daily(hour: 8, minute: 0),
            prompt: "How is my NEAR account doing?",
            needsAccount: true
        )
    ]

    func makeBriefing(account: String? = nil) -> Briefing {
        Briefing(title: title, prompt: prompt, schedule: schedule, kind: kind, accountID: account)
    }
}

/// Tappable suggestions that create (and immediately run) a briefing for each
/// named use case. NEAR account asks for the account id first.
struct SuggestedBriefingsView: View {
    @ObservedObject var store: BriefingStore
    var onOpen: (Briefing) -> Void = { _ in }

    @State private var pendingAccountTemplate: BriefingTemplate?
    @State private var accountInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.textSecondary)

            VStack(spacing: 0) {
                ForEach(Array(BriefingTemplate.suggested.enumerated()), id: \.element.id) { index, template in
                    Button { tap(template) } label: { row(template) }
                        .buttonStyle(.plain)
                    if index < BriefingTemplate.suggested.count - 1 {
                        Divider().overlay(Color.appHairline).padding(.leading, 52)
                    }
                }
            }
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .alert("Track a NEAR account", isPresented: Binding(
            get: { pendingAccountTemplate != nil },
            set: { if !$0 { pendingAccountTemplate = nil } }
        )) {
            TextField("yourname.near", text: $accountInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Track") { confirmAccount() }
            Button("Cancel", role: .cancel) { pendingAccountTemplate = nil }
        } message: {
            Text("Enter a NEAR mainnet account to track its balance and holdings.")
        }
    }

    private func row(_ template: BriefingTemplate) -> some View {
        HStack(spacing: 12) {
            BriefingIconChip(symbolName: template.symbol, tint: template.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(template.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.actionPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func tap(_ template: BriefingTemplate) {
        if template.needsAccount {
            accountInput = ""
            pendingAccountTemplate = template
        } else {
            create(template.makeBriefing())
        }
    }

    private func confirmAccount() {
        guard let template = pendingAccountTemplate else { return }
        let account = accountInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        pendingAccountTemplate = nil
        guard !account.isEmpty else { return }
        create(template.makeBriefing(account: account))
    }

    private func create(_ briefing: Briefing) {
        store.add(briefing)
        AppHaptics.lightImpact()
        Task {
            await store.run(briefing)
            // Open the post-run briefing so the thread shows the saved result,
            // not the pre-run "No delivery yet" state.
            let updated = store.briefings.first(where: { $0.id == briefing.id }) ?? briefing
            onOpen(updated)
        }
    }
}

private enum BriefingSamples {
    @MainActor
    static let store = BriefingStore(briefings: sampleBriefings)

    // Live briefings — no canned results. They fetch real data through the
    // actual runner (LiveDataService) on runDue, so the demo exercises the real
    // product flow rather than fake widgets.
    static let sampleBriefings: [Briefing] = [
        Briefing(
            title: "Daily news brief",
            prompt: "Today's top news",
            schedule: .weekdays(hour: 8, minute: 0),
            createdAt: Date().addingTimeInterval(-86_400 * 3),
            kind: .dailyNews
        ),
        Briefing(
            title: "ETH price watcher",
            prompt: "What is the ETH price?",
            schedule: .daily(hour: 9, minute: 0),
            createdAt: Date().addingTimeInterval(-86_400 * 2),
            kind: .ethPrice
        ),
        Briefing(
            title: "My NEAR account",
            prompt: "How is my NEAR account doing?",
            schedule: .daily(hour: 8, minute: 0),
            createdAt: Date().addingTimeInterval(-86_400),
            kind: .nearAccount,
            accountID: "root.near"
        )
    ]

    static func sampleWidget(title: String) -> MessageWidget {
        MessageWidget(
            kind: .generic,
            title: title,
            freshness: .fresh,
            time: briefingTimeFormatter.string(from: Date()),
            followUp: "Tell me more",
            note: "Sample briefing result generated locally. Wire a real runner to replace this with a private chat answer."
        )
    }
}

private extension JSONEncoder {
    static var briefing: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var briefing: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private func briefingSort(_ lhs: Briefing, _ rhs: Briefing) -> Bool {
    if lhs.isPaused != rhs.isPaused { return !lhs.isPaused }
    let now = Date()
    let lhsNext = lhs.schedule.nextRun(after: lhs.lastRunAt ?? now) ?? .distantFuture
    let rhsNext = rhs.schedule.nextRun(after: rhs.lastRunAt ?? now) ?? .distantFuture
    if lhsNext != rhsNext { return lhsNext < rhsNext }
    return lhs.createdAt > rhs.createdAt
}

private func relativeNextRun(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}

private var briefingTimeFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateFormat = "h:mma"
    return formatter
}

private func clampedHour(_ hour: Int) -> Int {
    min(max(hour, 0), 23)
}

private func clampedMinute(_ minute: Int) -> Int {
    min(max(minute, 0), 59)
}

private func clampedWeekday(_ weekday: Int) -> Int {
    min(max(weekday, 1), 7)
}

#Preview("Today Section") {
    ScrollView {
        TodaySection(
            store: BriefingSamples.store,
            onOpenBriefing: { _ in },
            onNewBriefing: {}
        )
    }
    .background(Color.appBackground)
}

#Preview("Briefing Editor") {
    BriefingEditorSheet(
        briefing: BriefingSamples.sampleBriefings.first,
        onSave: { _ in },
        onDelete: { _ in }
    )
}
