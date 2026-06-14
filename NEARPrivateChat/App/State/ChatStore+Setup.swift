import Foundation

@MainActor
extension ChatStore {
    func setupProfileSnapshot(_ rawProfile: UserSetupProfile) -> UserSetupProfile {
        var profile = rawProfile.normalizedForDefaults
        profile.routeDefaults = resolvedSetupRouteDefaults(for: profile)
        return profile
    }

    func applySetupProfile(_ rawProfile: UserSetupProfile) {
        let profile = setupProfileSnapshot(rawProfile)
        let routeDefaults = resolvedSetupRouteDefaults(for: profile)
        let readiness = AppSetupReadinessSnapshot(
            modelCatalogLoaded: !models.isEmpty || routeDefaults.councilModelIDs.count > 1,
            privateModelAvailable: pickerModels.contains { !$0.isExternalModel },
            defaultCouncilModelCount: max(defaultCouncilModels.count, routeDefaults.councilModelIDs.count),
            ironclawMobileAvailable: agentModels.contains { $0.id == ModelOption.ironclawMobileModelID },
            hostedIronclawAvailable: ironclawRemoteWorkstationAvailable,
            nearCloudKeyConfigured: nearCloudKeyConfigured
        )
        let plan = AppSetupPlan(profile: profile, readiness: readiness, routeDefaults: routeDefaults)
        webSearchEnabled = profile.wantsWeb
        sourceMode = plan.focusMode
        researchModeEnabled = profile.useCases.contains(.research) && plan.modelRoute != .ironclaw
        if soulMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            soulMarkdown = SetupSoulPromptBuilder.markdown(for: profile)
        }

        let requestedCouncilModelIDs = plan.modelRoute == .council ? routeDefaults.councilModelIDs : []
        switch plan.modelRoute {
        case .ironclaw:
            selectedModel = routeDefaults.preferredIronclawModelID(readiness: readiness) ?? ModelOption.ironclawMobileModelID
            councilModelIDs = []
        case .council:
            councilModelIDs = requestedCouncilModelIDs
            selectedModel = requestedCouncilModelIDs.first ?? preferredAvailableModel() ?? Self.defaultModelID
        case .privateModel:
            selectedModel = SetupRouteDefaultResolver.usablePrivateModelID(routeDefaults.privateModelID) ??
                preferredAvailableModel() ??
                Self.defaultModelID
            councilModelIDs = canUseInCouncil(selectedModel) ? [selectedModel] : []
        }

        if let projectName = profile.setupStarterProjectName {
            let project = projectStore.ensureProject(named: projectName, includeConversationID: nil)
            projectStore.selectProjectID(project.id)
            _ = projectStore.updateInstructionsIfEmpty(
                projectID: project.id,
                instructions: profile.setupProjectInstructions
            )
            _ = projectStore.seedSetupMetadata(projectID: project.id, profile: profile, plan: plan)
        } else if profile.contextStyle == .simple {
            projectStore.selectAllProjects()
        }

        let shouldSeedStarterDraft = shouldSeedSetupStarterDraft(for: profile)
        if let draft = profile.firstRunDraft, shouldSeedStarterDraft {
            startNewConversation(resetInteractionDefaults: false)
            self.draft = draft
            conversationStore.requestOpenSelectedConversation()
            showBanner(setupAppliedBanner(for: plan, profile: profile, openedDraft: true))
        } else {
            showBanner(setupAppliedBanner(for: plan, profile: profile, openedDraft: false))
        }
    }

    private func resolvedSetupRouteDefaults(for profile: UserSetupProfile) -> SetupRouteDefaults {
        SetupRouteDefaultResolver.resolvedDefaults(
            stored: profile.routeDefaults,
            fallback: setupRouteDefaults,
            preferredAvailableModelID: preferredAvailableModel(),
            agentModelIDs: Set(agentModels.map(\.id)),
            defaultModelID: Self.defaultModelID,
            maxCouncilModels: ModelCatalogStore.maxCouncilModels
        )
    }

    private func setupAppliedBanner(for plan: AppSetupPlan, profile: UserSetupProfile, openedDraft: Bool) -> String {
        if profile.wantsIronclaw, plan.modelRoute != .ironclaw {
            return openedDraft
                ? "Setup applied. Private prompt ready while Agent tools stay unavailable."
                : "Setup applied. Private route is ready while Agent tools stay unavailable."
        }
        if profile.wantsCouncil, plan.modelRoute != .council {
            return openedDraft
                ? "Setup applied. Private prompt ready while Council finishes loading."
                : "Setup applied. Private route is ready while Council finishes loading."
        }

        switch plan.modelRoute {
        case .ironclaw:
            return openedDraft ? "Setup applied. Agent prompt ready." : "Setup applied. Agent route ready."
        case .council:
            return openedDraft ? "Setup applied. Council prompt ready." : "Setup applied. Council route ready."
        case .privateModel:
            return openedDraft ? "Setup applied. First prompt ready." : "Setup applied."
        }
    }

    private func shouldSeedSetupStarterDraft(for profile: UserSetupProfile) -> Bool {
        if !profile.normalizedGoalText.isEmpty {
            return true
        }
        let hasDraftText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasDraftText || !pendingAttachments.isEmpty || !pendingLargePasteTexts.isEmpty {
            return false
        }
        return messages.isEmpty
    }
}
