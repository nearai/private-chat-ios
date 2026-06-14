import SwiftUI

// MARK: - Generative widget cards
//
// Renders a MessageWidget as a native card whose shape matches the answer:
// chart, metric, comparison table, or news digest. Each card carries a meta
// strip (freshness + source + time) and a micro-composer for scoped follow-up.
// Chrome matches SourceCard / IronclawApprovalCard: panel bg, 16r, 1px border.

struct MessageWidgetCard: View {
    let widget: MessageWidget
    var onFollowUp: ((String) -> Void)? = nil
    var onCreateAppAction: ((WidgetActionItem) -> Void)? = nil

    var body: some View {
        // A widget whose kind has no usable payload would otherwise render as a
        // bare title shell with an empty body. Render nothing instead. Model
        // extraction already filters these; this guards persisted/programmatic
        // widgets that reach the card directly.
        if widget.hasRenderableBody {
            card
        }
    }

    private var card: some View {
        WidgetShell(
            title: widget.title,
            time: widget.time,
            freshness: widget.freshness,
            followUpPlaceholder: widget.followUpLabel,
            followUpDraft: widget.followUpDraft,
            onFollowUp: onFollowUp
        ) {
            switch widget.kind {
            case .chart:
                if let chart = widget.chart { WidgetChartBody(chart: chart) }
            case .metric:
                if let metric = widget.metric { WidgetMetricBody(metric: metric) }
            case .comparison:
                if let comparison = widget.comparison { WidgetComparisonBody(comparison: comparison) }
            case .newsBrief:
                if let brief = widget.newsBrief { WidgetNewsBriefBody(brief: brief) }
            case .actionPlan:
                if let plan = widget.actionPlan {
                    WidgetActionPlanBody(
                        plan: plan,
                        onFollowUp: onFollowUp,
                        onCreateAppAction: onCreateAppAction
                    )
                }
            case .generic:
                if let note = widget.note { WidgetGenericBody(note: note) }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .accessibilityIdentifier("message.widget.\(widget.kind.rawValue)")
    }
}
