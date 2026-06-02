import Foundation

extension UserSetupProfile {
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
                detail: "Saved setup runs Agent work for this goal first.",
                prompt: "Plan the first build or repo task for this goal: \(goal)"
            )
        }

        return SetupAgentMissionSuggestion(
            title: "Use saved Agent starter",
            detail: "Saved setup keeps repo and Agent work ready from day one.",
            prompt: UserSetupUseCase.buildAgents.starterPrompt
        )
    }
}
