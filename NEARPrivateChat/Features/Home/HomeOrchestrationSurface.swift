import SwiftUI

enum HomeOrchestrationFilter: String, CaseIterable, Identifiable {
    case all
    case streams
    case agents
    case projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .streams:
            return "Streams"
        case .agents:
            return "Agents"
        case .projects:
            return "Projects"
        }
    }

    var symbolName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .streams:
            return "dot.radiowaves.left.and.right"
        case .agents:
            return "sparkles"
        case .projects:
            return "folder"
        }
    }
}

enum HomeOrchestrationTone: Equatable {
    case blue
    case green
    case amber
    case red
    case violet
    case neutral

    var tintColor: Color {
        switch self {
        case .blue:
            return Color.brandBlue
        case .green:
            return Color.proofVerified
        case .amber:
            return Color.proofStale
        case .red:
            return Color.proofMismatch
        case .violet:
            return Color.purple
        case .neutral:
            return Color.textSecondary
        }
    }
}

enum HomeOrchestrationItemKind: String, Equatable {
    case briefing
    case council
    case agent
    case project
    case chat
    case setup

    var filter: HomeOrchestrationFilter {
        switch self {
        case .briefing:
            return .streams
        case .council, .agent, .setup:
            return .agents
        case .project:
            return .projects
        case .chat:
            return .all
        }
    }
}

struct HomeStagedPrompt: Equatable {
    let prompt: String
    let projectID: String?
    let banner: String

    init(prompt: String, projectID: String? = nil, banner: String = "Prompt ready.") {
        self.prompt = prompt
        self.projectID = projectID
        self.banner = banner
    }
}

enum HomeOrchestrationAction: Equatable {
    case openBriefing(UUID)
    case openProject(String)
    case openConversation(String)
    case openAgentSettings
    case useAutoCouncil
    case newBriefing
    case stagePrompt(HomeStagedPrompt)
}

struct HomeOrchestrationCommand: Identifiable, Equatable {
    let id: String
    let title: String
    let symbolName: String
    let action: HomeOrchestrationAction
}

struct HomeOrchestrationItem: Identifiable, Equatable {
    let id: String
    let kind: HomeOrchestrationItemKind
    let title: String
    let subtitle: String
    let detail: String
    let statusText: String
    let symbolName: String
    let tone: HomeOrchestrationTone
    let action: HomeOrchestrationAction

    func matches(_ filter: HomeOrchestrationFilter) -> Bool {
        filter == .all || kind.filter == filter
    }
}

struct HomeOrchestrationScheduleItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
    let scheduleLabel: String
    let symbolName: String
    let tone: HomeOrchestrationTone
    let action: HomeOrchestrationAction
}

struct HomeOrchestrationPlan: Equatable {
    let subtitle: String
    let liveItems: [HomeOrchestrationItem]
    let scheduledItems: [HomeOrchestrationScheduleItem]
    let commands: [HomeOrchestrationCommand]

    var activeCount: Int { liveItems.count }
}

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
        setupPlan: AppSetupPlan? = nil
    ) -> HomeOrchestrationPlan {
        let sortedBriefings = sorted(briefings: briefings)
        let sortedProjects = sorted(projects: projects, selectedProjectID: selectedProjectID)
        let liveBriefings = sortedBriefings.filter { $0.latestResult != nil }

        var items: [HomeOrchestrationItem] = []
        if isStreaming {
            items.append(activeRunItem(routeLabel: routeLabel))
        }

        items.append(contentsOf: liveBriefings.prefix(2).map(briefingItem))

        if isCouncilModeEnabled || defaultCouncilModelCount >= 2 {
            items.append(councilItem(
                isEnabled: isCouncilModeEnabled,
                defaultModelCount: defaultCouncilModelCount,
                modelNames: councilModelNames
            ))
        }

        if hostedAgentAvailable || mobileAgentAvailable {
            items.append(agentItem(
                hostedAvailable: hostedAgentAvailable,
                mobileAvailable: mobileAgentAvailable,
                selectedProject: sortedProjects.first
            ))
        }

        if let setupPlan,
           let skill = setupPlan.starterSkillSuggestions.first {
            items.append(setupSkillItem(skill: skill, setupPlan: setupPlan, selectedProject: sortedProjects.first))
        }

        let remainingSlots = max(0, 6 - items.count)
        items.append(contentsOf: sortedProjects.prefix(remainingSlots).map(projectItem))

        if items.count < 4 {
            let chatSlots = max(0, 4 - items.count)
            items.append(contentsOf: conversations.prefix(chatSlots).map(chatItem))
        }

        if items.isEmpty {
            items.append(emptyStarterItem())
        }

        let scheduledItems = sortedBriefings.prefix(4).map(scheduleItem)
        let subtitle = surfaceSubtitle(
            liveBriefingCount: liveBriefings.count,
            projectCount: projects.count,
            isCouncilAvailable: isCouncilModeEnabled || defaultCouncilModelCount >= 2,
            isAgentAvailable: hostedAgentAvailable || mobileAgentAvailable
        )

        return HomeOrchestrationPlan(
            subtitle: subtitle,
            liveItems: items,
            scheduledItems: scheduledItems,
            commands: commandItems(
                selectedProject: sortedProjects.first,
                isCouncilModeEnabled: isCouncilModeEnabled,
                defaultCouncilModelCount: defaultCouncilModelCount,
                agentAvailable: hostedAgentAvailable || mobileAgentAvailable
            )
        )
    }

    private static func activeRunItem(routeLabel: String) -> HomeOrchestrationItem {
        HomeOrchestrationItem(
            id: "active-run",
            kind: .agent,
            title: "Active run",
            subtitle: routeLabel,
            detail: "The current agent turn is still working.",
            statusText: "running",
            symbolName: "waveform.path.ecg",
            tone: .green,
            action: .stagePrompt(HomeStagedPrompt(
                prompt: "After the current run finishes, summarize what changed, what still needs input, and the safest next action.",
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
            detail: widgetSummary(widget) ?? "Open the threaded brief and ask a follow-up.",
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
        let subtitle: String
        if names.isEmpty {
            subtitle = defaultModelCount > 1 ? "\(defaultModelCount) models available" : "Multi-model route"
        } else {
            subtitle = names.prefix(3).joined(separator: " + ")
        }

        let action: HomeOrchestrationAction = isEnabled
            ? .stagePrompt(HomeStagedPrompt(
                prompt: "Run a Council pass on the current decision. Ask each model to state agreement, dissent, risk, and the recommended next move, then synthesize.",
                banner: "Council prompt ready."
            ))
            : .useAutoCouncil

        return HomeOrchestrationItem(
            id: "council-room",
            kind: .council,
            title: isEnabled ? "Council room" : "Auto-Council",
            subtitle: subtitle,
            detail: isEnabled ? "Compare model perspectives before committing." : "Enable the default multi-model lineup.",
            statusText: isEnabled ? "ready" : "available",
            symbolName: "person.3.fill",
            tone: .violet,
            action: action
        )
    }

    private static func agentItem(
        hostedAvailable: Bool,
        mobileAvailable: Bool,
        selectedProject: ChatProject?
    ) -> HomeOrchestrationItem {
        let route = hostedAvailable ? "Hosted IronClaw" : "Phone agent"
        let projectName = selectedProject?.name.nilIfBlank
        let detail = projectName.map { "Plan work from \($0) context." } ?? "Plan code, research, and tool work without sending yet."
        let prompt = projectName.map {
            "Use the \($0) project context to plan the next agent task. Include goal, files or sources to inspect, risks, and focused verification."
        } ?? "Plan the next agent task. Include goal, context to inspect, risks, and focused verification."

        return HomeOrchestrationItem(
            id: "agent-builder",
            kind: .agent,
            title: "Agent builder",
            subtitle: route,
            detail: detail,
            statusText: hostedAvailable ? "connected" : (mobileAvailable ? "local" : "ready"),
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
            statusText: project.conversationIDs.isEmpty ? "workspace" : "\(project.conversationIDs.count) chats",
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
            detail: "Open the thread and continue from the latest turn.",
            statusText: timestampText(for: conversation.createdAt),
            symbolName: "bubble.left.and.bubble.right",
            tone: .neutral,
            action: .openConversation(conversation.id)
        )
    }

    private static func emptyStarterItem() -> HomeOrchestrationItem {
        HomeOrchestrationItem(
            id: "starter-workboard",
            kind: .setup,
            title: "Start a work stream",
            subtitle: "Private chat, Council, agent, or briefing",
            detail: "Stage the first prompt and keep the run editable.",
            statusText: "new",
            symbolName: "sparkles.rectangle.stack",
            tone: .blue,
            action: .stagePrompt(HomeStagedPrompt(
                prompt: "Help me choose the best first work stream for today: private answer, research brief, Council decision, or agent task.",
                banner: "Work stream prompt ready."
            ))
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
        defaultCouncilModelCount: Int,
        agentAvailable: Bool
    ) -> [HomeOrchestrationCommand] {
        var commands = [
            HomeOrchestrationCommand(
                id: "brief",
                title: "Make brief",
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
                title: "Plan patch",
                symbolName: "hammer",
                action: .stagePrompt(HomeStagedPrompt(
                    prompt: selectedProject.map {
                        "Use the \($0.name) project context to plan a safe patch. Identify files to inspect, likely changes, tests, and risks before editing."
                    } ?? "Plan a safe patch. Identify context to inspect, likely changes, tests, and risks before editing.",
                    projectID: selectedProject?.id,
                    banner: "Patch plan ready."
                ))
            )
        ]

        if isCouncilModeEnabled {
            commands.append(
                HomeOrchestrationCommand(
                    id: "council",
                    title: "Run Council",
                    symbolName: "person.3.fill",
                    action: .stagePrompt(HomeStagedPrompt(
                        prompt: "Run a Council comparison on this. Ask for agreement, dissent, risk, and a recommended decision.",
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
                    title: "Ask agent",
                    symbolName: "terminal",
                    action: .stagePrompt(HomeStagedPrompt(
                        prompt: selectedProject.map {
                            "Use the \($0.name) project context to define the next agent task, expected output, and verification path."
                        } ?? "Define the next agent task, expected output, and verification path.",
                        projectID: selectedProject?.id,
                        banner: "Agent prompt ready."
                    ))
                )
            )
        } else {
            commands.append(
                HomeOrchestrationCommand(
                    id: "agent",
                    title: "Connect agent",
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

    private static func surfaceSubtitle(
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
            parts.append("\(projectCount) workspaces")
        }
        if isCouncilAvailable {
            parts.append("Council")
        }
        if isAgentAvailable {
            parts.append("Agent")
        }
        return parts.isEmpty ? "Stage the next useful run" : parts.joined(separator: " / ")
    }

    private static func widgetSummary(_ widget: MessageWidget?) -> String? {
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
        case .generic:
            return widget.note?.nilIfBlank
        }
        return widget.note?.nilIfBlank
    }

    private static func projectContextLabel(_ project: ChatProject) -> String {
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

    private static func projectDetail(_ project: ChatProject) -> String {
        if let memory = project.memorySummary.nilIfBlank {
            return memory
        }
        if let instructions = project.instructions.nilIfBlank {
            return instructions
        }
        return "Open files, links, notes, and task context."
    }

    private static func scheduleSubtitle(_ briefing: Briefing) -> String {
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

    private static func tone(for widget: MessageWidget?) -> HomeOrchestrationTone {
        switch widget?.kind {
        case .metric:
            return tone(for: widget?.metric?.trend)
        case .chart:
            return tone(for: widget?.chart?.trend)
        case .newsBrief:
            return .blue
        case .comparison:
            return .violet
        case .generic, .none:
            return .neutral
        }
    }

    private static func tone(for trend: WidgetTrend?) -> HomeOrchestrationTone {
        switch trend {
        case .up:
            return .green
        case .down:
            return .red
        case .flat, .none:
            return .neutral
        }
    }

    private static func symbolName(for kind: WidgetKind?) -> String {
        switch kind {
        case .chart:
            return "chart.xyaxis.line"
        case .metric:
            return "number"
        case .comparison:
            return "tablecells"
        case .newsBrief:
            return "newspaper"
        case .generic, .none:
            return "doc.text"
        }
    }

    private static func timestampText(for createdAt: TimeInterval?) -> String {
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

struct HomeOrchestrationSurface: View {
    let plan: HomeOrchestrationPlan
    let onAction: (HomeOrchestrationAction) -> Void
    @State private var selectedFilter: HomeOrchestrationFilter = .all

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 10)
    ]

    private var visibleItems: [HomeOrchestrationItem] {
        plan.liveItems.filter { $0.matches(selectedFilter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            commandStrip
            filterStrip
            liveGrid
            scheduledSection
        }
        .padding(14)
        .background(Color.appBackground)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(plan.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button {
                onAction(.newBriefing)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appPanelBackground)
                    .frame(width: 32, height: 32)
                    .background(Color.actionPrimary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New briefing")
        }
    }

    private var commandStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(plan.commands) { command in
                    Button {
                        onAction(command.action)
                    } label: {
                        Label(command.title, systemImage: command.symbolName)
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(Color.appPanelBackground, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(Color.appBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
    }

    private var filterStrip: some View {
        HStack(spacing: 6) {
            ForEach(HomeOrchestrationFilter.allCases) { filter in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                        selectedFilter = filter
                    }
                } label: {
                    Label(filter.title, systemImage: filter.symbolName)
                        .font(.caption2.weight(.bold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(selectedFilter == filter ? Color.actionPrimary : Color.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            selectedFilter == filter ? Color.actionTint : Color.appPanelBackground,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var liveGrid: some View {
        if visibleItems.isEmpty {
            Text("No work streams in this view.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(visibleItems) { item in
                    HomeOrchestrationCard(item: item) {
                        onAction(item.action)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var scheduledSection: some View {
        if !plan.scheduledItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Scheduled")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.textSecondary)
                    Spacer(minLength: 8)
                    Text("\(plan.scheduledItems.count) upcoming")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(plan.scheduledItems.enumerated()), id: \.element.id) { index, item in
                        HomeOrchestrationScheduleRow(item: item) {
                            onAction(item.action)
                        }
                        if index != plan.scheduledItems.count - 1 {
                            Divider()
                                .overlay(Color.appHairline)
                                .padding(.leading, 48)
                        }
                    }
                }
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }
            }
        }
    }
}

private struct HomeOrchestrationCard: View {
    let item: HomeOrchestrationItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.symbolName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(item.tone.tintColor)
                        .frame(width: 30, height: 30)
                        .background(item.tone.tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Spacer(minLength: 6)

                    Text(item.statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(item.tone.tintColor)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityHint: String {
        switch item.kind {
        case .briefing, .project, .chat:
            return "Opens this work stream."
        case .council, .agent, .setup:
            return "Stages or prepares this agentic action without sending."
        }
    }
}

private struct HomeOrchestrationScheduleRow: View {
    let item: HomeOrchestrationScheduleItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(item.tone.tintColor)
                    .frame(width: 30, height: 30)
                    .background(item.tone.tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(item.scheduleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
