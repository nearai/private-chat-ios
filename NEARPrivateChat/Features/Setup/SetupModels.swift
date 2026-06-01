import Foundation
import SwiftUI

enum UserSetupUseCase: String, CaseIterable, Codable, Identifiable, Hashable {
    case privateChat
    case research
    case buildAgents
    case teamProjects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateChat: "Ask privately"
        case .research: "Research with sources"
        case .buildAgents: "Run an Agent"
        case .teamProjects: "Work in a Project"
        }
    }

    var subtitle: String {
        switch self {
        case .privateChat: "Fast private answers, web only when useful."
        case .research: "Current sources, citations, and saveable memos."
        case .buildAgents: "Plan code, PR, and test work from Project context."
        case .teamProjects: "Files, links, notes, and shared context."
        }
    }

    var symbolName: String {
        switch self {
        case .privateChat: "lock.shield"
        case .research: "doc.text.magnifyingglass"
        case .buildAgents: "terminal"
        case .teamProjects: "folder.badge.gearshape"
        }
    }

    var starterProjectName: String? {
        switch self {
        case .privateChat:
            return nil
        case .research:
            return "Research Room"
        case .buildAgents:
            return "Build Project"
        case .teamProjects:
            return "Project Hub"
        }
    }

    var starterInstructions: String {
        switch self {
        case .privateChat:
            return "Keep answers direct, private, and practical. Use live web only when the question depends on current facts."
        case .research:
            return "Prioritize dated sources, citations, contradictions, and a concise recommendation. Save strong outputs as Project notes."
        case .buildAgents:
            return "Use Project files, pull requests, issues, and source links to plan careful code work. Do not suggest destructive changes unless explicitly requested."
        case .teamProjects:
            return "Use Project files, saved source links, notes, and saved outputs before broad web. Keep context tidy and ask only when a missing source blocks progress."
        }
    }

    var starterPrompt: String {
        switch self {
        case .privateChat:
            return "Help me think through the most important question I should ask first."
        case .research:
            return "Create a sourced research brief on the latest important AI developments, with dates, citations, and a short recommendation."
        case .buildAgents:
            return "Plan the first repo task: what to inspect, what to change, and which focused tests should run."
        case .teamProjects:
            return "Help me set up this Project: what files, links, instructions, and first chat should I add?"
        }
    }

    var workspaceSeed: SetupWorkspaceSeed? {
        switch self {
        case .privateChat:
            return nil
        case .research:
            return SetupWorkspaceSeed(
                title: "Research brief",
                detail: "Starter prompts ask for dated sources, contradictions, citations, and a concise recommendation.",
                symbolName: "doc.text.magnifyingglass"
            )
        case .buildAgents:
            return SetupWorkspaceSeed(
                title: "Repo plan",
                detail: "Starter prompts ask for a safe patch plan and focused verification before code changes.",
                symbolName: "terminal"
            )
        case .teamProjects:
            return SetupWorkspaceSeed(
                title: "Project memory",
                detail: "Links, files, notes, and reusable instructions stay together inside one active project.",
                symbolName: "folder.badge.gearshape"
            )
        }
    }

    var starterSkillIDs: [String] {
        switch self {
        case .privateChat:
            return []
        case .research:
            return ["llm-council", "plan-mode", "decision-capture"]
        case .buildAgents:
            return ["project-setup", "plan-mode", "developer-setup", "coding", "local-test", "review-readiness", "github-workflow"]
        case .teamProjects:
            return ["new-project", "project-setup", "decision-capture", "commitment-triage"]
        }
    }
}

extension Array where Element == UserSetupUseCase {
    var setupOrderedUnique: [UserSetupUseCase] {
        let selected = Set(self)
        let ordered = UserSetupUseCase.allCases.filter { selected.contains($0) }
        return ordered.isEmpty ? [.privateChat] : ordered
    }

    var setupPrimaryUseCase: UserSetupUseCase {
        let selected = Set(setupOrderedUnique)
        if selected.contains(.buildAgents) {
            return .buildAgents
        }
        if selected.contains(.research) {
            return .research
        }
        if selected.contains(.teamProjects) {
            return .teamProjects
        }
        return .privateChat
    }
}

enum UserSetupContextStyle: String, CaseIterable, Codable, Identifiable, Hashable {
    case simple
    case project
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: "Automatic"
        case .project: "Project context"
        case .files: "Files first"
        }
    }

    var subtitle: String {
        switch self {
        case .simple: "Use the chat, web, and saved context only when it helps."
        case .project: "Keep links, notes, instructions, and files together."
        case .files: "Prioritize attached and project files before anything else."
        }
    }

    var symbolName: String {
        switch self {
        case .simple: "sparkles"
        case .project: "folder"
        case .files: "paperclip"
        }
    }

    var sourceMode: ChatSourceMode {
        switch self {
        case .simple: .auto
        case .project: .all
        case .files: .files
        }
    }

    init(sourceMode: ChatSourceMode) {
        switch sourceMode {
        case .files:
            self = .files
        case .all, .links:
            self = .project
        case .auto, .web:
            self = .simple
        }
    }
}

enum UserSetupExperienceMode: String, CaseIterable, Codable, Identifiable, Hashable {
    case beginner
    case power

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner: "Beginner"
        case .power: "Power"
        }
    }

    var subtitle: String {
        switch self {
        case .beginner: "Start with private chat, sources, and proof display. Optional capabilities stay available later."
        case .power: "Show agents, Council, Cloud models, and developer controls from day one."
        }
    }

    var symbolName: String {
        switch self {
        case .beginner: "sparkles"
        case .power: "bolt"
        }
    }
}

enum UserSetupStarterPreset: String, CaseIterable, Codable, Identifiable, Hashable {
    case privateQuestion
    case researchBrief
    case agentMission
    case projectWorkspace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateQuestion: "Private question"
        case .researchBrief: "Research brief"
        case .agentMission: "Agent mission"
        case .projectWorkspace: "Project"
        }
    }

    var quickStartDetail: String {
        switch self {
        case .privateQuestion:
            return "Open a private draft with a simple route."
        case .researchBrief:
            return "Start a cited brief with web-ready defaults."
        case .agentMission:
            return "Launch a phone-safe agent planning draft."
        case .projectWorkspace:
            return "Open a project-first draft with saved context."
        }
    }

    var setupExampleGoalText: String {
        switch self {
        case .privateQuestion:
            return "Think through a private question"
        case .researchBrief:
            return "Research the latest important AI developments"
        case .agentMission:
            return "Plan a phone-launched agent task for a repo or research project"
        case .projectWorkspace:
            return "Set up a shared Project with files, links, and reusable instructions"
        }
    }

    var prompt: String {
        switch self {
        case .privateQuestion: "Help me think through a private question."
        case .researchBrief: "Create a sourced brief on the latest developments in AI."
        case .agentMission: "Plan a phone-launched agent task for a repo or research project."
        case .projectWorkspace: "Help me set up this Project: what files, links, instructions, and first chat should I add?"
        }
    }

    var symbolName: String {
        switch self {
        case .privateQuestion: "lock.shield"
        case .researchBrief: "text.magnifyingglass"
        case .agentMission: "terminal"
        case .projectWorkspace: "folder.badge.gearshape"
        }
    }

    var useCase: UserSetupUseCase {
        switch self {
        case .privateQuestion: .privateChat
        case .researchBrief: .research
        case .agentMission: .buildAgents
        case .projectWorkspace: .teamProjects
        }
    }

    var contextStyle: UserSetupContextStyle {
        switch self {
        case .privateQuestion: .simple
        case .researchBrief, .agentMission, .projectWorkspace: .project
        }
    }

    var wantsIronclaw: Bool {
        self == .agentMission
    }

    var wantsCouncil: Bool {
        self == .researchBrief
    }

    var wantsWeb: Bool {
        self == .researchBrief
    }

    var quickStartProfile: UserSetupProfile {
        UserSetupProfile(
            useCase: useCase,
            contextStyle: contextStyle,
            wantsWeb: wantsWeb,
            wantsIronclaw: wantsIronclaw,
            wantsCouncil: wantsCouncil,
            useCases: [useCase],
            goalText: "",
            experienceMode: wantsIronclaw || wantsCouncil ? .power : .beginner
        )
    }

    func previewPlan(
        readiness: AppSetupReadinessSnapshot,
        routeDefaults: SetupRouteDefaults = .empty
    ) -> AppSetupPlan {
        AppSetupPlan(
            profile: quickStartProfile,
            readiness: readiness,
            routeDefaults: routeDefaults
        )
    }
}

struct SetupPromptSuggestion: Codable, Identifiable, Hashable {
    let title: String
    let symbolName: String
    let prompt: String

    var id: String {
        "\(title)-\(prompt)"
    }
}

struct SetupWorkspaceSeed: Codable, Identifiable, Hashable {
    let title: String
    let detail: String
    let symbolName: String

    var id: String {
        "\(title)-\(detail)"
    }
}

struct SetupAgentMissionSuggestion: Codable, Hashable {
    let title: String
    let detail: String
    let prompt: String
}

struct UserSetupProfile: Codable, Hashable {
    var useCase: UserSetupUseCase {
        didSet {
            guard oldValue != useCase, !useCases.contains(useCase) else { return }
            useCases = [useCase]
        }
    }
    var useCases: [UserSetupUseCase]
    var goalText: String
    var contextStyle: UserSetupContextStyle
    var wantsWeb: Bool
    var wantsIronclaw: Bool
    var wantsCouncil: Bool
    var experienceMode: UserSetupExperienceMode
    var routeDefaults: SetupRouteDefaults

    init(
        useCase: UserSetupUseCase,
        contextStyle: UserSetupContextStyle,
        wantsWeb: Bool,
        wantsIronclaw: Bool,
        wantsCouncil: Bool,
        useCases: [UserSetupUseCase]? = nil,
        goalText: String = "",
        experienceMode: UserSetupExperienceMode = .beginner,
        routeDefaults: SetupRouteDefaults = .empty
    ) {
        let normalizedUseCases = (useCases ?? [useCase]).setupOrderedUnique
        self.useCases = normalizedUseCases
        self.useCase = normalizedUseCases.setupPrimaryUseCase
        self.goalText = String(goalText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
        self.contextStyle = contextStyle
        self.wantsWeb = wantsWeb
        self.wantsIronclaw = wantsIronclaw
        self.wantsCouncil = wantsCouncil
        self.experienceMode = experienceMode
        self.routeDefaults = routeDefaults.normalized
    }

    enum CodingKeys: String, CodingKey {
        case useCase
        case useCases
        case goalText
        case contextStyle
        case wantsWeb
        case wantsIronclaw
        case wantsCouncil
        case experienceMode
        case routeDefaults
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedUseCase = try container.decodeIfPresent(UserSetupUseCase.self, forKey: .useCase) ?? .privateChat
        let storedUseCases = try container.decodeIfPresent([UserSetupUseCase].self, forKey: .useCases)
        let normalizedUseCases = (storedUseCases ?? [storedUseCase]).setupOrderedUnique
        useCases = normalizedUseCases
        useCase = normalizedUseCases.setupPrimaryUseCase
        goalText = try container.decodeIfPresent(String.self, forKey: .goalText) ?? ""
        contextStyle = try container.decodeIfPresent(UserSetupContextStyle.self, forKey: .contextStyle) ?? .simple
        wantsWeb = try container.decodeIfPresent(Bool.self, forKey: .wantsWeb) ?? false
        wantsIronclaw = try container.decodeIfPresent(Bool.self, forKey: .wantsIronclaw) ?? false
        wantsCouncil = try container.decodeIfPresent(Bool.self, forKey: .wantsCouncil) ?? false
        experienceMode = try container.decodeIfPresent(UserSetupExperienceMode.self, forKey: .experienceMode) ?? .beginner
        routeDefaults = (try container.decodeIfPresent(SetupRouteDefaults.self, forKey: .routeDefaults) ?? .empty).normalized
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(useCase, forKey: .useCase)
        try container.encode(useCases.setupOrderedUnique, forKey: .useCases)
        try container.encode(goalText, forKey: .goalText)
        try container.encode(contextStyle, forKey: .contextStyle)
        try container.encode(wantsWeb, forKey: .wantsWeb)
        try container.encode(wantsIronclaw, forKey: .wantsIronclaw)
        try container.encode(wantsCouncil, forKey: .wantsCouncil)
        try container.encode(experienceMode, forKey: .experienceMode)
        try container.encode(routeDefaults.normalized, forKey: .routeDefaults)
    }

    var normalizedForDefaults: UserSetupProfile {
        var profile = self
        profile.useCases = useCases.setupOrderedUnique
        profile.useCase = profile.useCases.setupPrimaryUseCase
        profile.goalText = normalizedGoalText
        profile.routeDefaults = routeDefaults.normalized
        return profile
    }

    var normalizedGoalText: String {
        String(goalText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
    }

    static func inferredCurrentDefaults(
        webSearchEnabled: Bool,
        sourceMode: ChatSourceMode,
        selectedModelID: String,
        hasSelectedProject: Bool,
        isCouncilModeEnabled: Bool,
        researchModeEnabled: Bool
    ) -> UserSetupProfile {
        var profile = UserSetupProfile.defaults
        profile.wantsWeb = webSearchEnabled
        profile.contextStyle = UserSetupContextStyle(sourceMode: sourceMode)
        profile.wantsIronclaw = selectedModelID == ModelOption.ironclawMobileModelID ||
            selectedModelID == ModelOption.ironclawModelID
        profile.wantsCouncil = isCouncilModeEnabled

        if researchModeEnabled {
            profile.useCase = .research
            profile.useCases = [.research]
        } else if profile.wantsIronclaw {
            profile.useCase = .buildAgents
            profile.useCases = [.buildAgents]
        } else if hasSelectedProject || profile.contextStyle != .simple {
            profile.useCase = .teamProjects
            profile.useCases = [.teamProjects]
        } else {
            profile.useCase = .privateChat
            profile.useCases = [.privateChat]
        }

        return profile
    }

    var setupStarterProjectName: String? {
        if useCases.contains(.buildAgents) {
            return UserSetupUseCase.buildAgents.starterProjectName
        }
        if useCases.contains(.research) {
            return UserSetupUseCase.research.starterProjectName
        }
        if useCases.contains(.teamProjects) {
            return UserSetupUseCase.teamProjects.starterProjectName
        }
        return contextStyle == .project ? "Project Hub" : nil
    }

    var setupProjectInstructions: String {
        let orderedUseCases = useCases.setupOrderedUnique
        let instructionBlocks = orderedUseCases.map { useCase in
            if orderedUseCases.count == 1 {
                return useCase.starterInstructions
            }
            return "\(useCase.title): \(useCase.starterInstructions)"
        }
        let goal = normalizedGoalText
        var sections: [String] = []
        if orderedUseCases.count > 1 {
            let titles = orderedUseCases.map(\.title).joined(separator: ", ")
            sections.append("This Project was configured for: \(titles).")
        }
        sections.append(contentsOf: instructionBlocks)
        if !goal.isEmpty {
            sections.append("Setup goal: \(goal)")
        }
        return sections.joined(separator: "\n\n")
    }

    var setupInstructionSummary: String {
        let orderedUseCases = useCases.setupOrderedUnique
        let lead = orderedUseCases.setupPrimaryUseCase.starterInstructions
        if orderedUseCases.count > 1 {
            return "\(orderedUseCases.count) setup tracks are combined into shared project instructions."
        }
        return lead
    }

    var agentMissionSuggestion: SetupAgentMissionSuggestion? {
        let orderedUseCases = useCases.setupOrderedUnique
        guard wantsIronclaw || orderedUseCases.contains(.buildAgents) else { return nil }

        let goal = normalizedGoalText
        if !goal.isEmpty {
            return SetupAgentMissionSuggestion(
                title: "Use saved setup goal",
                detail: "Saved setup wants agent work for this goal first.",
                prompt: "Plan the first build or repo task for this goal: \(goal)"
            )
        }

        return SetupAgentMissionSuggestion(
            title: "Use saved agent starter",
            detail: "Saved setup keeps repo and agent work ready from day one.",
            prompt: UserSetupUseCase.buildAgents.starterPrompt
        )
    }

    var firstRunDraft: String? {
        let orderedUseCases = useCases.setupOrderedUnique
        let goal = normalizedGoalText
        if orderedUseCases.count > 1,
           let combinedStarter = combinedStarterSuggestion(for: orderedUseCases, goal: goal) {
            return combinedStarter.prompt
        }

        if !goal.isEmpty, useCases.contains(.research) {
            return "Create a sourced research brief for this goal: \(goal)"
        }
        if !goal.isEmpty, useCases.contains(.buildAgents) {
            return "Plan the first build or repo task for this goal: \(goal)"
        }
        if !goal.isEmpty, useCases.contains(.teamProjects) || contextStyle != .simple {
            return "Help me organize this project and next actions for this goal: \(goal)"
        }
        if !goal.isEmpty {
            return "Help me with this goal: \(goal)"
        }
        if useCases.contains(.buildAgents) {
            return UserSetupUseCase.buildAgents.starterPrompt
        }
        if useCases.contains(.research) {
            return UserSetupUseCase.research.starterPrompt
        }
        if useCases.contains(.teamProjects) || contextStyle != .simple {
            return UserSetupUseCase.teamProjects.starterPrompt
        }
        return nil
    }

    var emptyStateSubtitle: String {
        let goal = normalizedGoalText
        if !goal.isEmpty {
            return "Goal ready: \(goal)"
        }

        switch useCases.setupPrimaryUseCase {
        case .privateChat:
            return "Ask privately first. Turn on web or files only when the task needs them."
        case .research:
            return "Start a cited brief, compare sources, and save strong outputs."
        case .buildAgents:
            return "Start with a safe repo plan, then verify the patch or test pass."
        case .teamProjects:
            return "Turn files, links, and notes into a shared project memory."
        }
    }

    var emptyStatePromptSuggestions: [SetupPromptSuggestion] {
        let orderedUseCases = useCases.setupOrderedUnique
        let goal = normalizedGoalText
        if orderedUseCases.count > 1 {
            return combinedPromptSuggestions(for: orderedUseCases, goal: goal)
        }

        switch orderedUseCases.setupPrimaryUseCase {
        case .privateChat:
            return promptSuggestions(for: .privateChat, goal: goal)
        case .research:
            return promptSuggestions(for: .research, goal: goal)
        case .buildAgents:
            return promptSuggestions(for: .buildAgents, goal: goal)
        case .teamProjects:
            return promptSuggestions(for: .teamProjects, goal: goal)
        }
    }

    private func promptSuggestions(for useCase: UserSetupUseCase, goal: String) -> [SetupPromptSuggestion] {
        switch useCase {
        case .privateChat:
            if !goal.isEmpty {
                return [
                    SetupPromptSuggestion(
                        title: "Start goal",
                        symbolName: "lock.shield",
                        prompt: "Help me with this goal: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "Break into steps",
                        symbolName: "list.bullet.clipboard",
                        prompt: "Break this goal into the next private steps I should take: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "Best first question",
                        symbolName: "questionmark.bubble",
                        prompt: "What is the most important first question I should ask for this goal: \(goal)"
                    )
                ]
            }
            return [
                SetupPromptSuggestion(
                    title: "Private question",
                    symbolName: "lock.shield",
                    prompt: "Help me think through a private question."
                ),
                SetupPromptSuggestion(
                    title: "Pressure-test",
                    symbolName: "scale.3d",
                    prompt: "Pressure-test this decision and show me the strongest risks and tradeoffs: "
                ),
                SetupPromptSuggestion(
                    title: "Draft message",
                    symbolName: "text.bubble",
                    prompt: "Draft a clear message I can send about this situation: "
                )
            ]
        case .research:
            if !goal.isEmpty {
                return [
                    SetupPromptSuggestion(
                        title: "Start brief",
                        symbolName: "doc.text.magnifyingglass",
                        prompt: "Create a sourced research brief for this goal: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "Find sources",
                        symbolName: "globe",
                        prompt: "Find the strongest current sources, dates, and contradictions for this goal: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "Recommend next step",
                        symbolName: "arrow.forward.circle",
                        prompt: "Turn this research goal into a concise recommendation with citations: \(goal)"
                    )
                ]
            }
            return [
                SetupPromptSuggestion(
                    title: "Research brief",
                    symbolName: "doc.text.magnifyingglass",
                    prompt: "Create a sourced brief on the latest developments in AI."
                ),
                SetupPromptSuggestion(
                    title: "Compare sources",
                    symbolName: "arrow.triangle.branch",
                    prompt: "Compare the strongest current sources on this topic, note contradictions, and explain what matters most: "
                ),
                SetupPromptSuggestion(
                    title: "Risk memo",
                    symbolName: "exclamationmark.triangle",
                    prompt: "Draft a short risk memo with dates, citations, and a recommendation for: "
                )
            ]
        case .buildAgents:
            if !goal.isEmpty {
                return [
                    SetupPromptSuggestion(
                        title: "Plan repo task",
                        symbolName: "chevron.left.forwardslash.chevron.right",
                        prompt: "Plan the first repo task for this goal: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "Safe patch",
                        symbolName: "wrench.and.screwdriver",
                        prompt: "Turn this goal into a safe patch plan with focused verification steps: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "Repo checklist",
                        symbolName: "checklist",
                        prompt: "Create a repo inspection checklist for this goal before any code changes: \(goal)"
                    )
                ]
            }
            return [
                SetupPromptSuggestion(
                    title: "Repo plan",
                    symbolName: "chevron.left.forwardslash.chevron.right",
                    prompt: "Plan the first repo task: what to inspect, what to change, and which focused tests should run."
                ),
                SetupPromptSuggestion(
                    title: "Review repo",
                    symbolName: "chevron.left.forwardslash.chevron.right",
                    prompt: "Review this repo and identify the highest-impact safe fix to make first: "
                ),
                SetupPromptSuggestion(
                    title: "Focused tests",
                    symbolName: "checkmark.seal",
                    prompt: "List the focused tests and verification steps I should run for this change: "
                )
            ]
        case .teamProjects:
            if !goal.isEmpty {
                return [
                    SetupPromptSuggestion(
                        title: "Organize project",
                        symbolName: "folder.badge.gearshape",
                        prompt: "Help me organize this project and next actions for this goal: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "Add context",
                        symbolName: "paperclip",
                        prompt: "What files, links, notes, or instructions should I add first for this goal: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "First Project chat",
                        symbolName: "bubble.left.and.bubble.right",
                        prompt: "Draft the best first project chat prompt for this goal: \(goal)"
                    )
                ]
            }
            return [
                SetupPromptSuggestion(
                    title: "Project setup",
                    symbolName: "folder.badge.gearshape",
                    prompt: "Help me set up this Project: what files, links, instructions, and first chat should I add?"
                ),
                SetupPromptSuggestion(
                    title: "Find missing context",
                    symbolName: "magnifyingglass",
                    prompt: "Look at this project context and tell me what is missing before I start work: "
                ),
                SetupPromptSuggestion(
                    title: "Next-step plan",
                    symbolName: "arrow.forward.circle",
                    prompt: "Turn this project context into a concise next-step plan I can act on."
                )
            ]
        }
    }

    private func combinedPromptSuggestions(for orderedUseCases: [UserSetupUseCase], goal: String) -> [SetupPromptSuggestion] {
        let primaryUseCase = orderedUseCases.setupPrimaryUseCase
        let promptUseCaseOrder = [primaryUseCase] + orderedUseCases.filter { $0 != primaryUseCase }
        var suggestions: [SetupPromptSuggestion] = []
        if let combinedStarter = combinedStarterSuggestion(for: orderedUseCases, goal: goal) {
            suggestions.append(combinedStarter)
        }

        for useCase in promptUseCaseOrder {
            if let first = promptSuggestions(for: useCase, goal: goal).first {
                suggestions.append(first)
            }
        }

        for useCase in promptUseCaseOrder {
            for suggestion in promptSuggestions(for: useCase, goal: goal).dropFirst() {
                suggestions.append(suggestion)
                if suggestions.count >= 6 {
                    break
                }
            }
            if suggestions.count >= 6 {
                break
            }
        }

        var seenPrompts: Set<String> = []
        var uniqueSuggestions: [SetupPromptSuggestion] = []
        for suggestion in suggestions {
            if seenPrompts.insert(suggestion.prompt).inserted {
                uniqueSuggestions.append(suggestion)
            }
        }
        return Array(uniqueSuggestions.prefix(3))
    }

    private func combinedStarterSuggestion(for orderedUseCases: [UserSetupUseCase], goal: String) -> SetupPromptSuggestion? {
        guard orderedUseCases.count > 1 else { return nil }

        let primaryUseCase = orderedUseCases.setupPrimaryUseCase
        let primaryPrompt: String
        switch primaryUseCase {
        case .privateChat:
            primaryPrompt = goal.isEmpty ? "Help me get started." : "Help me with this goal"
        case .research:
            primaryPrompt = goal.isEmpty ? "Create a sourced research brief" : "Create a sourced research brief for this goal"
        case .buildAgents:
            primaryPrompt = goal.isEmpty ? "Plan the first repo task" : "Plan the first repo task for this goal"
        case .teamProjects:
            primaryPrompt = goal.isEmpty ? "Help me set up this Project" : "Help me organize this Project and next actions for this goal"
        }

        var qualifiers: [String] = []
        if orderedUseCases.contains(.teamProjects) && primaryUseCase != .teamProjects {
            qualifiers.append("using project files, links, notes, and memory")
        }
        if orderedUseCases.contains(.research) && primaryUseCase != .research {
            qualifiers.append("with current sources and citations")
        }
        if orderedUseCases.contains(.buildAgents) && primaryUseCase != .buildAgents {
            qualifiers.append("including a safe patch and focused verification plan")
        }
        if orderedUseCases.contains(.privateChat) && primaryUseCase == .privateChat && goal.isEmpty {
            qualifiers.append("and keep it private and practical")
        }

        var prompt = primaryPrompt
        if !qualifiers.isEmpty {
            prompt += " " + qualifiers.joined(separator: ", ")
        }
        if !goal.isEmpty {
            prompt += ": \(goal)"
        } else {
            prompt += "."
        }

        return SetupPromptSuggestion(
            title: combinedStarterTitle(for: primaryUseCase, hasGoal: !goal.isEmpty),
            symbolName: primaryUseCase.symbolName,
            prompt: prompt
        )
    }

    private func combinedStarterTitle(for useCase: UserSetupUseCase, hasGoal: Bool) -> String {
        if hasGoal {
            return "Start goal"
        }
        switch useCase {
        case .privateChat:
            return "Start chat"
        case .research:
            return "Start brief"
        case .buildAgents:
            return "Start plan"
        case .teamProjects:
            return "Start Project"
        }
    }

    var setupWorkspaceSeeds: [SetupWorkspaceSeed] {
        guard let starterProjectName = setupStarterProjectName else { return [] }
        let orderedUseCases = useCases.setupOrderedUnique
        let prioritizedUseCases = [orderedUseCases.setupPrimaryUseCase] + orderedUseCases.filter { $0 != orderedUseCases.setupPrimaryUseCase }

        var seeds = [
            SetupWorkspaceSeed(
                title: "Project",
                detail: "\(starterProjectName) opens as the active project for your first chats.",
                symbolName: "folder.badge.plus"
            ),
        ]

        for useCase in prioritizedUseCases {
            if let seed = useCase.workspaceSeed {
                seeds.append(seed)
            }
        }

        seeds.append(
            SetupWorkspaceSeed(
                title: orderedUseCases.count > 1 ? "Shared guide" : "Setup guide",
                detail: orderedUseCases.count > 1
                    ? "\(orderedUseCases.count) setup tracks share one reusable guide note and project instructions."
                    : "A reusable note keeps next steps visible inside the project.",
                symbolName: "note.text.badge.plus"
            )
        )

        let goal = normalizedGoalText
        if !goal.isEmpty {
            seeds.append(
                SetupWorkspaceSeed(
                    title: "Goal",
                    detail: goal,
                    symbolName: "target"
                )
            )
        }

        var seenTitles: Set<String> = []
        return seeds.filter { seed in
            seenTitles.insert(seed.title).inserted
        }
    }

    var setupSkillSuggestions: [IronclawSkillProfile] {
        let orderedUseCases = useCases.setupOrderedUnique
        var coreSkillIDs: [String] = []
        let goalMatchedSkillIDs = IronclawSkillCatalog.matchingSkillIDs(
            for: normalizedGoalText,
            limit: orderedUseCases.contains(.buildAgents) || wantsIronclaw ? 3 : 2
        )

        if wantsCouncil {
            coreSkillIDs.append("llm-council")
        }
        if wantsIronclaw {
            coreSkillIDs.append(contentsOf: ["plan-mode", "developer-setup"])
        }

        let prioritizedUseCases = [orderedUseCases.setupPrimaryUseCase] + orderedUseCases.filter { $0 != orderedUseCases.setupPrimaryUseCase }
        var useCaseSkillIDs: [String] = []
        for useCase in prioritizedUseCases {
            useCaseSkillIDs.append(contentsOf: useCase.starterSkillIDs)
        }

        let skillIDs = (wantsIronclaw || wantsCouncil)
            ? coreSkillIDs + goalMatchedSkillIDs + useCaseSkillIDs
            : useCaseSkillIDs + goalMatchedSkillIDs
        guard !skillIDs.isEmpty else { return [] }
        let limit = !goalMatchedSkillIDs.isEmpty && (wantsIronclaw || wantsCouncil)
            ? 5
            : (wantsIronclaw || orderedUseCases.contains(.buildAgents) || orderedUseCases.count > 1 ? 4 : 3)
        return IronclawSkillCatalog.profiles(for: skillIDs, limit: limit)
    }

    mutating func toggleUseCase(_ useCase: UserSetupUseCase) {
        var next = useCases.setupOrderedUnique
        if next.contains(useCase) {
            guard next.count > 1 else { return }
            next.removeAll { $0 == useCase }
        } else {
            next.append(useCase)
        }
        useCases = next.setupOrderedUnique
        self.useCase = useCases.setupPrimaryUseCase
    }

    mutating func applyUseCaseSelectionDefaults(
        editedWeb: Bool,
        editedIronclaw: Bool,
        editedCouncil: Bool,
        editedContextStyle: Bool
    ) {
        let selected = Set(useCases)
        useCase = useCases.setupPrimaryUseCase
        if !editedWeb {
            wantsWeb = selected.contains(.research)
        }
        if !editedIronclaw {
            wantsIronclaw = experienceMode == .power && selected.contains(.buildAgents)
        }
        if !editedCouncil {
            wantsCouncil = experienceMode == .power && selected.contains(.research) && !wantsIronclaw
        }
        if !editedContextStyle {
            if selected.contains(.research) || selected.contains(.buildAgents) || selected.contains(.teamProjects) {
                contextStyle = .project
            } else {
                contextStyle = .simple
            }
        }
    }

    mutating func applyStarterPreset(_ preset: UserSetupStarterPreset) {
        useCase = preset.useCase
        useCases = [preset.useCase]
        goalText = preset.setupExampleGoalText
        contextStyle = preset.contextStyle
        wantsWeb = preset.wantsWeb
        wantsIronclaw = preset.wantsIronclaw
        wantsCouncil = preset.wantsCouncil
    }

    static let defaults = UserSetupProfile(
        useCase: .privateChat,
        contextStyle: .simple,
        wantsWeb: false,
        wantsIronclaw: false,
        wantsCouncil: false,
        useCases: [.privateChat],
        goalText: "",
        experienceMode: .beginner
    )
}

enum AppSetupModelRoute: String, Codable, Hashable {
    case privateModel
    case council
    case ironclaw

    var title: String {
        switch self {
        case .privateModel: "Private model"
        case .council: "LLM Council"
        case .ironclaw: "Agent"
        }
    }

    var symbolName: String {
        switch self {
        case .privateModel: "lock.shield"
        case .council: "square.grid.2x2"
        case .ironclaw: "terminal"
        }
    }
}

struct AppSetupReadinessSnapshot: Codable, Hashable {
    var modelCatalogLoaded: Bool
    var privateModelAvailable: Bool
    var defaultCouncilModelCount: Int
    var ironclawMobileAvailable: Bool
    var hostedIronclawAvailable: Bool
    var nearCloudKeyConfigured: Bool

    var councilReady: Bool {
        modelCatalogLoaded && defaultCouncilModelCount > 1
    }

    static let optimistic = AppSetupReadinessSnapshot(
        modelCatalogLoaded: true,
        privateModelAvailable: true,
        defaultCouncilModelCount: 3,
        ironclawMobileAvailable: true,
        hostedIronclawAvailable: true,
        nearCloudKeyConfigured: true
    )
}

struct SetupRouteDefaults: Codable, Hashable {
    var privateModelID: String?
    var councilModelIDs: [String]
    var ironclawMobileModelID: String?

    static let empty = SetupRouteDefaults(
        privateModelID: nil,
        councilModelIDs: [],
        ironclawMobileModelID: nil
    )

    var isEmpty: Bool {
        normalized == .empty
    }

    var normalized: SetupRouteDefaults {
        SetupRouteDefaults(
            privateModelID: Self.normalizedID(privateModelID),
            councilModelIDs: Self.normalizedIDs(councilModelIDs),
            ironclawMobileModelID: Self.normalizedID(ironclawMobileModelID)
        )
    }

    func preferredIronclawModelID(readiness: AppSetupReadinessSnapshot) -> String? {
        if readiness.ironclawMobileAvailable {
            return normalized.ironclawMobileModelID ?? ModelOption.ironclawMobileModelID
        }
        if readiness.hostedIronclawAvailable {
            return ModelOption.ironclawModelID
        }
        return nil
    }

    private static func normalizedID(_ id: String?) -> String? {
        guard let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for modelID in ids {
            guard let trimmed = normalizedID(modelID),
                  seen.insert(trimmed.lowercased()).inserted else {
                continue
            }
            normalized.append(trimmed)
        }
        return normalized
    }
}

struct AppSetupPlan: Codable, Hashable, Identifiable {
    var id: String
    var modelRoute: AppSetupModelRoute
    var focusMode: ChatSourceMode
    var focusBehavior: String
    var starterProjectName: String?
    var agentEnabled: Bool
    var councilEnabled: Bool
    var expectedFirstAction: String
    var goalText: String
    var firstRunDraft: String?
    var agentMissionSuggestion: SetupAgentMissionSuggestion?
    var readinessStatus: String
    var experienceSummary: String
    var starterWorkspaceSeeds: [SetupWorkspaceSeed]
    var starterSkillSuggestions: [IronclawSkillProfile]
    var starterPromptSuggestions: [SetupPromptSuggestion]
    var expectedRouteModelIDs: [String]

    var launchCardTitle: String {
        expectedFirstAction
    }

    var launchCardSubtitle: String {
        let goal = goalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !goal.isEmpty {
            return goal
        }
        return "Ready now: \(launchCardMetadata.joined(separator: " · "))"
    }

    var launchCardMetadata: [String] {
        var items = [modelRoute.title, focusMode.setupMetadataTitle]
        if let starterProjectName {
            items.append(starterProjectName)
        }
        return items
    }

    init(
        profile: UserSetupProfile,
        readiness: AppSetupReadinessSnapshot = .optimistic,
        routeDefaults: SetupRouteDefaults = .empty
    ) {
        let profile = profile.normalizedForDefaults
        let routeDefaults = (routeDefaults.isEmpty ? profile.routeDefaults : routeDefaults).normalized
        let preferredIronclawModelID = routeDefaults.preferredIronclawModelID(readiness: readiness)
        let usesIronclaw = profile.wantsIronclaw && preferredIronclawModelID != nil
        let usesCouncil = !usesIronclaw && profile.wantsCouncil && readiness.councilReady
        modelRoute = usesIronclaw ? .ironclaw : (usesCouncil ? .council : .privateModel)
        focusMode = profile.contextStyle.sourceMode
        focusBehavior = Self.focusBehavior(for: profile)
        starterProjectName = profile.setupStarterProjectName
        agentEnabled = profile.wantsIronclaw
        councilEnabled = profile.wantsCouncil
        expectedFirstAction = Self.expectedFirstAction(for: profile, readiness: readiness, modelRoute: modelRoute)
        goalText = profile.goalText
        firstRunDraft = profile.firstRunDraft
        agentMissionSuggestion = profile.agentMissionSuggestion
        readinessStatus = Self.readinessStatus(for: profile, readiness: readiness, modelRoute: modelRoute)
        experienceSummary = profile.experienceMode == .power
            ? "Power mode keeps advanced routes visible."
            : "Beginner mode starts simple; power routes remain available later."
        starterWorkspaceSeeds = profile.setupWorkspaceSeeds
        starterSkillSuggestions = profile.setupSkillSuggestions
        starterPromptSuggestions = Array(profile.emptyStatePromptSuggestions.prefix(3))
        expectedRouteModelIDs = Self.expectedRouteModelIDs(
            for: modelRoute,
            readiness: readiness,
            routeDefaults: routeDefaults
        )
        id = [
            profile.useCases.map(\.rawValue).joined(separator: "+"),
            profile.experienceMode.rawValue,
            profile.contextStyle.rawValue,
            profile.wantsWeb ? "web" : "noweb",
            profile.wantsIronclaw ? "agent" : "noagent",
            profile.wantsCouncil ? "council" : "nocouncil",
            modelRoute.rawValue,
            expectedRouteModelIDs.joined(separator: "+")
        ].joined(separator: "-")
    }

    static let previews: [AppSetupPlan] = UserSetupUseCase.allCases.map { useCase in
        var profile = UserSetupProfile.defaults
        profile.useCase = useCase
        profile.useCases = [useCase]
        switch useCase {
        case .privateChat:
            profile.contextStyle = .simple
            profile.wantsCouncil = false
            profile.wantsIronclaw = false
        case .research:
            profile.contextStyle = .project
            profile.wantsCouncil = true
            profile.wantsIronclaw = false
        case .buildAgents:
            profile.contextStyle = .project
            profile.wantsCouncil = false
            profile.wantsIronclaw = true
        case .teamProjects:
            profile.contextStyle = .project
            profile.wantsCouncil = false
            profile.wantsIronclaw = false
        }
        return AppSetupPlan(profile: profile)
    }

    private static func focusBehavior(for profile: UserSetupProfile) -> String {
        let goal = profile.goalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !goal.isEmpty {
            return "Starts from your goal, then routes model, context, and web as needed."
        }
        switch profile.contextStyle {
        case .simple:
            return profile.wantsWeb ? "Auto routes private chat and live web when useful." : "Keeps answers private and avoids live web by default."
        case .project:
            return profile.wantsWeb ? "Uses project sources, saved links, files, and live web." : "Uses project sources and files before broader context."
        case .files:
            return "Prioritizes attached and project files before broader sources."
        }
    }

    private static func expectedFirstAction(
        for profile: UserSetupProfile,
        readiness: AppSetupReadinessSnapshot,
        modelRoute: AppSetupModelRoute
    ) -> String {
        let goal = profile.goalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !goal.isEmpty {
            return "Start from your goal"
        }
        if modelRoute == .ironclaw,
           !readiness.ironclawMobileAvailable,
           readiness.hostedIronclawAvailable {
            return "Open hosted agent"
        }
        if profile.wantsIronclaw, !readiness.ironclawMobileAvailable {
            return "Start private chat while agent tools load"
        }
        if profile.wantsCouncil, !readiness.councilReady {
            return readiness.modelCatalogLoaded
                ? "Start private chat; Council needs models"
                : "Start private chat while models load"
        }
        if modelRoute == .council {
            return "Ask the council"
        }
        switch profile.useCase {
        case .privateChat:
            return "Ask a private question"
        case .research:
            return "Start a research brief"
        case .buildAgents:
            return "Plan a build task"
        case .teamProjects:
            return "Create a Project"
        }
    }

    private static func readinessStatus(
        for profile: UserSetupProfile,
        readiness: AppSetupReadinessSnapshot,
        modelRoute: AppSetupModelRoute
    ) -> String {
        if profile.wantsIronclaw,
           !readiness.ironclawMobileAvailable,
           !readiness.hostedIronclawAvailable {
            return "IronClaw Mobile is still loading; private chat is ready first."
        }
        if modelRoute == .ironclaw,
           !readiness.ironclawMobileAvailable,
           readiness.hostedIronclawAvailable {
            return "Hosted IronClaw is ready; mobile runtime is unavailable."
        }
        if profile.wantsCouncil {
            if !readiness.modelCatalogLoaded {
                return "Council lineup will be checked after models load."
            }
            if !readiness.councilReady {
                return "Council needs at least two available models; private chat is ready first."
            }
        }
        if !readiness.privateModelAvailable {
            return "Private model catalog is still loading."
        }
        return "Ready: \(modelRoute.title)"
    }

    private static func expectedRouteModelIDs(
        for modelRoute: AppSetupModelRoute,
        readiness: AppSetupReadinessSnapshot,
        routeDefaults: SetupRouteDefaults
    ) -> [String] {
        switch modelRoute {
        case .privateModel:
            return normalizedRouteModelIDs([routeDefaults.privateModelID].compactMap { $0 })
        case .council:
            return normalizedRouteModelIDs(routeDefaults.councilModelIDs)
        case .ironclaw:
            return normalizedRouteModelIDs(
                [routeDefaults.preferredIronclawModelID(readiness: readiness)].compactMap { $0 }
            )
        }
    }

    private static func normalizedRouteModelIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for modelID in ids {
            let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else {
                continue
            }
            normalized.append(trimmed)
        }
        return normalized
    }
}

private extension ChatSourceMode {
    var setupMetadataTitle: String {
        switch self {
        case .all: "Project"
        default: title
        }
    }
}

struct AppSetupRouteDetailContent: Codable, Hashable {
    let title: String
    let summary: String
    let symbolName: String
}

extension AppSetupPlan {
    var routeDetailContent: AppSetupRouteDetailContent? {
        let labels = expectedRouteModelIDs.map(Self.setupRouteModelLabel)

        switch modelRoute {
        case .privateModel:
            guard let label = labels.first else { return nil }
            return AppSetupRouteDetailContent(
                title: "NEAR Private route",
                summary: "\(label) · attested when proof is fresh.",
                symbolName: "lock.shield"
            )
        case .council:
            guard !labels.isEmpty else { return nil }
            return AppSetupRouteDetailContent(
                title: labels.count > 2 ? "Council lineup (\(labels.count))" : "Council lineup",
                summary: "\(labels.joined(separator: " + ")) · proof depends on the selected models.",
                symbolName: "square.grid.2x2"
            )
        case .ironclaw:
            let usesHosted = expectedRouteModelIDs.contains(ModelOption.ironclawModelID)
            let label = labels.first ?? (usesHosted ? "Hosted IronClaw" : "IronClaw Mobile")
            return AppSetupRouteDetailContent(
                title: "IronClaw route",
                summary: usesHosted
                    ? "\(label) · Hosted Agent connection sends work outside this phone."
                    : "\(label) · phone agent route, outside NEAR Private proof.",
                symbolName: "terminal"
            )
        }
    }

    private static func setupRouteModelLabel(_ modelID: String) -> String {
        switch modelID {
        case ModelOption.ironclawModelID:
            return "Hosted IronClaw"
        case ModelOption.ironclawMobileModelID:
            return "IronClaw Mobile"
        default:
            return ModelOption.humanize(modelID: modelID)
        }
    }

    func firstRunCapabilityRecommendation(readiness: AppSetupReadinessSnapshot) -> CapabilityNextStep? {
        if councilEnabled, modelRoute != .council {
            guard readiness.modelCatalogLoaded, !readiness.nearCloudKeyConfigured else { return nil }
            return CapabilityNextStep(
                title: "Unlock a fuller council",
                detail: "This quick start opens private chat first because fewer than two council models are ready. Connect NEAR AI Cloud to add more models for research comparison.",
                actionTitle: "Connect Cloud",
                kind: .openCloud
            )
        }

        guard agentEnabled else { return nil }

        if !readiness.ironclawMobileAvailable, readiness.hostedIronclawAvailable {
            return CapabilityNextStep(
                title: "Hosted agent is available",
                detail: "This quick start opens private chat first because IronClaw Mobile is unavailable. Open the hosted agent when you need repo, shell, or approval-gated work.",
                actionTitle: "Open Agent",
                kind: .openAgent
            )
        }

        guard modelRoute != .ironclaw else { return nil }

        return CapabilityNextStep(
            title: "Finish agent setup",
            detail: "This quick start opens private chat first. Connect Hosted IronClaw to use repo, shell, or approval-gated Agent work.",
            actionTitle: "Connect Agent",
            kind: .openAgent
        )
    }
}

struct SetupRuntimeSnapshot: Equatable {
    var modelRoute: AppSetupModelRoute
    var focusMode: ChatSourceMode
    var webSearchEnabled: Bool
    var researchModeEnabled: Bool
    var selectedProjectName: String?
    var selectedModelID: String? = nil
    var councilModelIDs: [String] = []
}

struct SetupRestoreDifference: Equatable, Hashable, Identifiable {
    let title: String
    let savedValue: String
    let currentValue: String

    var id: String {
        "\(title)-\(savedValue)-\(currentValue)"
    }
}

struct SetupRestoreState: Equatable {
    let needsRestore: Bool
    let summaryText: String
    let differences: [SetupRestoreDifference]
}

enum SetupRestorePlanner {
    static func evaluate(
        profile: UserSetupProfile,
        plan: AppSetupPlan,
        runtime: SetupRuntimeSnapshot
    ) -> SetupRestoreState {
        if runtime.modelRoute != plan.modelRoute {
            return SetupRestoreState(
                needsRestore: true,
                summaryText: "Current route changed. Restore saved setup to return to your saved route.",
                differences: [
                    SetupRestoreDifference(
                        title: "Route",
                        savedValue: routeDifferenceLabel(for: plan.modelRoute),
                        currentValue: runtime.modelRoute.title
                    )
                ]
            )
        }

        if let routeSelectionDrift = routeSelectionDrift(profile: profile, plan: plan, runtime: runtime) {
            return routeSelectionDrift
        }

        let expectedResearchMode = profile.useCases.contains(.research) && plan.modelRoute != .ironclaw
        if runtime.focusMode != plan.focusMode ||
            runtime.webSearchEnabled != profile.wantsWeb ||
            runtime.researchModeEnabled != expectedResearchMode {
            var differences: [SetupRestoreDifference] = []
            if runtime.focusMode != plan.focusMode {
                differences.append(
                    SetupRestoreDifference(
                        title: "Focus",
                        savedValue: plan.focusMode.title,
                        currentValue: runtime.focusMode.title
                    )
                )
            }
            if runtime.webSearchEnabled != profile.wantsWeb {
                differences.append(
                    SetupRestoreDifference(
                        title: "Web",
                        savedValue: enabledLabel(profile.wantsWeb),
                        currentValue: enabledLabel(runtime.webSearchEnabled)
                    )
                )
            }
            if runtime.researchModeEnabled != expectedResearchMode {
                differences.append(
                    SetupRestoreDifference(
                        title: "Research",
                        savedValue: enabledLabel(expectedResearchMode),
                        currentValue: enabledLabel(runtime.researchModeEnabled)
                    )
                )
            }
            return SetupRestoreState(
                needsRestore: true,
                summaryText: "Context defaults changed. Restore saved setup to recover your saved web, focus, and research defaults.",
                differences: differences
            )
        }

        if let starterProjectName = plan.starterProjectName {
            if runtime.selectedProjectName != starterProjectName {
                return SetupRestoreState(
                    needsRestore: true,
                    summaryText: "\"\(starterProjectName)\" is not active right now. Restore saved setup to reopen that Project.",
                    differences: [
                        SetupRestoreDifference(
                            title: "Project",
                            savedValue: starterProjectName,
                            currentValue: runtime.selectedProjectName ?? "No active project"
                        )
                    ]
                )
            }
        } else if runtime.selectedProjectName != nil && profile.contextStyle == .simple {
            return SetupRestoreState(
                needsRestore: true,
                summaryText: "A project is active, but your saved setup starts without project memory.",
                differences: [
                    SetupRestoreDifference(
                        title: "Project",
                        savedValue: "No active project",
                        currentValue: runtime.selectedProjectName ?? "No active project"
                    )
                ]
            )
        }

        return SetupRestoreState(
            needsRestore: false,
            summaryText: profile.normalizedGoalText.isEmpty
                ? "Your saved setup is ready to reopen with the same route and focus defaults."
                : "Your saved setup is ready to reopen with the same route, focus, and starter prompt.",
            differences: []
        )
    }

    private static func routeSelectionDrift(
        profile: UserSetupProfile,
        plan: AppSetupPlan,
        runtime: SetupRuntimeSnapshot
    ) -> SetupRestoreState? {
        let expectedModelIDs = normalizedRouteModelIDs(plan.expectedRouteModelIDs)
        guard !expectedModelIDs.isEmpty else { return nil }

        switch plan.modelRoute {
        case .privateModel:
            let currentModelID = runtime.selectedModelID?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard currentModelID?.isEmpty == false,
                  currentModelID?.caseInsensitiveCompare(expectedModelIDs[0]) != .orderedSame else {
                return nil
            }
            return SetupRestoreState(
                needsRestore: true,
                summaryText: profile.useCases.contains(.research)
                    ? "Current research model changed. Restore saved setup to recover your preferred starter route."
                    : "Current private model changed. Restore saved setup to recover your preferred starter route.",
                differences: [
                    SetupRestoreDifference(
                        title: profile.useCases.contains(.research) ? "Research model" : "Model",
                        savedValue: modelLabel(for: expectedModelIDs[0]),
                        currentValue: modelLabel(for: currentModelID)
                    )
                ]
            )
        case .council:
            let currentCouncilModelIDs = normalizedRouteModelIDs(runtime.councilModelIDs)
            guard currentCouncilModelIDs != expectedModelIDs else { return nil }
            return SetupRestoreState(
                needsRestore: true,
                summaryText: "Council lineup changed. Restore saved setup to recover your saved model mix.",
                differences: [
                    SetupRestoreDifference(
                        title: "Council",
                        savedValue: lineupLabel(for: expectedModelIDs),
                        currentValue: lineupLabel(for: currentCouncilModelIDs)
                    )
                ]
            )
        case .ironclaw:
            let currentModelID = runtime.selectedModelID?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard currentModelID?.isEmpty == false,
                  currentModelID?.caseInsensitiveCompare(expectedModelIDs[0]) != .orderedSame else {
                return nil
            }
            let expectedAgentRoute = expectedModelIDs[0].caseInsensitiveCompare(ModelOption.ironclawModelID) == .orderedSame
                ? "Hosted IronClaw"
                : "IronClaw Mobile"
            return SetupRestoreState(
                needsRestore: true,
                summaryText: "Current agent route changed. Restore saved setup to return to \(expectedAgentRoute).",
                differences: [
                    SetupRestoreDifference(
                        title: "Agent route",
                        savedValue: modelLabel(for: expectedModelIDs[0]),
                        currentValue: modelLabel(for: currentModelID)
                    )
                ]
            )
        }
    }

    private static func enabledLabel(_ value: Bool) -> String {
        value ? "On" : "Off"
    }

    private static func routeDifferenceLabel(for route: AppSetupModelRoute) -> String {
        switch route {
        case .council:
            return "Council"
        case .privateModel, .ironclaw:
            return route.title
        }
    }

    private static func lineupLabel(for ids: [String]) -> String {
        let labels = ids.map(modelLabel(for:))
        return labels.isEmpty ? "No saved lineup" : labels.joined(separator: " + ")
    }

    private static func modelLabel(for modelID: String?) -> String {
        guard let trimmed = modelID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return "Unavailable"
        }
        switch trimmed {
        case ModelOption.ironclawModelID:
            return "Hosted IronClaw"
        case ModelOption.ironclawMobileModelID:
            return "IronClaw Mobile"
        default:
            return ModelOption.humanize(modelID: trimmed)
        }
    }

    private static func normalizedRouteModelIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for modelID in ids {
            let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else {
                continue
            }
            normalized.append(trimmed)
        }
        return normalized
    }
}

enum CapabilityRouteBlock: String, Codable, Equatable, Sendable {
    case nearCloudKeyRequired
    case hostedIronclawEndpointRequired
    case councilNeedsModels
}

enum CapabilityNextStepKind: String, Codable, Equatable, Sendable {
    case openSecurity
    case openCloud
    case openAgent
    case useAutoCouncil
    case rerunSetup
}

enum AccountSettingsDeepLink: String, Codable, Equatable, Hashable, Sendable {
    case nearCloudKeys
    case ironclawAgent

    init?(capabilityNextStepKind: CapabilityNextStepKind) {
        switch capabilityNextStepKind {
        case .openCloud:
            self = .nearCloudKeys
        case .openAgent:
            self = .ironclawAgent
        case .openSecurity, .useAutoCouncil, .rerunSetup:
            return nil
        }
    }
}

struct CapabilityNextStep: Codable, Equatable, Sendable {
    let title: String
    let detail: String
    let actionTitle: String
    let kind: CapabilityNextStepKind
}

enum CapabilityNextStepPlanner {
    static func recommend(
        routeBlock: CapabilityRouteBlock?,
        setupPlan: AppSetupPlan,
        currentRoute: ChatRouteKind,
        hasFreshPrivateProof: Bool,
        hostedIronclawAvailable: Bool,
        autoCouncilReady: Bool
    ) -> CapabilityNextStep? {
        switch routeBlock {
        case .nearCloudKeyRequired:
            return CapabilityNextStep(
                title: "Connect NEAR AI Cloud",
                detail: "This route is blocked until NEAR AI Cloud is connected. Private chat still works right now.",
                actionTitle: "Connect Cloud",
                kind: .openCloud
            )
        case .hostedIronclawEndpointRequired:
            return CapabilityNextStep(
                title: "Connect hosted agent",
                detail: "Phone-safe Agent skills are ready, but hosted Agent routes need a Hosted IronClaw URL.",
                actionTitle: "Connect Agent",
                kind: .openAgent
            )
        case .councilNeedsModels:
            if autoCouncilReady {
                return CapabilityNextStep(
                    title: "Restore the Council lineup",
                    detail: "Recommended Council can repopulate a working lineup so you can compare models without rebuilding it by hand.",
                    actionTitle: "Use recommended Council",
                    kind: .useAutoCouncil
                )
            }
        case nil:
            break
        }

        if setupPlan.agentEnabled && !currentRoute.isIronclawRoute && !hostedIronclawAvailable {
            return CapabilityNextStep(
                title: "Finish agent setup",
                detail: "Your defaults expect Agent work. Connect Hosted IronClaw when you need repo, shell, or approval-gated tasks.",
                actionTitle: "Connect Agent",
                kind: .openAgent
            )
        }

        if setupPlan.councilEnabled && autoCouncilReady {
            return CapabilityNextStep(
                title: "Try recommended Council",
                detail: "Your defaults favor multi-model comparison. Start with the ready lineup and customize later if needed.",
                actionTitle: "Use recommended Council",
                kind: .useAutoCouncil
            )
        }

        if currentRoute == .nearPrivate && !hasFreshPrivateProof {
            return CapabilityNextStep(
                title: "Check private proof",
                detail: "Private chat is ready now. Fetch or refresh proof when you need signed route evidence for the current model.",
                actionTitle: "Open Proof report",
                kind: .openSecurity
            )
        }

        return CapabilityNextStep(
            title: "Adjust your defaults",
            detail: "Rerun setup if you want to change the app's first-run route, context, or capability defaults.",
            actionTitle: "Rerun Setup",
            kind: .rerunSetup
        )
    }
}

enum UserSetupStorage {
    static let completedKey = "userSetupProfileV1Completed"
    static let profileKey = "userSetupProfileV1Data"
    static let launchCardPendingKey = "userSetupLaunchCardPending"
    private static let scopedVersion = "v2"
    private static let protectedStoreDirectoryName = "SetupProfiles"
    private static let protectedProfileFilename = "profile.json"
    private static let protectedCompletionFilename = "completed.txt"
    private static let protectedLaunchCardPendingFilename = "launch-card-pending.txt"

    static func accountID(userID: String?, sessionID: String?, token: String?) -> String? {
        if let userID = userID?.trimmingCharacters(in: .whitespacesAndNewlines), !userID.isEmpty {
            return "user:\(userID)"
        }
        if let sessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines), !sessionID.isEmpty {
            return "session:\(sessionID)"
        }
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return "token:\(stableTokenDigest(token))"
        }
        return nil
    }

    static func isFallbackAccountID(_ accountID: String) -> Bool {
        accountID.hasPrefix("session:") || accountID.hasPrefix("token:")
    }

    static func isCompleted(for accountID: String, defaults: UserDefaults = .standard) -> Bool {
        if usesProtectedStorage(defaults) {
            if let data = readProtectedData(for: accountID, filename: protectedCompletionFilename),
               let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return value == "true"
            }
            return defaults.bool(forKey: scopedCompletedKey(for: accountID))
        }
        return defaults.bool(forKey: scopedCompletedKey(for: accountID))
    }

    static func load(for accountID: String, defaults: UserDefaults = .standard) -> UserSetupProfile? {
        if usesProtectedStorage(defaults),
           let data = readProtectedData(for: accountID, filename: protectedProfileFilename),
           let profile = try? JSONDecoder().decode(UserSetupProfile.self, from: data) {
            return profile
        }
        guard let data = defaults.data(forKey: scopedProfileKey(for: accountID)) else { return nil }
        return try? JSONDecoder().decode(UserSetupProfile.self, from: data)
    }

    static func save(_ profile: UserSetupProfile, for accountID: String, defaults: UserDefaults = .standard) {
        if usesProtectedStorage(defaults) {
            if let data = try? JSONEncoder().encode(profile.normalizedForDefaults) {
                writeProtectedData(data, for: accountID, filename: protectedProfileFilename)
            }
            writeProtectedData(Data("true".utf8), for: accountID, filename: protectedCompletionFilename)
            writeProtectedData(Data("true".utf8), for: accountID, filename: protectedLaunchCardPendingFilename)
            defaults.removeObject(forKey: scopedProfileKey(for: accountID))
            defaults.removeObject(forKey: scopedCompletedKey(for: accountID))
            defaults.removeObject(forKey: scopedLaunchCardPendingKey(for: accountID))
            return
        }
        if let data = try? JSONEncoder().encode(profile.normalizedForDefaults) {
            defaults.set(data, forKey: scopedProfileKey(for: accountID))
        }
        defaults.set(true, forKey: scopedCompletedKey(for: accountID))
        defaults.set(true, forKey: scopedLaunchCardPendingKey(for: accountID))
    }

    static func saveWithoutPendingLaunchCard(
        _ profile: UserSetupProfile,
        for accountID: String,
        defaults: UserDefaults = .standard
    ) {
        save(profile, for: accountID, defaults: defaults)
        clearPendingLaunchCard(for: accountID, defaults: defaults)
    }

    static func completeFirstRunPrivateChat(
        for accountID: String,
        defaults: UserDefaults = .standard
    ) -> UserSetupProfile {
        let profile = UserSetupProfile.defaults
        saveWithoutPendingLaunchCard(profile, for: accountID, defaults: defaults)
        return profile
    }

    static func completeFirstRunQuickStart(
        for accountID: String,
        preset: UserSetupStarterPreset,
        defaults: UserDefaults = .standard
    ) -> UserSetupProfile {
        let profile = preset.quickStartProfile
        saveWithoutPendingLaunchCard(profile, for: accountID, defaults: defaults)
        return profile
    }

    static func clearCompletion(for accountID: String, defaults: UserDefaults = .standard) {
        if usesProtectedStorage(defaults) {
            writeProtectedData(Data("false".utf8), for: accountID, filename: protectedCompletionFilename)
            defaults.removeObject(forKey: scopedCompletedKey(for: accountID))
            return
        }
        defaults.set(false, forKey: scopedCompletedKey(for: accountID))
    }

    static func hasPendingLaunchCard(for accountID: String, defaults: UserDefaults = .standard) -> Bool {
        if usesProtectedStorage(defaults) {
            if let data = readProtectedData(for: accountID, filename: protectedLaunchCardPendingFilename),
               let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() {
                return text == "true" || text == "1"
            }
            if defaults.object(forKey: scopedLaunchCardPendingKey(for: accountID)) != nil {
                return defaults.bool(forKey: scopedLaunchCardPendingKey(for: accountID))
            }
            return false
        }
        return defaults.bool(forKey: scopedLaunchCardPendingKey(for: accountID))
    }

    static func clearPendingLaunchCard(for accountID: String, defaults: UserDefaults = .standard) {
        if usesProtectedStorage(defaults) {
            writeProtectedData(Data("false".utf8), for: accountID, filename: protectedLaunchCardPendingFilename)
            defaults.removeObject(forKey: scopedLaunchCardPendingKey(for: accountID))
            return
        }
        defaults.set(false, forKey: scopedLaunchCardPendingKey(for: accountID))
    }

    static func presentationProfile(
        for accountID: String,
        currentDefaults: UserSetupProfile,
        defaults: UserDefaults = .standard
    ) -> UserSetupProfile {
        if let stored = load(for: accountID, defaults: defaults) {
            return stored
        }
        if isCompleted(for: accountID, defaults: defaults) {
            return currentDefaults.normalizedForDefaults
        }
        return .defaults
    }

    static func needsFirstRunSetup(for accountID: String, defaults: UserDefaults = .standard) -> Bool {
        load(for: accountID, defaults: defaults) == nil &&
            !isCompleted(for: accountID, defaults: defaults)
    }

    static func migrate(from oldAccountID: String, to newAccountID: String, defaults: UserDefaults = .standard) {
        guard oldAccountID != newAccountID,
              isFallbackAccountID(oldAccountID),
              !isCompleted(for: newAccountID, defaults: defaults) else { return }
        if let profile = load(for: oldAccountID, defaults: defaults) {
            save(profile, for: newAccountID, defaults: defaults)
        } else if isCompleted(for: oldAccountID, defaults: defaults) {
            if usesProtectedStorage(defaults) {
                writeProtectedData(Data("true".utf8), for: newAccountID, filename: protectedCompletionFilename)
            } else {
                defaults.set(true, forKey: scopedCompletedKey(for: newAccountID))
            }
        }
        if hasPendingLaunchCard(for: oldAccountID, defaults: defaults) {
            if usesProtectedStorage(defaults) {
                writeProtectedData(Data("true".utf8), for: newAccountID, filename: protectedLaunchCardPendingFilename)
            } else {
                defaults.set(true, forKey: scopedLaunchCardPendingKey(for: newAccountID))
            }
        }
        if usesProtectedStorage(defaults) {
            removeProtectedData(for: oldAccountID, filename: protectedProfileFilename)
            removeProtectedData(for: oldAccountID, filename: protectedCompletionFilename)
            removeProtectedData(for: oldAccountID, filename: protectedLaunchCardPendingFilename)
            defaults.removeObject(forKey: scopedProfileKey(for: oldAccountID))
            defaults.removeObject(forKey: scopedCompletedKey(for: oldAccountID))
            defaults.removeObject(forKey: scopedLaunchCardPendingKey(for: oldAccountID))
        } else {
            defaults.removeObject(forKey: scopedProfileKey(for: oldAccountID))
            defaults.removeObject(forKey: scopedCompletedKey(for: oldAccountID))
            defaults.removeObject(forKey: scopedLaunchCardPendingKey(for: oldAccountID))
        }
    }

    @available(*, deprecated, message: "Use account-scoped save(_:for:) instead.")
    static func save(_ profile: UserSetupProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    @available(*, deprecated, message: "Use account-scoped clearCompletion(for:) instead.")
    static func clearCompletion() {
        UserDefaults.standard.set(false, forKey: completedKey)
    }

    private static func scopedCompletedKey(for accountID: String) -> String {
        "\(completedKey).\(scopedVersion).\(normalizedAccountID(accountID))"
    }

    private static func scopedProfileKey(for accountID: String) -> String {
        "\(profileKey).\(scopedVersion).\(normalizedAccountID(accountID))"
    }

    private static func scopedLaunchCardPendingKey(for accountID: String) -> String {
        "\(launchCardPendingKey).\(scopedVersion).\(normalizedAccountID(accountID))"
    }

    private static func usesProtectedStorage(_ defaults: UserDefaults) -> Bool {
        defaults === UserDefaults.standard
    }

    private static func protectedDirectoryURL(for accountID: String) -> URL? {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return baseURL
            .appendingPathComponent("NEARPrivateChat", isDirectory: true)
            .appendingPathComponent(protectedStoreDirectoryName, isDirectory: true)
            .appendingPathComponent(normalizedAccountID(accountID), isDirectory: true)
    }

    private static func protectedFileURL(for accountID: String, filename: String) -> URL? {
        protectedDirectoryURL(for: accountID)?.appendingPathComponent(filename, isDirectory: false)
    }

    private static func readProtectedData(for accountID: String, filename: String) -> Data? {
        guard let url = protectedFileURL(for: accountID, filename: filename) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func writeProtectedData(_ data: Data, for accountID: String, filename: String) {
        guard let directoryURL = protectedDirectoryURL(for: accountID),
              let fileURL = protectedFileURL(for: accountID, filename: filename) else { return }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            var mutableDirectoryURL = directoryURL
            try? mutableDirectoryURL.setResourceValues(directoryValues)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            var fileValues = URLResourceValues()
            fileValues.isExcludedFromBackup = true
            var mutableFileURL = fileURL
            try? mutableFileURL.setResourceValues(fileValues)
        } catch {
            return
        }
    }

    private static func removeProtectedData(for accountID: String, filename: String) {
        guard let url = protectedFileURL(for: accountID, filename: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func normalizedAccountID(_ accountID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = accountID.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar).description : "_"
        }
        return String(scalars.joined()).prefix(96).description
    }

    private static func stableTokenDigest(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
