import SwiftUI

extension HomeOrchestrationPlanner {
    static func surfaceSubtitle(
        liveBriefingCount: Int,
        projectCount: Int,
        isCouncilAvailable: Bool,
        isAgentAvailable: Bool
    ) -> String {
        var parts: [String] = []
        if liveBriefingCount > 0 {
            parts.append("\(liveBriefingCount) live")
        }
        if projectCount > 0 {
            parts.append(projectCount == 1 ? "1 Project" : "\(projectCount) Projects")
        }
        if isCouncilAvailable {
            parts.append("Council")
        }
        if isAgentAvailable {
            parts.append("Agent")
        }
        return parts.isEmpty ? "Stage the next run" : parts.joined(separator: " / ")
    }

    static func widgetSummary(_ widget: MessageWidget?) -> String? {
        guard let widget else { return nil }
        switch widget.kind {
        case .metric:
            if let metric = widget.metric {
                let delta = metric.delta?.nilIfBlank
                return [metric.value.nilIfBlank, delta, metric.caption?.nilIfBlank].compactMap { $0 }.joined(separator: " / ").nilIfBlank
            }
        case .chart:
            if let chart = widget.chart {
                return [chart.value?.nilIfBlank, chart.delta?.nilIfBlank, chart.caption?.nilIfBlank].compactMap { $0 }.joined(separator: " / ").nilIfBlank
            }
        case .comparison:
            return widget.comparison?.subtitle?.nilIfBlank ?? widget.note?.nilIfBlank
        case .newsBrief:
            return widget.newsBrief?.stories.first?.title.nilIfBlank ?? widget.newsBrief?.heading?.nilIfBlank
        case .actionPlan:
            return widget.actionPlan?.heading?.nilIfBlank ?? widget.actionPlan?.actions.first?.title.nilIfBlank
        case .generic:
            return widget.note?.nilIfBlank
        }
        return widget.note?.nilIfBlank
    }

    static func projectContextLabel(_ project: ChatProject) -> String {
        let sourceCount = project.attachments.count + project.links.count
        var parts: [String] = []
        if sourceCount > 0 {
            parts.append(sourceCount == 1 ? "1 source" : "\(sourceCount) sources")
        }
        if !project.notes.isEmpty {
            parts.append(project.notes.count == 1 ? "1 note" : "\(project.notes.count) notes")
        }
        return parts.isEmpty ? "Ready for context" : parts.joined(separator: " / ")
    }

    static func projectDetail(_ project: ChatProject) -> String {
        if let memory = project.memorySummary.nilIfBlank {
            return memory
        }
        if let instructions = project.instructions.nilIfBlank {
            return instructions
        }
        return "Open files, links, notes, and task context."
    }

    static func scheduleSubtitle(_ briefing: Briefing) -> String {
        if briefing.isPaused {
            return "Paused"
        }
        if briefing.snoozedUntil != nil {
            return "Snoozed"
        }
        if briefing.latestResult != nil {
            return "Latest result ready"
        }
        return "Scheduled"
    }

    static func tone(for widget: MessageWidget?) -> HomeOrchestrationTone {
        switch widget?.kind {
        case .metric:
            return tone(for: widget?.metric?.trend)
        case .chart:
            return tone(for: widget?.chart?.trend)
        case .newsBrief:
            return .blue
        case .actionPlan:
            return .green
        case .comparison:
            return .violet
        case .generic, .none:
            return .neutral
        }
    }

    static func tone(for trend: WidgetTrend?) -> HomeOrchestrationTone {
        switch trend {
        case .up:
            return .green
        case .down:
            return .red
        case .flat, .none:
            return .neutral
        }
    }

    static func symbolName(for kind: WidgetKind?) -> String {
        switch kind {
        case .chart:
            return "chart.xyaxis.line"
        case .metric:
            return "number"
        case .comparison:
            return "tablecells"
        case .newsBrief:
            return "newspaper"
        case .actionPlan:
            return "checklist"
        case .generic, .none:
            return "doc.text"
        }
    }

    static func timestampText(for createdAt: TimeInterval?) -> String {
        guard let createdAt else { return "recent" }
        let elapsed = max(0, Date().timeIntervalSince(Date(timeIntervalSince1970: createdAt)))
        if elapsed < 60 {
            return "now"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60))m"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3600))h"
        }
        return Date(timeIntervalSince1970: createdAt).formatted(.dateTime.month(.abbreviated).day())
    }
}
