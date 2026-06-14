import SwiftUI

// MARK: - Mapping a live Briefing into deliveries

extension ThreadedBriefingView {
    init(
        briefing: Briefing,
        store: BriefingStore? = nil,
        onAskFollowUp: ((String, String, String?) async -> BriefingFollowUpResult)? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.init(
            title: briefing.title,
            schedule: briefing.schedule.scheduleLabel,
            deliveries: ThreadedBriefingView.deliveries(for: briefing),
            store: store,
            briefingID: briefing.id,
            onAskFollowUp: onAskFollowUp,
            onClose: onClose
        )
    }

    static func deliveries(for briefing: Briefing) -> [BriefingDelivery] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        let runDate = briefing.lastRunAt ?? Date()
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mma"
        let isFailed = briefing.status == .failed
        let scheduledRunLabel = scheduledRunTimeLabel(for: briefing.schedule)
        let failureTitle = "The \(scheduledRunLabel) run didn't start"
        let body = briefing.latestResult.map(summary(for:))
            ?? (isFailed
                ? failureSummary(for: briefing)
                : "No delivery yet — it will appear here after the next scheduled run.")
        let deliveryDate = briefing.lastRunAt ?? briefing.lastFailureAt ?? runDate
        let sourceTags = briefing.latestResult.map(sourceTags(for:)) ?? []
        return [
            BriefingDelivery(
                dayLabel: Calendar.current.isDateInToday(deliveryDate) ? "Today" : formatter.string(from: deliveryDate),
                time: briefing.lastRunAt == nil && !isFailed ? "—" : timeFormatter.string(from: deliveryDate).lowercased(),
                title: isFailed ? failureTitle : "\(formatter.string(from: deliveryDate)) · briefing",
                headline: nil,
                summary: isFailed ? body : nil,
                body: body,
                sources: sourceTags,
                sourceStatusText: sourceTags.isEmpty ? sourceStatusText(for: briefing) : nil,
                unread: briefing.lastRunAt != nil || isFailed,
                isFailure: isFailed,
                widget: briefing.latestResult
            )
        ]
    }

    private static func sourceTags(for widget: MessageWidget) -> [BriefingSourceTag] {
        guard let stories = widget.newsBrief?.stories else { return [] }
        var seen: Set<String> = []
        var tags: [BriefingSourceTag] = []
        for source in stories.flatMap(\.sources) {
            let label = source.domain?.nilIfBlank ?? source.label.nilIfBlank
            guard let label else { continue }
            let key = label.lowercased()
            guard seen.insert(key).inserted else { continue }
            let letter = source.label.nilIfBlank ?? String(label.prefix(1)).uppercased()
            tags.append(BriefingSourceTag(letter: letter, colorHex: source.color ?? "#007AFF"))
        }
        return tags
    }

    private static func sourceStatusText(for briefing: Briefing) -> String? {
        guard briefing.latestResult != nil, briefing.status != .failed else { return nil }
        switch briefing.kind {
        case .ethPrice, .cryptoPrice, .stockPrice, .watchlist:
            return "Market data"
        case .nearAccount:
            return "Account data"
        case .dailyNews, .dailyBrief:
            return "Scheduled run"
        case .customPrompt:
            let prompt = briefing.prompt.lowercased()
            if prompt.contains("web search") ||
                prompt.contains("current source") ||
                prompt.contains("fresh source") ||
                prompt.contains("live source") ||
                prompt.contains("market data") {
                return "Current-source run"
            }
            return nil
        }
    }

    private static func scheduledRunTimeLabel(for schedule: BriefingSchedule) -> String {
        guard let time = schedule.timeComponents else { return "scheduled" }
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        guard let date = Calendar.current.date(from: components) else { return "scheduled" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).lowercased()
    }

    private static func failureSummary(for briefing: Briefing) -> String {
        let failure = briefing.lastFailureMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if looksLikeSignInFailure(failure) {
            return "The plan wasn't signed in when the brief was due. Re-run now, or check the plan's sign-in to resume the schedule."
        }
        if !failure.isEmpty {
            return failure
        }
        return "The last scheduled run didn't produce a result. Re-run now, or check the plan's route and sign-in."
    }

    private static func looksLikeSignInFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("sign-in") ||
            lower.contains("sign in") ||
            lower.contains("signed in") ||
            lower.contains("not signed") ||
            lower.contains("login") ||
            lower.contains("not logged in") ||
            lower.contains("unauthorized") ||
            lower.contains("authorization")
    }

    static func summary(for widget: MessageWidget) -> String {
        if let chart = widget.chart, let value = chart.value {
            return [chart.label, value, chart.delta].compactMap { $0 }.joined(separator: " · ")
        }
        if let metric = widget.metric {
            return [metric.label, metric.value, metric.delta].compactMap { $0 }.joined(separator: " · ")
        }
        if let brief = widget.newsBrief, !brief.stories.isEmpty {
            return brief.stories.prefix(3).map(\.title).joined(separator: " · ")
        }
        if let plan = widget.actionPlan, !plan.actions.isEmpty {
            return plan.heading ?? plan.actions.prefix(3).map(\.title).joined(separator: " · ")
        }
        if let comparison = widget.comparison, let subtitle = comparison.subtitle {
            return subtitle
        }
        return widget.note ?? widget.title ?? "Briefing delivered."
    }
}
