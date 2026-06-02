import Foundation

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
            return "Launch a phone-safe Agent planning draft."
        case .projectWorkspace:
            return "Open a project-first draft with saved context."
        }
    }

    var setupExampleGoalText: String {
        switch self {
        case .privateQuestion:
            return "Think through a private question"
        case .researchBrief:
            return "Research the latest AI developments"
        case .agentMission:
            return "Plan a phone-launched agent task for a repo or research project"
        case .projectWorkspace:
            return "Set up a shared Project with files, links, and reusable instructions"
        }
    }

    var prompt: String {
        switch self {
        case .privateQuestion: "Think through a private question."
        case .researchBrief: "Write a sourced brief on the latest AI developments."
        case .agentMission: "Plan a phone-launched agent task for a repo or research project."
        case .projectWorkspace: "Set up this Project: what files, links, instructions, and first chat to add?"
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
