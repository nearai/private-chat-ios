import Foundation
import SwiftUI

enum BriefingKind: String, Codable, Hashable {
    case customPrompt
    case ethPrice
    case cryptoPrice
    case stockPrice
    case watchlist
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
            return "You don’t have any automations yet. Try “turn this table into reminders” or “every weekday, check for new sources on this project.”"
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
        let subtitle = count == 0 ? "No automations yet" : "\(count) automation\(count == 1 ? "" : "s") · latest signals"
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
    var timeZoneIdentifier: String
    var lastFailureAt: Date?
    var lastFailureMessage: String?
    /// Run a multi-model council + synthesis on each scheduled run (customPrompt
    /// only; live-data kinds are single API fetches where council is meaningless).
    var council: Bool
    /// When set, the tracker only delivers on runs where the condition is met
    /// (e.g. a price threshold). nil = a plain recurring briefing.
    var condition: BriefingCondition?
    /// Numeric values recorded across runs (oldest → newest), so a tracker can
    /// chart its trend over time. Empty for trackers whose runs aren't numeric.
    var history: [TrackerSample]
    /// User-steered: pinned trackers sort to the top of Today.
    var isPinned: Bool
    /// User-steered: skip scheduled runs until this time (snooze), then resume.
    var snoozedUntil: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, prompt, schedule, isPaused, createdAt, lastRunAt, latestResult, kind, accountID, timeZoneIdentifier, lastFailureAt, lastFailureMessage, council, condition, history, isPinned, snoozedUntil
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
        timeZoneIdentifier: String = TimeZone.current.identifier,
        lastFailureAt: Date? = nil,
        lastFailureMessage: String? = nil,
        council: Bool = false,
        condition: BriefingCondition? = nil,
        history: [TrackerSample] = [],
        isPinned: Bool = false,
        snoozedUntil: Date? = nil
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
        self.timeZoneIdentifier = timeZoneIdentifier
        self.lastFailureAt = lastFailureAt
        self.lastFailureMessage = lastFailureMessage
        self.council = council
        self.condition = condition
        self.history = history
        self.isPinned = isPinned
        self.snoozedUntil = snoozedUntil
    }

    /// True when this tracker is gated on a condition (a threshold alert).
    var isConditional: Bool { condition != nil }

    var status: BriefingStatus {
        if isPaused { return .paused }
        if lastFailureAt != nil, latestResult == nil { return .failed }
        if latestResult != nil { return .active }
        return .scheduled
    }

    var scheduleCalendar: Calendar {
        var calendar = Calendar.current
        if let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            calendar.timeZone = timeZone
        }
        return calendar
    }

    var timeZoneLabel: String {
        TimeZone(identifier: timeZoneIdentifier)?.identifier ?? TimeZone.current.identifier
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
            timeZoneIdentifier: (try? c.decode(String.self, forKey: .timeZoneIdentifier)) ?? TimeZone.current.identifier,
            lastFailureAt: try? c.decode(Date.self, forKey: .lastFailureAt),
            lastFailureMessage: try? c.decode(String.self, forKey: .lastFailureMessage),
            council: (try? c.decode(Bool.self, forKey: .council)) ?? false,
            condition: try? c.decode(BriefingCondition.self, forKey: .condition),
            history: (try? c.decode([TrackerSample].self, forKey: .history)) ?? [],
            isPinned: (try? c.decode(Bool.self, forKey: .isPinned)) ?? false,
            snoozedUntil: try? c.decode(Date.self, forKey: .snoozedUntil)
        )
    }
}

enum BriefingStatus: String, Codable, Hashable {
    case active
    case failed
    case live
    case scheduled
    case paused
}

