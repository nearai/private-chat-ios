import Foundation

extension UserSetupProfile {
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
