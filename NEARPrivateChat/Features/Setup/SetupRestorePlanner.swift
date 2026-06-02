import Foundation

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
