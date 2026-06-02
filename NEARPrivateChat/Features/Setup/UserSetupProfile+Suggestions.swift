import Foundation

extension UserSetupProfile {
    var firstRunDraft: String? {
        let orderedUseCases = useCases.setupOrderedUnique
        let goal = normalizedGoalText
        if orderedUseCases.count > 1,
           let combinedStarter = combinedStarterSuggestion(for: orderedUseCases, goal: goal) {
            return combinedStarter.prompt
        }

        if !goal.isEmpty, useCases.contains(.research) {
            return "Write a sourced brief for this goal: \(goal)"
        }
        if !goal.isEmpty, useCases.contains(.buildAgents) {
            return "Plan the first build or repo task for this goal: \(goal)"
        }
        if !goal.isEmpty, useCases.contains(.teamProjects) || contextStyle != .simple {
            return "Organize this Project and next actions for this goal: \(goal)"
        }
        if !goal.isEmpty {
            return "Work on this goal: \(goal)"
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
                        prompt: "Work on this goal: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "Break into steps",
                        symbolName: "list.bullet.clipboard",
                        prompt: "Break this goal into the next private steps: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "Best first question",
                        symbolName: "questionmark.bubble",
                        prompt: "The most important first question to ask for this goal: \(goal)"
                    )
                ]
            }
            return [
                SetupPromptSuggestion(
                    title: "Private question",
                    symbolName: "lock.shield",
                    prompt: "Think through a private question."
                ),
                SetupPromptSuggestion(
                    title: "Pressure-test",
                    symbolName: "scale.3d",
                    prompt: "Pressure-test this decision; show the strongest risks and tradeoffs: "
                ),
                SetupPromptSuggestion(
                    title: "Draft message",
                    symbolName: "text.bubble",
                    prompt: "Draft a clear message about this situation: "
                )
            ]
        case .research:
            if !goal.isEmpty {
                return [
                    SetupPromptSuggestion(
                        title: "Start brief",
                        symbolName: "doc.text.magnifyingglass",
                        prompt: "Write a sourced brief for this goal: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "Find sources",
                        symbolName: "globe",
                        prompt: "Find the strongest current sources, dates, and contradictions for this goal: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "Recommend next step",
                        symbolName: "arrow.forward.circle",
                        prompt: "Turn this goal into a concise recommendation with citations: \(goal)"
                    )
                ]
            }
            return [
                SetupPromptSuggestion(
                    title: "Research brief",
                    symbolName: "doc.text.magnifyingglass",
                    prompt: "Write a sourced brief on the latest AI developments."
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
                        prompt: "Turn this goal into a safe patch plan with focused verification: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "Repo checklist",
                        symbolName: "checklist",
                        prompt: "Make a repo inspection checklist for this goal before any code changes: \(goal)"
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
                    prompt: "Review this repo for the highest-impact safe fix to make first: "
                ),
                SetupPromptSuggestion(
                    title: "Focused tests",
                    symbolName: "checkmark.seal",
                    prompt: "List the focused tests and verification steps for this change: "
                )
            ]
        case .teamProjects:
            if !goal.isEmpty {
                return [
                    SetupPromptSuggestion(
                        title: "Organize project",
                        symbolName: "folder.badge.gearshape",
                        prompt: "Organize this Project and next actions for this goal: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "Add context",
                        symbolName: "paperclip",
                        prompt: "What files, links, notes, or instructions to add first for this goal: \(goal)"
                    ),
                    SetupPromptSuggestion(
                        title: "First Project chat",
                        symbolName: "bubble.left.and.bubble.right",
                        prompt: "Draft the best first Project chat prompt for this goal: \(goal)"
                    )
                ]
            }
            return [
                SetupPromptSuggestion(
                    title: "Project setup",
                    symbolName: "folder.badge.gearshape",
                    prompt: "Set up this Project: what files, links, instructions, and first chat to add?"
                ),
                SetupPromptSuggestion(
                    title: "Find missing context",
                    symbolName: "magnifyingglass",
                    prompt: "Tell me what's missing in this Project context before I start work: "
                ),
                SetupPromptSuggestion(
                    title: "Next-step plan",
                    symbolName: "arrow.forward.circle",
                    prompt: "Turn this Project context into a concise next-step plan."
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
            primaryPrompt = goal.isEmpty ? "Get me started." : "Work on this goal"
        case .research:
            primaryPrompt = goal.isEmpty ? "Write a sourced brief" : "Write a sourced brief for this goal"
        case .buildAgents:
            primaryPrompt = goal.isEmpty ? "Plan the first repo task" : "Plan the first repo task for this goal"
        case .teamProjects:
            primaryPrompt = goal.isEmpty ? "Set up this Project" : "Organize this Project and next actions for this goal"
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
}
