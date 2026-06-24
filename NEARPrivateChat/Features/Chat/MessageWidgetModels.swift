import Foundation

// MARK: - Generative widgets
//
// A typed, render-ready payload attached to an assistant message so the answer's
// *shape* matches the question's shape: a price question returns a chart, a
// comparison returns a table, a digest returns a story list. The model emits a
// fenced ```near-widget JSON block; `MessageWidget.extract` parses it client-side
// and strips it from the displayed prose. Decoders are deliberately forgiving —
// model-emitted JSON varies, and a malformed block must degrade to plain text,
// never crash.

enum WidgetKind: String, Codable, Hashable {
    case chart
    case metric
    case comparison
    case newsBrief
    case actionPlan
    case generic

    init(from decoder: Decoder) throws {
        let raw = ((try? decoder.singleValueContainer().decode(String.self)) ?? "")
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch raw {
        case "chart", "sparkline", "price", "trend", "line": self = .chart
        case "metric", "stat", "number", "kpi", "gauge": self = .metric
        case "comparison", "compare", "table", "matrix", "versus", "vs": self = .comparison
        case "newsbrief", "news", "brief", "digest", "headlines", "stories": self = .newsBrief
        case "actionplan", "actions", "action", "tasks", "nextactions", "nextsteps": self = .actionPlan
        default: self = .generic
        }
    }
}

enum WidgetTrend: String, Codable, Hashable {
    case up, down, flat

    init(from decoder: Decoder) throws {
        let raw = ((try? decoder.singleValueContainer().decode(String.self)) ?? "").lowercased()
        switch raw {
        case "up", "rise", "rising", "positive", "gain", "bull": self = .up
        case "down", "fall", "falling", "negative", "loss", "drop", "bear": self = .down
        default: self = .flat
        }
    }
}

enum WidgetTone: String, Codable, Hashable {
    case neutral, good, warn, bad, off

    init(from decoder: Decoder) throws {
        let raw = ((try? decoder.singleValueContainer().decode(String.self)) ?? "").lowercased()
        switch raw {
        case "good", "ok", "yes", "pass", "positive", "up", "supported": self = .good
        case "warn", "warning", "preview", "partial", "caution": self = .warn
        case "bad", "negative", "down", "error", "fail", "danger": self = .bad
        case "off", "no", "none", "na", "n/a", "missing", "unsupported": self = .off
        default: self = .neutral
        }
    }
}

enum WidgetFreshness: String, Codable, Hashable {
    case fresh, stale

    init(from decoder: Decoder) throws {
        let raw = ((try? decoder.singleValueContainer().decode(String.self)) ?? "").lowercased()
        self = (raw == "stale" || raw == "old" || raw == "cached") ? .stale : .fresh
    }
}

struct WidgetChart: Codable, Hashable {
    var label: String? = nil       // "ETH / USD"
    var value: String? = nil       // "$3,124"
    var delta: String? = nil       // "−$74.20 (−2.3%)"
    var trend: WidgetTrend? = nil
    var points: [Double] = []      // sparkline samples, oldest → newest
    var caption: String? = nil     // "Threshold $3,180 broken at 9:47am"
    var timeframe: String? = nil   // "past 1h"
}

extension WidgetChart {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try? c.decode(String.self, forKey: .label),
            value: try? c.decode(String.self, forKey: .value),
            delta: try? c.decode(String.self, forKey: .delta),
            trend: try? c.decode(WidgetTrend.self, forKey: .trend),
            points: (try? c.decode([Double].self, forKey: .points)) ?? [],
            caption: try? c.decode(String.self, forKey: .caption),
            timeframe: try? c.decode(String.self, forKey: .timeframe)
        )
    }
}

struct WidgetMetric: Codable, Hashable {
    var label: String? = nil
    var value: String = ""
    var delta: String? = nil
    var trend: WidgetTrend? = nil
    var caption: String? = nil
}

extension WidgetMetric {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try? c.decode(String.self, forKey: .label),
            value: (try? c.decode(String.self, forKey: .value)) ?? "",
            delta: try? c.decode(String.self, forKey: .delta),
            trend: try? c.decode(WidgetTrend.self, forKey: .trend),
            caption: try? c.decode(String.self, forKey: .caption)
        )
    }
}

struct WidgetComparisonCell: Codable, Hashable {
    var text: String = ""
    var tone: WidgetTone? = nil
}

extension WidgetComparisonCell {
    init(from decoder: Decoder) throws {
        // Accept a bare string ("AES-128 XEX") or an object ({text, tone}).
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self) {
            self.init(text: s, tone: nil)
            return
        }
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        self.init(
            text: (try? c?.decode(String.self, forKey: .text)) ?? "",
            tone: try? c?.decode(WidgetTone.self, forKey: .tone)
        )
    }
}

struct WidgetComparisonRow: Codable, Hashable {
    var label: String = ""
    var cells: [WidgetComparisonCell] = []
}

extension WidgetComparisonRow {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: (try? c.decode(String.self, forKey: .label)) ?? "",
            cells: (try? c.decode([WidgetComparisonCell].self, forKey: .cells)) ?? []
        )
    }
}

struct WidgetComparison: Codable, Hashable {
    var subtitle: String? = nil    // "SEV-SNP vs TDX"
    var columns: [String] = []
    var rows: [WidgetComparisonRow] = []
}

extension WidgetComparison {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            subtitle: try? c.decode(String.self, forKey: .subtitle),
            columns: (try? c.decode([String].self, forKey: .columns)) ?? [],
            rows: (try? c.decode([WidgetComparisonRow].self, forKey: .rows)) ?? []
        )
    }
}

struct WidgetNewsSource: Codable, Hashable {
    var label: String = ""         // favicon initial, e.g. "W"
    var color: String? = nil       // hex, e.g. "#ff7e1c"
    var domain: String? = nil
}

extension WidgetNewsSource {
    var faviconIdentity: String? {
        SourceFaviconResolver.sourceIdentity(domain: domain, label: label)
    }

    var displaySourceText: String {
        if let knownDisplayName = SourceFaviconResolver.displayName(for: faviconIdentity, fallback: label.nilIfBlank),
           SourceFaviconResolver.canonicalFaviconHost(for: faviconIdentity) != nil {
            return knownDisplayName
        }
        if let label = label.nilIfBlank,
           label.count > 1,
           label.localizedCaseInsensitiveCompare("source") != .orderedSame {
            return label
        }
        return SourceFaviconResolver.displayName(for: faviconIdentity, fallback: label.nilIfBlank) ?? "Source"
    }

    var fallbackMark: String {
        label.nilIfBlank ?? domain?.nilIfBlank ?? "S"
    }

    var allowsNetworkFavicon: Bool {
        if let host = SourceFaviconResolver.canonicalFaviconHost(for: domain),
           URLSecurity.isPublicHost(host) {
            return true
        }
        if let host = SourceFaviconResolver.canonicalFaviconHost(for: label),
           URLSecurity.isPublicHost(host) {
            return true
        }
        return false
    }
}

extension WidgetNewsSource {
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self) {
            self.init(label: String(s.prefix(1)).uppercased(), color: nil, domain: s)
            return
        }
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: (try? c?.decode(String.self, forKey: .label)) ?? "",
            color: try? c?.decode(String.self, forKey: .color),
            domain: try? c?.decode(String.self, forKey: .domain)
        )
    }
}

struct WidgetNewsStory: Codable, Hashable {
    var title: String = ""
    var tag: String? = nil
    var sources: [WidgetNewsSource] = []
    var url: String? = nil
}

extension WidgetNewsStory {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            title: (try? c.decode(String.self, forKey: .title)) ?? "",
            tag: try? c.decode(String.self, forKey: .tag),
            sources: (try? c.decode([WidgetNewsSource].self, forKey: .sources)) ?? [],
            url: try? c.decode(String.self, forKey: .url)
        )
    }
}

struct WidgetNewsBrief: Codable, Hashable {
    var heading: String? = nil     // "Today · 3 stories"
    var stories: [WidgetNewsStory] = []
}

extension WidgetNewsBrief {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            heading: try? c.decode(String.self, forKey: .heading),
            stories: (try? c.decode([WidgetNewsStory].self, forKey: .stories)) ?? []
        )
    }
}

struct WidgetActionItem: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var title: String = ""
    var type: String? = nil        // tracker, reminder, calendar, task, decision, question
    var detail: String? = nil
    var schedule: String? = nil
    var command: String? = nil     // composer-safe command to stage, never auto-run
    var source: String? = nil      // filename, row, thread, or project note provenance
    var date: String? = nil
    var time: String? = nil
    var duration: String? = nil
    var recurrence: String? = nil
    var timezone: String? = nil
    var location: String? = nil
    var attendees: [String] = []
    var missingFields: [String] = []
    var confidence: Double? = nil
    var tone: WidgetTone? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, type, detail, schedule, command
        case source, date, time, duration, recurrence, timezone, location, attendees, confidence, tone
        case missingFields = "missing_fields"
    }
}

extension WidgetActionItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString,
            title: (try? c.decode(String.self, forKey: .title)) ?? "",
            type: try? c.decode(String.self, forKey: .type),
            detail: try? c.decode(String.self, forKey: .detail),
            schedule: try? c.decode(String.self, forKey: .schedule),
            command: try? c.decode(String.self, forKey: .command),
            source: try? c.decode(String.self, forKey: .source),
            date: try? c.decode(String.self, forKey: .date),
            time: try? c.decode(String.self, forKey: .time),
            duration: try? c.decode(String.self, forKey: .duration),
            recurrence: try? c.decode(String.self, forKey: .recurrence),
            timezone: try? c.decode(String.self, forKey: .timezone),
            location: try? c.decode(String.self, forKey: .location),
            attendees: (try? c.decode([String].self, forKey: .attendees)) ?? [],
            missingFields: (try? c.decode([String].self, forKey: .missingFields)) ?? [],
            confidence: try? c.decode(Double.self, forKey: .confidence),
            tone: try? c.decode(WidgetTone.self, forKey: .tone)
        )
    }
}
