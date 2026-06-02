import Foundation

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
            : "Beginner mode starts simple; power routes stay available later."
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
            return "Open Hosted IronClaw"
        }
        if profile.wantsIronclaw, !readiness.ironclawMobileAvailable {
            return "Start private chat while Agent tools load"
        }
        if profile.wantsCouncil, !readiness.councilReady {
            return readiness.modelCatalogLoaded
                ? "Start private chat; Council needs models"
                : "Start private chat while models load"
        }
        if modelRoute == .council {
            return "Ask the Council"
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
