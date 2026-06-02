import SwiftUI

struct WidgetShell<Content: View>: View {
    let title: String?
    let time: String?
    let freshness: WidgetFreshness?
    let followUpPlaceholder: String?
    var onFollowUp: ((String) -> Void)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || time != nil {
                HStack(spacing: 8) {
                    Image(systemName: "seal.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(freshness == .stale ? Color.proofStale : Color.proofVerified)
                    if let title {
                        Text(title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let time {
                        Text(time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider().overlay(Color.appHairline)
            }

            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

            if onFollowUp != nil {
                Button {
                    onFollowUp?(followUpPlaceholder ?? "Tell me more about this")
                } label: {
                    HStack(spacing: 8) {
                        Text(followUpPlaceholder ?? "Ask about this…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.actionPrimary)
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 8)
                    .frame(height: 38)
                    .background(Color.appSecondaryBackground, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .accessibilityLabel("Ask a follow-up about this widget")
            }
        }
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}

// MARK: Widget bodies

struct WidgetChartBody: View {
    let chart: WidgetChart

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    if let label = chart.label {
                        Text(label.uppercased())
                            .font(.caption2.weight(.medium))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                    }
                    if let value = chart.value {
                        Text(value)
                            .font(.system(.title2, design: .monospaced).weight(.bold))
                            .foregroundStyle(.primary)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    if let delta = chart.delta {
                        Text(delta)
                            .font(.system(.subheadline, design: .monospaced).weight(.medium))
                            .foregroundStyle(widgetTrendColor(chart.trend))
                    }
                    if let timeframe = chart.timeframe {
                        Text(timeframe)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if chart.points.count > 1 {
                ZStack {
                    WidgetSparklineFill(points: chart.points)
                        .fill(
                            LinearGradient(
                                colors: [widgetTrendColor(chart.trend).opacity(0.18), widgetTrendColor(chart.trend).opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    WidgetSparkline(points: chart.points)
                        .stroke(widgetTrendColor(chart.trend), style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 64)
            }

            if let caption = chart.caption {
                HStack(spacing: 6) {
                    Circle()
                        .fill(widgetTrendColor(chart.trend))
                        .frame(width: 6, height: 6)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct WidgetMetricBody: View {
    let metric: WidgetMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label = metric.label {
                Text(label.uppercased())
                    .font(.caption2.weight(.medium))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            Text(metric.value)
                .font(.system(.title, design: .monospaced).weight(.bold))
                .foregroundStyle(.primary)
            if let delta = metric.delta {
                Text(delta)
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .foregroundStyle(widgetTrendColor(metric.trend))
            }
            if let caption = metric.caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct WidgetComparisonBody: View {
    let comparison: WidgetComparison

    private var columnCount: Int { max(comparison.columns.count, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let subtitle = comparison.subtitle {
                Text(subtitle.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                // Header row
                HStack(alignment: .top, spacing: 8) {
                    Text("")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(comparison.columns.enumerated()), id: \.offset) { _, col in
                        Text(col)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 6)

                ForEach(Array(comparison.rows.enumerated()), id: \.offset) { _, row in
                    Divider().overlay(Color.appHairline)
                    HStack(alignment: .top, spacing: 8) {
                        Text(row.label)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(0..<columnCount, id: \.self) { i in
                            let cell = i < row.cells.count ? row.cells[i] : WidgetComparisonCell(text: "—", tone: .off)
                            Text(cell.text)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(widgetToneColor(cell.tone))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

struct WidgetNewsBriefBody: View {
    let brief: WidgetNewsBrief

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let heading = brief.heading {
                Text(heading.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(brief.stories.enumerated()), id: \.offset) { _, story in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.textSecondary)
                        .frame(width: 4, height: 4)
                        .padding(.top, 7)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(story.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 4) {
                            ForEach(Array(story.sources.enumerated()), id: \.offset) { _, src in
                                WidgetSourceDot(source: src)
                            }
                            if let tag = story.tag {
                                Text(tag)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 2)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct WidgetActionPlanBody: View {
    let plan: WidgetActionPlan
    var onFollowUp: ((String) -> Void)? = nil
    var onCreateAppAction: ((WidgetActionItem) -> Void)? = nil
    @State private var selectedAction: WidgetActionItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let heading = widgetNonBlank(plan.heading) {
                Text(heading)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let summary = widgetNonBlank(plan.summary) {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(plan.actions.indices, id: \.self) { index in
                    if index > 0 {
                        Divider().overlay(Color.appHairline)
                    }
                    WidgetActionRow(
                        action: plan.actions[index],
                        onFollowUp: onFollowUp,
                        onPreview: { selectedAction = $0 }
                    )
                        .padding(.vertical, 9)
                }
            }
        }
        .sheet(item: $selectedAction) { action in
            WidgetActionCandidatePreviewSheet(
                action: action,
                canStageCommand: onFollowUp != nil,
                onStageCommand: { command in
                    selectedAction = nil
                    onFollowUp?(command)
                },
                onCreateAppAction: { action in
                    selectedAction = nil
                    onCreateAppAction?(action)
                }
            )
        }
    }
}

