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
        mobileAgentAvailable: Bool,
        setupPlan: AppSetupPlan? = nil,
        includesSetupDefaultsCommand: Bool = false
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

    private static func councilItem(
        isEnabled: Bool,
        defaultModelCount: Int,
        modelNames: [String]
    ) -> HomeOrchestrationItem {
        let names = modelNames.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let selectedCount = names.count
        let needsMoreSelectedModels = isEnabled && selectedCount < 2
        let subtitle: String
        if !isEnabled {
            subtitle = defaultModelCount > 1 ? "\(defaultModelCount) models available" : "Set up Council"
        } else if names.isEmpty {
            subtitle = defaultModelCount > 1 ? "\(defaultModelCount) models available" : "Multi-model route"
        } else {
            let count = min(selectedCount, 3)
            subtitle = count == 1 ? "1 model selected" : "\(count) models selected"
        }

        let action: HomeOrchestrationAction = needsMoreSelectedModels
            ? .editCouncilLineup
            : isEnabled
            ? .stagePrompt(HomeStagedPrompt(
                prompt: "Run a Council pass on this decision. Have each model state agreement, dissent, risk, and a recommended move, then synthesize.",
                banner: "Council prompt ready."
            ))
            : .useAutoCouncil

        return HomeOrchestrationItem(
            id: "council-room",
            kind: .council,
            title: needsMoreSelectedModels ? "Finish Council setup" : (isEnabled ? "Council room" : "Recommended Council"),
            subtitle: subtitle,
            detail: needsMoreSelectedModels
                ? "Add at least one more model before running Council."
                : isEnabled ? "Compare model views before committing." : "Enable the recommended multi-model lineup.",
            statusText: needsMoreSelectedModels ? "Needs 2" : (isEnabled ? "Ready" : "Available"),
            symbolName: needsMoreSelectedModels ? "person.badge.plus" : "person.3.fill",
            tone: needsMoreSelectedModels ? .amber : .violet,
            action: action
        )
    }

    private static func agentItem(
        hostedAvailable: Bool,
        mobileAvailable: Bool,
        selectedProject: ChatProject?
    ) -> HomeOrchestrationItem {
        let route = hostedAvailable ? "Hosted IronClaw" : "Phone Agent"
        let projectName = selectedProject?.name.nilIfBlank
        // Concrete first suggestion from the project's actual content beats a
        // generic planning template.
        let suggestion = AgentSuggestionPlanner.suggestions(
            projectName: projectName,
            attachmentNames: selectedProject?.attachments.map(\.name) ?? [],
            linkHosts: selectedProject?.links.compactMap(\.host) ?? [],
            recentConversationTitles: []
        ).first
        let detail = suggestion?.title ?? "Plan code, research, and tool work before sending."
        let prompt = suggestion?.prompt ?? "Draft a short, concrete work plan: the goal as you understand it, the next three steps, and what you need from me."

        return HomeOrchestrationItem(
            id: "agent-builder",
            kind: .agent,
            title: "Agent task",
            subtitle: route,
            detail: detail,
            statusText: hostedAvailable ? "Connected" : (mobileAvailable ? "Phone route" : "Set up"),
            symbolName: hostedAvailable ? "terminal" : "iphone",
            tone: .blue,
            action: .stagePrompt(HomeStagedPrompt(
                prompt: prompt,
                projectID: selectedProject?.id,
                banner: "Agent plan ready."
            ))
        )
    }

    private static func setupSkillItem(
        skill: IronclawSkillProfile,
        setupPlan: AppSetupPlan,
        selectedProject: ChatProject?
    ) -> HomeOrchestrationItem {
        let projectName = setupPlan.starterProjectName ?? selectedProject?.name
        return HomeOrchestrationItem(
            id: "setup-skill-\(skill.id)",
            kind: .setup,
            title: skill.title,
            subtitle: "Saved setup skill",
            detail: skill.summary,
            statusText: "saved",
            symbolName: skill.symbolName,
            tone: .green,
            action: .stagePrompt(HomeStagedPrompt(
                prompt: skill.missionPrompt(seed: setupPlan.goalText, projectName: projectName),
                projectID: selectedProject?.id,
                banner: "\(skill.title) prompt ready."
            ))
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

    private static func chatItem(_ conversation: ConversationSummary) -> HomeOrchestrationItem {
        HomeOrchestrationItem(
            id: "chat-\(conversation.id)",
            kind: .chat,
            title: conversation.title,
            subtitle: "Recent chat",
            detail: "Open the thread and continue from the last turn.",
            statusText: timestampText(for: conversation.createdAt),
            symbolName: "bubble.left.and.bubble.right",
            tone: .neutral,
            action: .openConversation(conversation.id)
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

    private static func commandItems(
        selectedProject: ChatProject?,
        isCouncilModeEnabled: Bool,
        selectedCouncilModelCount: Int,
        defaultCouncilModelCount: Int,
        agentAvailable: Bool,
        includesSetupDefaultsCommand: Bool
    ) -> [HomeOrchestrationCommand] {
        var commands = [
            HomeOrchestrationCommand(
                id: "actions",
                title: "Find next actions",
                symbolName: "checklist",
                action: .stagePrompt(HomeStagedPrompt(
                    prompt: selectedProject.map {
                        "Use \($0.name) context to surface next moves: trackers, reminders, calendar items, decisions, risks, open questions, and things I should care about. Include structured fields where known (source, date, time, recurrence, timezone, attendees, confidence), missing_fields, and exact commands. Emit a near-widget action_plan when helpful. Preview before creating anything."
                    } ?? "Surface next moves from this context: trackers, reminders, calendar items, decisions, risks, open questions, and things I should care about. Include structured fields where known (source, date, time, recurrence, timezone, attendees, confidence), missing_fields, and exact commands. Emit a near-widget action_plan when helpful. Preview before creating anything.",
                    projectID: selectedProject?.id,
                    banner: "Action scan prompt ready."
                ))
            ),
            HomeOrchestrationCommand(
                id: "brief",
                title: "Create workflow",
                symbolName: "doc.text.magnifyingglass",
                action: .newBriefing
            ),
            HomeOrchestrationCommand(
                id: "review",
                title: "Review thread",
                symbolName: "text.magnifyingglass",
                action: .stagePrompt(HomeStagedPrompt(
                    prompt: "Review this thread for decisions, risks, missing tests, and the next concrete follow-up.",
                    projectID: selectedProject?.id,
                    banner: "Review prompt ready."
                ))
            ),
            HomeOrchestrationCommand(
                id: "patch",
                title: "Plan changes",
                symbolName: "hammer",
                action: .stagePrompt(HomeStagedPrompt(
                    prompt: selectedProject.map {
                        "Use \($0.name) context to plan a safe patch: files to inspect, likely changes, tests, and risks before editing."
                    } ?? "Plan a safe patch: context to inspect, likely changes, tests, and risks before editing.",
                    projectID: selectedProject?.id,
                    banner: "Patch plan ready."
                ))
            )
        ]

        if includesSetupDefaultsCommand {
            commands.insert(
                HomeOrchestrationCommand(
                    id: "setup-defaults",
                    title: "Tune defaults",
                    symbolName: "slider.horizontal.3",
                    action: .runSetupDefaults
                ),
                at: 2
            )
        }

        if isCouncilModeEnabled, selectedCouncilModelCount < 2 {
            commands.append(
                HomeOrchestrationCommand(
                    id: "council",
                    title: "Edit Council",
                    symbolName: "person.badge.plus",
                    action: .editCouncilLineup
                )
            )
        } else if isCouncilModeEnabled {
            commands.append(
                HomeOrchestrationCommand(
                    id: "council",
                    title: "Run Council",
                    symbolName: "person.3.fill",
                    action: .stagePrompt(HomeStagedPrompt(
                        prompt: "Run a Council comparison on this: agreement, dissent, risk, and a recommended decision.",
                        projectID: selectedProject?.id,
                        banner: "Council prompt ready."
                    ))
                )
            )
        } else if defaultCouncilModelCount >= 2 {
            commands.append(
                HomeOrchestrationCommand(
                    id: "council",
                    title: "Use Council",
                    symbolName: "person.3.fill",
                    action: .useAutoCouncil
                )
            )
        }

        if agentAvailable {
            commands.append(
                HomeOrchestrationCommand(
                    id: "agent",
                    title: "Run Agent",
                    symbolName: "terminal",
                    action: .stagePrompt(HomeStagedPrompt(
                        prompt: selectedProject.map {
                            "Use \($0.name) context to define the next Agent task, expected output, and verification path."
                        } ?? "Define the next Agent task, expected output, and verification path.",
                        projectID: selectedProject?.id,
                        banner: "Agent prompt ready."
                    ))
                )
            )
        } else {
            commands.append(
                HomeOrchestrationCommand(
                    id: "agent",
                    title: "Connect Agent",
                    symbolName: "point.3.connected.trianglepath.dotted",
                    action: .openAgentSettings
                )
            )
        }

        return commands
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
