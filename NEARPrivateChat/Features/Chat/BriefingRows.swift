import SwiftUI

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
        case .actionPlan:
            Text(widget?.actionPlan?.heading ?? widget?.actionPlan?.actions.first?.title ?? "Actions ready")
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
        if briefing.status == .failed { return "Failed" }
        guard let widget else { return briefing.status == .active ? "Active" : "Scheduled" }
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
        case .actionPlan:
            let count = widget.actionPlan?.actions.count ?? 0
            return count == 1 ? "1 action" : "\(count) actions"
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
        switch briefing.status {
        case .paused:
            return "paused"
        case .failed:
            return briefing.lastFailureMessage ?? "last run failed"
        case .active, .live, .scheduled:
            break
        }
        guard let next = briefing.schedule.nextRun(after: briefing.lastRunAt ?? Date(), calendar: briefing.scheduleCalendar) else {
            return "not scheduled"
        }
        let suffix = briefing.timeZoneLabel == TimeZone.current.identifier ? "" : " · \(briefing.timeZoneLabel)"
        return "next run \(relativeNextRun(next))\(suffix)"
    }
}

struct TodayEmptyState: View {
    var onNewBriefing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BriefingIconChip(symbolName: "calendar.badge.plus", tint: Color.actionPrimary)
            Text("No automations yet")
                .font(.headline)
            Text("Create a recurring check from any source, note, table, or chat.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onNewBriefing) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("New workflow")
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

struct BriefingIconChip: View {
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
        case .actionPlan: return "checklist"
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
