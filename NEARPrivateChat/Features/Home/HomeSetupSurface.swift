import SwiftUI

struct FirstRunSetupHomeCard: View {
    let readiness: AppSetupReadinessSnapshot
    let routeDefaults: SetupRouteDefaults
    let onStartSetup: () -> Void
    let onStartPrivateChat: () -> Void
    let onQuickStart: (UserSetupStarterPreset) -> Void
    let onRecommendationAction: (CapabilityNextStep) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 38, height: 38)
                    .background(Color.appSymbolBlueBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("First run")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.primaryAction)
                    Text("Choose what should work first")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Setup picks your route, context, and starter prompt for private chat, research, Agent, or Project work.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["Private chat", "Research", "Agents", "Projects"], id: \.self) { item in
                        SetupLaunchPill(title: item)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()

            Text("Skip advanced routes now and change everything later from Account.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("One-tap starts")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textSecondary)

                VStack(spacing: 8) {
                    ForEach(UserSetupStarterPreset.allCases) { preset in
                        quickStartButton(for: preset)
                    }
                }
            }

            HStack(spacing: 10) {
                Button(action: onStartSetup) {
                    Label("Start setup", systemImage: "arrow.right")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Color.primaryAction, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button("Start private chat", action: onStartPrivateChat)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(height: 44)
                    .padding(.horizontal, 12)
                    .background(Color.secondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: Color.brandBlue.opacity(0.05), radius: 12, y: 6)
    }

    @ViewBuilder
    private func quickStartButton(for preset: UserSetupStarterPreset) -> some View {
        let plan = preset.previewPlan(
            readiness: readiness,
            routeDefaults: routeDefaults
        )
        let capabilityRecommendation = plan.firstRunCapabilityRecommendation(readiness: readiness)

        FirstRunQuickStartButton(
            preset: preset,
            plan: plan,
            recommendation: capabilityRecommendation.map(Self.recommendation),
            onRecommendationAction: capabilityRecommendation.map { recommendation in
                { onRecommendationAction(recommendation) }
            }
        ) {
            onQuickStart(preset)
        }
    }

    private static func recommendation(from nextStep: CapabilityNextStep) -> SetupCardRecommendation {
        SetupCardRecommendation(
            title: nextStep.title,
            detail: nextStep.detail,
            actionTitle: nextStep.actionTitle,
            actionSymbolName: recommendationSymbolName(for: nextStep.kind)
        )
    }

    private static func recommendationSymbolName(for kind: CapabilityNextStepKind) -> String {
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
}

private struct FirstRunQuickStartButton: View {
    let preset: UserSetupStarterPreset
    let plan: AppSetupPlan
    let recommendation: SetupCardRecommendation?
    let onRecommendationAction: (() -> Void)?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: preset.symbolName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 34, height: 34)
                            .background(Color.appSymbolBlueBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(plan.expectedFirstAction)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.top, 4)
                    }

                    ChipFlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(plan.launchCardMetadata, id: \.self) { item in
                            SetupLaunchPill(title: item)
                        }
                    }

                    if let routeDetail = plan.routeDetailContent {
                        FirstRunQuickStartRouteLine(detail: routeDetail)
                    }

                    Text(plan.readinessStatus)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quick start \(preset.title)")
            .accessibilityValue(plan.expectedFirstAction)
            .accessibilityHint("Applies that setup using the current route readiness and opens a starter draft without sending.")

            if let recommendation {
                SetupCardRecommendationView(
                    recommendation: recommendation,
                    onAction: onRecommendationAction
                )
            }
        }
    }
}

private struct FirstRunQuickStartRouteLine: View {
    let detail: AppSetupRouteDetailContent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: detail.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(detail.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
                Text(detail.summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

struct SavedSetupHomeCard: View {
    let plan: AppSetupPlan
    let restoreState: SetupRestoreState
    let recommendation: SetupCardRecommendation?
    let onSkillSuggestion: ((IronclawSkillProfile) -> Void)?
    let onPrimaryAction: () -> Void
    let onAgentMission: ((SetupAgentMissionSuggestion) -> Void)?
    let onPromptSuggestion: ((SetupPromptSuggestion) -> Void)?
    let onRecommendationAction: (() -> Void)?
    let onChangeSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 38, height: 38)
                    .background(Color.appSymbolBlueBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("No chats yet")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.primaryAction)
                    Text(plan.launchCardTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(restoreState.summaryText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(restoreState.needsRestore ? Color.primaryAction : Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if !plan.launchCardMetadata.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(plan.launchCardMetadata, id: \.self) { item in
                            SetupLaunchPill(title: item)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .scrollClipDisabled()
            }

            if let routeDetail = plan.routeDetailContent {
                SetupRouteDetailCard(detail: routeDetail)
            }

            if restoreState.needsRestore, !restoreState.differences.isEmpty {
                SetupRestoreDifferenceSection(differences: restoreState.differences)
            }

            if let firstRunDraft = plan.firstRunDraft {
                VStack(alignment: .leading, spacing: 5) {
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
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if !plan.starterWorkspaceSeeds.isEmpty {
                SetupWorkspaceSeedSection(seeds: Array(plan.starterWorkspaceSeeds.prefix(3)))
            }

            if !plan.starterSkillSuggestions.isEmpty {
                SetupSkillSuggestionSection(
                    skills: Array(plan.starterSkillSuggestions.prefix(3)),
                    onSelect: onSkillSuggestion
                )
            }

            if let agentMissionSuggestion = plan.agentMissionSuggestion {
                SetupAgentMissionSection(
                    mission: agentMissionSuggestion,
                    action: onAgentMission.map { select in
                        { select(agentMissionSuggestion) }
                    }
                )
            }

            if !plan.starterPromptSuggestions.isEmpty {
                SetupPromptSuggestionSection(
                    title: "Quick starts",
                    suggestions: plan.starterPromptSuggestions,
                    onSelect: onPromptSuggestion
                )
            }

            Text(plan.readinessStatus)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let recommendation {
                SetupCardRecommendationView(
                    recommendation: recommendation,
                    onAction: onRecommendationAction
                )
            }

            HStack(spacing: 10) {
                Button(action: onPrimaryAction) {
                    Label(primaryActionTitle, systemImage: primaryActionSymbolName)
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Color.primaryAction, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button("Change setup", action: onChangeSetup)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(height: 44)
                    .padding(.horizontal, 12)
                    .background(Color.secondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: Color.brandBlue.opacity(0.05), radius: 12, y: 6)
    }

    private var primaryActionTitle: String {
        if restoreState.needsRestore {
            return "Restore saved setup"
        }
        guard plan.firstRunDraft != nil else {
            return "Start new chat"
        }
        switch plan.modelRoute {
        case .ironclaw:
            return "Start agent chat"
        case .council:
            return "Start council chat"
        case .privateModel:
            return "Start first chat"
        }
    }

    private var primaryActionSymbolName: String {
        if restoreState.needsRestore {
            return "arrow.counterclockwise"
        }
        guard plan.firstRunDraft != nil else {
            return "bubble.left.and.bubble.right"
        }
        switch plan.modelRoute {
        case .ironclaw:
            return "terminal"
        case .council:
            return "square.grid.2x2"
        case .privateModel:
            return "arrow.right"
        }
    }
}

private struct SetupRestoreDifferenceSection: View {
    let differences: [SetupRestoreDifference]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Changed since setup")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primaryAction)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(differences) { difference in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(difference.title)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.textSecondary)
                        Text("Saved: \(difference.savedValue)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Current: \(difference.currentValue)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if difference.id != differences.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(12)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
