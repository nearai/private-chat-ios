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
        let body = briefing.latestResult.map(summary(for:))
            ?? "No delivery yet — it will appear here after the next scheduled run."
        return [
            BriefingDelivery(
                dayLabel: Calendar.current.isDateInToday(runDate) ? "Today" : formatter.string(from: runDate),
                time: briefing.lastRunAt == nil ? "—" : timeFormatter.string(from: runDate).lowercased(),
                title: "\(formatter.string(from: runDate)) · briefing",
                body: body,
                unread: briefing.lastRunAt != nil,
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
