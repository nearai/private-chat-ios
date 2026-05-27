import SwiftUI

struct EmptyChatView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var showingAccountSettings = false

    private struct EmptyPromptSuggestion: Identifiable {
        var id: String { title }
        let title: String
        let symbolName: String
        let prompt: String
    }

    private struct SetupQuickstartState {
        let profile: UserSetupProfile
        let plan: AppSetupPlan
        let restoreState: SetupRestoreState

        var hasStarterPrompt: Bool {
            plan.firstRunDraft != nil
        }

        var primaryActionTitle: String {
            switch (restoreState.needsRestore, hasStarterPrompt) {
            case (true, true):
                return "Restore saved setup"
            case (true, false):
                return "Restore saved setup"
            case (false, true):
                return "Use starter prompt"
            case (false, false):
                return "Setup ready"
            }
        }

        var primaryActionSymbolName: String {
            switch (restoreState.needsRestore, hasStarterPrompt) {
            case (true, _):
                return "arrow.counterclockwise"
            case (false, true):
                return "text.cursor"
            case (false, false):
                return "checkmark.circle"
            }
        }
    }

    private var emptyHeroSubtitle: String {
        if let project = chatStore.selectedProject {
            let contextCount = chatStore.activeProjectContextAttachments.count + chatStore.activeProjectContextLinks.count
            return contextCount > 0 ? "\(project.name) context is ready." : "\(project.name) is selected."
        }
        if chatStore.selectedModelOption?.isIronclawHostedModel == true {
            return chatStore.ironclawRemoteWorkstationAvailable ? "Hosted agent ready." : "Connect hosted IronClaw to run workstation tasks."
        }
        if chatStore.selectedModelOption?.isIronclawMobileRuntime == true {
            return chatStore.ironclawRemoteWorkstationAvailable ? "Hosted agent ready." : "Mobile agent ready."
        }
        if let setupProfileWithGoal {
            return setupProfileWithGoal.emptyStateSubtitle
        }
        if chatStore.isCouncilModeEnabled {
            return "Council is ready to compare answers."
        }
        if chatStore.researchModeEnabled && !chatStore.selectedRouteUsesNearCloud {
            return "Search current sources."
        }
        if let setupProfile {
            return setupProfile.emptyStateSubtitle
        }
        return "Ask normally. NEAR picks web, project context, or an agent when needed."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                PrivacySeal(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What do you want to ask?")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(emptyHeroSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let setupQuickstartState {
                setupQuickstartCard(setupQuickstartState)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(emptyPromptSuggestions) { suggestion in
                        suggestionButton(suggestion)
                    }
                }
                .padding(.vertical, 1)

                Menu {
                    ForEach(emptyPromptSuggestions) { suggestion in
                        Button {
                            fillDraft(for: suggestion)
                        } label: {
                            Label(suggestion.title, systemImage: suggestion.symbolName)
                        }
                    }
                } label: {
                    Label("Prompt examples", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(height: 34)
                        .padding(.horizontal, 10)
                        .background(Color.secondarySurface, in: Capsule())
                }
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
        .sheet(isPresented: $showingAccountSettings) {
            AccountSettingsView(onRunSetupAgain: {})
                .environmentObject(sessionStore)
                .environmentObject(chatStore)
        }
    }

    private func suggestionButton(_ suggestion: EmptyPromptSuggestion) -> some View {
        Button {
            fillDraft(for: suggestion)
        } label: {
            Label(suggestion.title, systemImage: suggestion.symbolName)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.secondarySurface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use suggestion, \(suggestion.title)")
        .accessibilityHint("Fills the composer without sending.")
    }

    private func setupQuickstartCard(_ state: SetupQuickstartState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: state.plan.modelRoute.symbolName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 36, height: 36)
                    .background(Color.appSymbolBlueBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Setup quickstart")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.primaryAction)
                    Text(state.plan.launchCardTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(state.plan.launchCardSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !state.plan.launchCardMetadata.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(state.plan.launchCardMetadata, id: \.self) { item in
                            SetupLaunchPill(title: item)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .scrollClipDisabled()
            }

            if let firstRunDraft = state.plan.firstRunDraft {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Starter prompt")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.textSecondary)
                    Text(firstRunDraft)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.secondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text(state.plan.readinessStatus)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if state.restoreState.needsRestore {
                Text(state.restoreState.summaryText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.primaryAction)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let recommendation = setupQuickstartRecommendation(for: state.plan) {
                SetupCardRecommendationView(
                    recommendation: recommendation,
                    onAction: { runSetupQuickstartRecommendation(for: state.plan) }
                )
            }

            if state.restoreState.needsRestore || state.hasStarterPrompt {
                HStack(spacing: 10) {
                    Button {
                        runSetupQuickstart(state)
                    } label: {
                        Label(state.primaryActionTitle, systemImage: state.primaryActionSymbolName)
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.primaryAction, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if state.restoreState.needsRestore, state.hasStarterPrompt {
                        Button {
                            useSetupPrompt(state)
                        } label: {
                            Label("Use starter prompt", systemImage: "text.cursor")
                                .font(.caption.weight(.semibold))
                                .frame(height: 38)
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.textSecondary)
                        .background(Color.secondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            } else {
                Text("This chat already matches your saved setup defaults.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.10), lineWidth: 1)
        }
    }

    private var emptyPromptSuggestions: [EmptyPromptSuggestion] {
        if chatStore.selectedProviderDisplayName == "IronClaw" {
            return [
                EmptyPromptSuggestion(title: "Review repo", symbolName: "chevron.left.forwardslash.chevron.right", prompt: "Agent mission: Review this repo and identify the highest-impact fixes: "),
                EmptyPromptSuggestion(title: "Patch safely", symbolName: "wrench.and.screwdriver", prompt: "Agent mission: Implement this change, run focused tests, and report changed files: "),
                EmptyPromptSuggestion(title: "Research issue", symbolName: "globe", prompt: "Agent mission: Research the latest context and turn it into next actions: ")
            ]
        }

        if let project = chatStore.selectedProject {
            let projectName = project.name
            return [
                EmptyPromptSuggestion(title: "Brief project", symbolName: "folder.badge.gearshape", prompt: "Use \(projectName)'s files, links, and notes to brief me on the next best move."),
                EmptyPromptSuggestion(title: "Find blockers", symbolName: "exclamationmark.triangle", prompt: "Review \(projectName)'s context and identify the highest-risk blockers, missing facts, and next checks."),
                EmptyPromptSuggestion(title: "Draft next step", symbolName: "arrow.forward.circle", prompt: "Turn \(projectName)'s current context into a concise next-step plan I can act on.")
            ]
        }

        if let setupProfileWithGoal {
            return setupProfileWithGoal.emptyStatePromptSuggestions.map {
                EmptyPromptSuggestion(title: $0.title, symbolName: $0.symbolName, prompt: $0.prompt)
            }
        }

        if chatStore.isCouncilModeEnabled {
            return [
                EmptyPromptSuggestion(title: "Compare models", symbolName: "square.grid.2x2", prompt: "Compare Anthropic and OpenAI for this task: "),
                EmptyPromptSuggestion(title: "Disagree", symbolName: "arrow.triangle.branch", prompt: "Ask the council to identify strongest agreements and disagreements on: "),
                EmptyPromptSuggestion(title: "Decision brief", symbolName: "doc.text.magnifyingglass", prompt: "Give me a decision-ready brief with tradeoffs and next steps: ")
            ]
        }

        if chatStore.researchModeEnabled {
            return [
                EmptyPromptSuggestion(title: "Latest AI", symbolName: "globe", prompt: "What is the latest important news in AI? Include sources and dates."),
                EmptyPromptSuggestion(title: "Compare views", symbolName: "square.grid.2x2", prompt: "Compare Anthropic and OpenAI for this task using current sources: "),
                EmptyPromptSuggestion(title: "Brief me", symbolName: "doc.text.magnifyingglass", prompt: "Research this and give me a decision-ready brief with citations: ")
            ]
        }

        if let setupProfile {
            return setupProfile.emptyStatePromptSuggestions.map {
                EmptyPromptSuggestion(title: $0.title, symbolName: $0.symbolName, prompt: $0.prompt)
            }
        }

        return [
            EmptyPromptSuggestion(title: "Plan next move", symbolName: "arrow.forward.circle", prompt: "Help me turn this into the next concrete action: "),
            EmptyPromptSuggestion(title: "Research latest", symbolName: "globe", prompt: "Research the latest context and give me the decision-ready version: "),
            EmptyPromptSuggestion(title: "Compare options", symbolName: "square.grid.2x2", prompt: "Compare the strongest options, tradeoffs, and recommendation for: ")
        ]
    }

    private var setupProfile: UserSetupProfile? {
        guard let accountID = sessionStore.setupAccountID else { return nil }
        return UserSetupStorage.load(for: accountID)
    }

    private var setupProfileWithGoal: UserSetupProfile? {
        guard let setupProfile, !setupProfile.normalizedGoalText.isEmpty else { return nil }
        return setupProfile
    }

    private var setupQuickstartState: SetupQuickstartState? {
        guard let profile = setupProfile else { return nil }
        let plan = AppSetupPlan(profile: profile, readiness: setupReadinessSnapshot)
        return SetupQuickstartState(
            profile: profile,
            plan: plan,
            restoreState: SetupRestorePlanner.evaluate(
                profile: profile,
                plan: plan,
                runtime: currentSetupRuntimeSnapshot
            )
        )
    }

    private var setupReadinessSnapshot: AppSetupReadinessSnapshot {
        AppSetupReadinessSnapshot(
            modelCatalogLoaded: !chatStore.models.isEmpty,
            privateModelAvailable: chatStore.pickerModels.contains { !$0.isExternalModel },
            defaultCouncilModelCount: chatStore.defaultCouncilModels.count,
            ironclawMobileAvailable: chatStore.agentModels.contains { $0.id == ModelOption.ironclawMobileModelID },
            hostedIronclawAvailable: chatStore.ironclawRemoteWorkstationAvailable,
            nearCloudKeyConfigured: chatStore.nearCloudKeyConfigured
        )
    }

    private var setupRouteBlock: CapabilityRouteBlock? {
        guard let issue = chatStore.routeReadinessIssue else { return nil }
        switch issue.route {
        case .nearCloud:
            return .nearCloudKeyRequired
        case .hostedIronclaw:
            return .hostedIronclawEndpointRequired
        case .council:
            return .councilNeedsModels
        }
    }

    private func setupQuickstartNextStep(for plan: AppSetupPlan) -> CapabilityNextStep? {
        let recommendation = CapabilityNextStepPlanner.recommend(
            routeBlock: setupRouteBlock,
            setupPlan: plan,
            currentRoute: chatStore.selectedRouteKind,
            hasFreshPrivateProof: true,
            hostedIronclawAvailable: chatStore.ironclawRemoteWorkstationAvailable,
            autoCouncilReady: chatStore.defaultCouncilModels.count >= 2
        )

        guard let recommendation else { return nil }
        switch recommendation.kind {
        case .openCloud, .openAgent, .useAutoCouncil:
            return recommendation
        case .openSecurity, .rerunSetup:
            return nil
        }
    }

    private func setupQuickstartRecommendation(for plan: AppSetupPlan) -> SetupCardRecommendation? {
        guard let recommendation = setupQuickstartNextStep(for: plan) else { return nil }
        return SetupCardRecommendation(
            title: recommendation.title,
            detail: recommendation.detail,
            actionTitle: recommendation.actionTitle,
            actionSymbolName: setupQuickstartRecommendationSymbolName(for: recommendation.kind)
        )
    }

    private func setupQuickstartRecommendationSymbolName(for kind: CapabilityNextStepKind) -> String {
        switch kind {
        case .openCloud:
            return "key"
        case .openAgent:
            return "point.3.connected.trianglepath.dotted"
        case .useAutoCouncil:
            return "square.grid.2x2"
        case .openSecurity:
            return "checkmark.shield"
        case .rerunSetup:
            return "arrow.counterclockwise"
        }
    }

    private func runSetupQuickstartRecommendation(for plan: AppSetupPlan) {
        guard let recommendation = setupQuickstartNextStep(for: plan) else { return }
        switch recommendation.kind {
        case .openCloud, .openAgent:
            AppHaptics.lightImpact()
            showingAccountSettings = true
        case .useAutoCouncil:
            AppHaptics.selection()
            chatStore.useDefaultCouncilLineup()
        case .openSecurity, .rerunSetup:
            break
        }
    }

    private func fillDraft(for suggestion: EmptyPromptSuggestion) {
        AppHaptics.selection()
        chatStore.draft = suggestion.prompt
    }

    private func runSetupQuickstart(_ state: SetupQuickstartState) {
        if state.restoreState.needsRestore {
            AppHaptics.lightImpact()
            chatStore.applySetupProfile(state.profile)
            return
        }

        useSetupPrompt(state)
    }

    private func useSetupPrompt(_ state: SetupQuickstartState) {
        guard let prompt = state.plan.firstRunDraft else { return }
        AppHaptics.selection()
        recordPromptTelemetry(for: state.profile)
        chatStore.draft = prompt
    }

    private var currentSetupRuntimeSnapshot: SetupRuntimeSnapshot {
        SetupRuntimeSnapshot(
            modelRoute: currentModelRoute,
            focusMode: chatStore.sourceMode,
            webSearchEnabled: chatStore.webSearchEnabled,
            researchModeEnabled: chatStore.researchModeEnabled,
            selectedProjectName: chatStore.selectedProject?.name
        )
    }

    private var currentModelRoute: AppSetupModelRoute {
        if chatStore.selectedModelOption?.isIronclawMobileRuntime == true ||
            chatStore.selectedModelOption?.isIronclawHostedModel == true {
            return .ironclaw
        }
        if chatStore.isCouncilModeEnabled {
            return .council
        }
        return .privateModel
    }

    private func recordPromptTelemetry(for profile: UserSetupProfile) {
        let store = PrivateTelemetryStore()
        let context = TelemetryContext(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "local",
            profileBucket: profile.telemetryProfileBucket
        )
        try? store.record(.promptChipUsed(profile.telemetryPromptChip), context: context)
    }
}

private extension UserSetupProfile {
    var telemetryPromptChip: TelemetryPromptChip {
        switch useCases.setupPrimaryUseCase {
        case .privateChat:
            return .ask
        case .research:
            return .research
        case .buildAgents:
            return .agent
        case .teamProjects:
            return .sourceQA
        }
    }

    var telemetryProfileBucket: TelemetryProfileBucket {
        if useCases.count > 1 {
            return .mixed
        }
        switch useCases.setupPrimaryUseCase {
        case .privateChat:
            return .privateChat
        case .research:
            return .research
        case .buildAgents:
            return .agentWork
        case .teamProjects:
            return .mixed
        }
    }
}
