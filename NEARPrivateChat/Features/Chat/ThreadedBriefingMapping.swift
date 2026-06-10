import SwiftUI

// MARK: - Mapping a live Briefing into deliveries

extension ThreadedBriefingView {
    init(
        briefing: Briefing,
        store: BriefingStore? = nil,
        onAskFollowUp: ((String, String) async -> BriefingFollowUpResult)? = nil,
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
        let body = briefing.latestResult.map(summary(for:))
            ?? (isFailed
                ? briefing.lastFailureMessage ?? "Last run failed before producing a result."
                : "No delivery yet — it will appear here after the next scheduled run.")
        let deliveryDate = briefing.lastRunAt ?? briefing.lastFailureAt ?? runDate
        return [
            BriefingDelivery(
                dayLabel: Calendar.current.isDateInToday(deliveryDate) ? "Today" : formatter.string(from: deliveryDate),
                time: briefing.lastRunAt == nil && !isFailed ? "—" : timeFormatter.string(from: deliveryDate).lowercased(),
                title: isFailed ? "\(formatter.string(from: deliveryDate)) · run failed" : "\(formatter.string(from: deliveryDate)) · briefing",
                headline: isFailed ? "Run failed" : nil,
                // BotDeliveryRow renders summary (not body) when a headline is
                // present, so the failure reason must ride in summary.
                summary: isFailed ? body : nil,
                body: body,
                unread: briefing.lastRunAt != nil || isFailed,
                isFailure: isFailed,
                widget: briefing.latestResult
            )
        ]
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
