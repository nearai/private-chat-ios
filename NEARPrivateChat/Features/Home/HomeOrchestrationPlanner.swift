import SwiftUI

enum HomeOrchestrationPlanner {
    static func make(
        briefings: [Briefing],
        projects: [ChatProject],
        conversations: [ConversationSummary],
        selectedProjectID: String?,
        isStreaming: Bool,
        routeLabel: String,
        isCouncilModeEnabled: Bool,
        defaultCouncilModelCount: Int,
        councilModelNames: [String],
        hostedAgentAvailable: Bool,
        mobileAgentAvailable: Bool
    ) -> HomeOrchestrationPlan {
        let sortedBriefings = sorted(briefings: briefings)
        let sortedProjects = sorted(projects: projects, selectedProjectID: selectedProjectID)
        let liveBriefings = sortedBriefings.filter { $0.latestResult != nil }

        var items: [HomeOrchestrationItem] = []
        if isStreaming {
            items.append(activeRunItem(routeLabel: routeLabel))
        }

        items.append(contentsOf: liveBriefings.prefix(2).map(briefingItem))

        let selectedCouncilModelCount = councilModelNames
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        let isCouncilAvailableForHome = isCouncilModeEnabled
            ? selectedCouncilModelCount >= 2
            : defaultCouncilModelCount >= 2

        if let selectedProject = sortedProjects.first(where: { $0.id == selectedProjectID }) {
            items.append(projectItem(selectedProject))
        }

        let scheduledItems = sortedBriefings.prefix(4).map(scheduleItem)
        let subtitle = surfaceSubtitle(
            liveBriefingCount: liveBriefings.count,
            projectCount: projects.count,
            isCouncilAvailable: isCouncilAvailableForHome,
            isAgentAvailable: hostedAgentAvailable || mobileAgentAvailable
        )

        return HomeOrchestrationPlan(
            subtitle: subtitle,
            liveItems: items,
            scheduledItems: scheduledItems,
            commands: []
        )
    }

    private static func activeRunItem(routeLabel: String) -> HomeOrchestrationItem {
        HomeOrchestrationItem(
            id: "active-run",
            kind: .agent,
            title: "Active run",
            subtitle: routeLabel,
            detail: "Agent turn is still running.",
            statusText: "running",
            symbolName: "waveform.path.ecg",
            tone: .green,
            action: .stagePrompt(HomeStagedPrompt(
                prompt: "When the run finishes, summarize what changed, what needs input, and the safest next action.",
                banner: "Follow-up staged after the run."
            ))
        )
    }

    private static func briefingItem(_ briefing: Briefing) -> HomeOrchestrationItem {
        let widget = briefing.latestResult
        return HomeOrchestrationItem(
            id: "briefing-\(briefing.id.uuidString)",
            kind: .briefing,
            title: briefing.title,
            subtitle: widget?.title?.nilIfBlank ?? "Live briefing",
            detail: widgetSummary(widget) ?? "Open the brief and ask a follow-up.",
            statusText: widget?.time?.nilIfBlank ?? "live",
            symbolName: symbolName(for: widget?.kind),
            tone: tone(for: widget),
            action: .openBriefing(briefing.id)
        )
    }

    private static func projectItem(_ project: ChatProject) -> HomeOrchestrationItem {
        HomeOrchestrationItem(
            id: "project-\(project.id)",
            kind: .project,
            title: project.name,
            subtitle: projectContextLabel(project),
            detail: projectDetail(project),
            statusText: project.conversationIDs.isEmpty ? "project" : "\(project.conversationIDs.count) chats",
            symbolName: project.projectIconName,
            tone: .blue,
            action: .openProject(project.id)
        )
    }

    private static func scheduleItem(_ briefing: Briefing) -> HomeOrchestrationScheduleItem {
        HomeOrchestrationScheduleItem(
            id: briefing.id,
            title: briefing.title,
            subtitle: scheduleSubtitle(briefing),
            scheduleLabel: briefing.schedule.scheduleLabel,
            symbolName: symbolName(for: briefing.latestResult?.kind),
            tone: tone(for: briefing.latestResult),
            action: .openBriefing(briefing.id)
        )
    }

    private static func sorted(briefings: [Briefing]) -> [Briefing] {
        briefings.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            let lhsDate = lhs.lastRunAt ?? lhs.createdAt
            let rhsDate = rhs.lastRunAt ?? rhs.createdAt
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func sorted(projects: [ChatProject], selectedProjectID: String?) -> [ChatProject] {
        projects.sorted { lhs, rhs in
            if lhs.id == selectedProjectID {
                return true
            }
            if rhs.id == selectedProjectID {
                return false
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}
