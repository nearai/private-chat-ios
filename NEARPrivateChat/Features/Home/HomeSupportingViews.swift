import SwiftUI

struct SetupCardRecommendation {
    let title: String
    let detail: String
    let actionTitle: String
    let actionSymbolName: String
}

struct SetupRouteDetailCard: View {
    let detail: AppSetupRouteDetailContent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: detail.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 30, height: 30)
                .background(Color.appSymbolBlueBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
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
        .padding(12)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SetupLaunchCard: View {
    let plan: AppSetupPlan
    let recommendation: SetupCardRecommendation?
    let onSkillSuggestion: ((IronclawSkillProfile) -> Void)?
    let onPrimaryAction: () -> Void
    let onAgentMission: ((SetupAgentMissionSuggestion) -> Void)?
    let onPromptSuggestion: ((SetupPromptSuggestion) -> Void)?
    let onRecommendationAction: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 38, height: 38)
                    .background(Color.appSymbolBlueBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Setup ready")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.primaryAction)
                    Text(plan.launchCardTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(plan.launchCardSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
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

            if let firstRunDraft = plan.firstRunDraft {
                VStack(alignment: .leading, spacing: 5) {
                    Text("First prompt")
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

                Button("Use defaults", action: onDismiss)
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
        guard plan.firstRunDraft != nil else {
            return "Apply setup"
        }
        switch plan.modelRoute {
        case .ironclaw:
            return "Open agent prompt"
        case .council:
            return "Open council prompt"
        case .privateModel:
            return "Open first prompt"
        }
    }

    private var primaryActionSymbolName: String {
        guard plan.firstRunDraft != nil else {
            return "slider.horizontal.3"
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
                    Text("Setup picks your route, context, and starter prompt for private chat, research, agents, or project work.")
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

            Text("You can skip advanced routes now and change everything later from Account.")
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

struct SetupCardRecommendationView: View {
    let recommendation: SetupCardRecommendation
    let onAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recommendation.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primaryAction)

            Text(recommendation.detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let onAction {
                Button(action: onAction) {
                    Label(recommendation.actionTitle, systemImage: recommendation.actionSymbolName)
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primaryAction)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(12)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SetupLaunchPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.secondarySurface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.appBorder, lineWidth: 1)
            }
    }
}

private struct SetupWorkspaceSeedSection: View {
    let seeds: [SetupWorkspaceSeed]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Starter Project")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(seeds) { seed in
                    SetupWorkspaceSeedRow(seed: seed)
                }
            }
        }
    }
}

private struct SetupWorkspaceSeedRow: View {
    let seed: SetupWorkspaceSeed

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: seed.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(seed.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(seed.detail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct SetupSkillSuggestionSection: View {
    let skills: [IronclawSkillProfile]
    let onSelect: ((IronclawSkillProfile) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent skills")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(skills) { skill in
                    SetupSkillSuggestionRow(
                        skill: skill,
                        action: onSelect.map { select in
                            { select(skill) }
                        }
                    )
                }
            }
        }
    }
}

private struct SetupSkillSuggestionRow: View {
    let skill: IronclawSkillProfile
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use setup skill, \(skill.title)")
                .accessibilityHint("Stages an IronClaw prompt from this saved setup skill without sending.")
            } else {
                rowLabel
            }
        }
    }

    private var rowLabel: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: skill.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(skill.summary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            if action != nil {
                Label("Use skill", systemImage: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color.primaryAction)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Color.secondarySurface, in: Capsule())
            }
        }
        .padding(12)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SetupAgentMissionSection: View {
    let mission: SetupAgentMissionSuggestion
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent mission")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mission.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(mission.detail)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(mission.prompt)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)

                if let action {
                    Button(action: action) {
                        Label("Use mission", systemImage: "terminal")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primaryAction)
                    .background(Color.secondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHint("Reopens setup defaults and fills the saved agent mission without sending.")
                }
            }
            .padding(12)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct SetupPromptSuggestionSection: View {
    let title: String
    let suggestions: [SetupPromptSuggestion]
    let onSelect: ((SetupPromptSuggestion) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        SetupPromptSuggestionChip(
                            suggestion: suggestion,
                            action: onSelect.map { select in
                                { select(suggestion) }
                            }
                        )
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()
        }
    }
}

private struct SetupPromptSuggestionChip: View {
    let suggestion: SetupPromptSuggestion
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    chipLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use setup prompt, \(suggestion.title)")
                .accessibilityHint("Reopens setup defaults and fills this first prompt without sending.")
            } else {
                chipLabel
            }
        }
    }

    private var chipLabel: some View {
        Label(suggestion.title, systemImage: suggestion.symbolName)
            .font(.footnote.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.appSecondaryBackground, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.appBorder, lineWidth: 1)
            }
    }
}

struct HomeTrustReadinessCard: View {
    let viewModel: ProofCapsuleViewModel
    let routeLabel: String
    let modelLabel: String
    let actionTitle: String
    let actionSymbolName: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: viewModel.symbolName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(viewModel.tintColor)
                    .frame(width: 38, height: 38)
                    .background(viewModel.tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Trust check")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.primaryAction)
                    Text(viewModel.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(viewModel.detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 10) {
                ProofCapsule(viewModel: viewModel)
                VStack(alignment: .leading, spacing: 3) {
                    Text(routeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(modelLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Button(action: action) {
                Label(actionTitle, systemImage: actionSymbolName)
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.primaryAction, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(viewModel.tintColor.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: Color.brandBlue.opacity(0.04), radius: 12, y: 6)
    }
}

struct HomeSurfaceBackground: View {
    var body: some View {
        ZStack {
            Color.appBackground
            LinearGradient(
                colors: [
                    Color.brandBlue.opacity(0.10),
                    Color.brandSky.opacity(0.05),
                    Color.clear,
                    Color.clear
                ],
                startPoint: .topTrailing,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }
}

struct ConversationRow: View {
    let conversation: ConversationSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            SidebarSymbol(
                symbolName: conversation.isPinned ? "pin.fill" : "bubble.left",
                isSelected: isSelected || conversation.isPinned,
                isAction: false
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.body.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let createdAt = conversation.createdAt {
                    Text(Self.timestampText(for: Date(timeIntervalSince1970: createdAt)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            Spacer(minLength: 0)

            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.brandBlue)
                    .frame(width: 4, height: 28)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(isSelected ? Color.brandBlue.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.brandBlue.opacity(0.10), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }

    private static func timestampText(for date: Date) -> String {
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 {
            return "Just now"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60))m ago"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3600))h ago"
        }
        if elapsed < 604_800 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct SidebarSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .tokenInputTraits()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.brandBlue.opacity(0.05), radius: 12, y: 6)
    }
}

struct HomeSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var actionSymbolName: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        if let actionSymbolName {
                            Image(systemName: actionSymbolName)
                                .font(.caption.weight(.bold))
                        }
                        Text(actionTitle)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.primaryAction)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 6)
        .padding(.trailing, 6)
    }
}

struct HomeToolbarIconButton: View {
    let symbolName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ClaudeHomeTopBar: View {
    let displayName: String
    let isSearchVisible: Bool
    let onAccount: () -> Void
    let onSearch: () -> Void
    let onNewChat: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onAccount) {
                Text(avatarLetter)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.actionFill, in: Circle())
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44, alignment: .leading)
            .accessibilityLabel("Account")

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(isSearchVisible ? Color.actionPrimary : Color.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSearchVisible ? "Hide search" : "Search")

                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New chat")
            }
        }
        .overlay {
            Text("Today")
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .background(Color.appBackground)
    }

    private var avatarLetter: String {
        String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "A").uppercased()
    }
}

struct ClaudeThreadRow: View {
    let conversation: ConversationSummary
    let preview: String
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(conversation.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    Text(timestampText)
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }

                Text(preview)
                    .font(.footnote)
                    .fontWeight(.regular)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.top, 11)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(minHeight: 64, alignment: .center)
            .contentShape(Rectangle())

            if !isLast {
                Rectangle()
                    .fill(Color.appHairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
            }
        }
        .background(Color.appBackground)
    }

    private var timestampText: String {
        guard let createdAt = conversation.createdAt else { return "Recent" }
        let date = Date(timeIntervalSince1970: createdAt)
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 {
            return "Just now"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60))m"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3600))h"
        }
        if elapsed < 172_800 {
            return "Yesterday"
        }
        if elapsed < 604_800 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct ClaudeHomeEmptyState: View {
    let title: String
    let showsAction: Bool
    let action: () -> Void

    var body: some View {
        // Spec (home.jsx EmptyView):
        //   gridTemplateRows: "1fr auto 0.85fr"
        //   paddingBottom: 56
        //
        // Translated: top spacer and bottom region split the remaining
        // height in a 1 : 0.85 ratio (top gets 54%, bottom 46%). The
        // mark+caption block sits between them with padding-top 30; the
        // CTA pins to the bottom of the lower region with the 56pt
        // padding accounting for the home indicator.
        GeometryReader { proxy in
            let bottomPadding: CGFloat = 56
            let contentHeight: CGFloat = 30 + 64 + 18 + 20 // padding-top + mark + gap + caption line
            let ctaHeight: CGFloat = showsAction ? 52 : 0
            let remaining = max(0, proxy.size.height - contentHeight - ctaHeight - bottomPadding)
            let topSpacer = remaining * (1.0 / 1.85)
            let bottomSpacer = remaining * (0.85 / 1.85)

            VStack(spacing: 0) {
                Color.clear.frame(height: topSpacer)

                VStack(spacing: 18) {
                    NearAppIconMark(size: 64)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 30)

                Color.clear.frame(height: bottomSpacer)

                if showsAction {
                    Button(action: action) {
                        Text("Start a new chat")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Color.actionPrimary.opacity(0.18), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, bottomPadding)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(minHeight: 560)
    }
}

struct HomeEmptyState: View {
    let title: String
    let subtitle: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 30)

            VStack(spacing: 14) {
                PrivacySeal(size: 64)
                    .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
            }

            Spacer(minLength: 28)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 420)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }
}

struct HomePromptCaptureCard: View {
    let subtitle: String
    @Binding var draft: String
    let suggestions: [EmptyChatStarterSuggestion]
    let selectedSuggestionID: String?
    let selectedProjectName: String?
    let actionTitle: String
    let actionSymbolName: String
    let actionEnabled: Bool
    let onSelectSuggestion: (EmptyChatStarterSuggestion) -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start from one prompt")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let selectedProjectName = selectedProjectName?.nilIfBlank {
                Label("\(selectedProjectName) context is active", systemImage: "folder.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.actionTint, in: Capsule())
            }

            TextField(
                "Paste a task, source, file question, tracker idea, or handoff brief",
                text: $draft,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(3...6)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }

            if !suggestions.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        promptIntentChips(fillsWidth: false)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 132), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        promptIntentChips(fillsWidth: true)
                    }
                }
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Nothing sends until you review it in chat.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button(action: onSubmit) {
                    Label(actionTitle, systemImage: actionSymbolName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(
                            actionEnabled ? Color.actionPrimary : Color.textTertiary,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!actionEnabled)
            }
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func promptIntentChips(fillsWidth: Bool) -> some View {
        ForEach(suggestions) { suggestion in
            HomePromptIntentChip(
                suggestion: suggestion,
                isSelected: suggestion.id == selectedSuggestionID,
                fillsWidth: fillsWidth,
                action: { onSelectSuggestion(suggestion) }
            )
        }
    }
}

private struct HomePromptIntentChip: View {
    let suggestion: EmptyChatStarterSuggestion
    let isSelected: Bool
    var fillsWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: suggestion.symbolName)
                    .font(.caption.weight(.bold))
                Text(suggestion.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.actionPrimary : Color.textSecondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 40)
            .background(
                isSelected ? Color.actionTint : Color.appSecondaryBackground,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.actionPrimary.opacity(0.24) : Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct HomeInboxSectionPlan: Equatable {
    let selectedFilter: HomeFilter
    let searchQuery: String
    let activeConversationCount: Int
    let activeProjectCount: Int
    let projectContextMatchCount: Int
    let sharedWithMeCount: Int
    let archivedConversationCount: Int
    let archivedProjectCount: Int

    init(
        selectedFilter: HomeFilter,
        searchQuery: String,
        activeConversationCount: Int,
        activeProjectCount: Int,
        projectContextMatchCount: Int,
        sharedWithMeCount: Int,
        archivedConversationCount: Int,
        archivedProjectCount: Int
    ) {
        self.selectedFilter = selectedFilter
        self.searchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activeConversationCount = activeConversationCount
        self.activeProjectCount = activeProjectCount
        self.projectContextMatchCount = projectContextMatchCount
        self.sharedWithMeCount = sharedWithMeCount
        self.archivedConversationCount = archivedConversationCount
        self.archivedProjectCount = archivedProjectCount
    }

    var isSearching: Bool {
        !searchQuery.isEmpty
    }

    var filterCounts: [HomeFilter: Int] {
        [
            .all: activeConversationCount + activeProjectCount + projectContextMatchCount,
            .shared: sharedWithMeCount,
            .archived: archivedConversationCount + archivedProjectCount
        ]
    }

    var showsActiveInbox: Bool {
        selectedFilter == .all
    }

    var showsProjectContext: Bool {
        showsActiveInbox && projectContextMatchCount > 0
    }

    var showsProjects: Bool {
        showsActiveInbox && activeProjectCount > 0
    }

    var showsConversations: Bool {
        showsActiveInbox && activeConversationCount > 0
    }

    var showsWorkboard: Bool {
        showsActiveInbox && !isSearching
    }

    var showsSharedWithMe: Bool {
        selectedFilter == .shared && sharedWithMeCount > 0
    }

    var showsArchivedProjects: Bool {
        selectedFilter == .archived && archivedProjectCount > 0
    }

    var showsArchivedConversations: Bool {
        selectedFilter == .archived && archivedConversationCount > 0
    }

    var hasActiveContent: Bool {
        activeConversationCount > 0 || activeProjectCount > 0 || projectContextMatchCount > 0
    }

    var showsActiveSetupEmptyState: Bool {
        showsActiveInbox && activeConversationCount == 0
    }

    var showsActiveSearchEmptyState: Bool {
        showsActiveInbox && isSearching && !hasActiveContent
    }

    var showsSharedEmptyState: Bool {
        selectedFilter == .shared && sharedWithMeCount == 0
    }

    var showsArchivedEmptyState: Bool {
        selectedFilter == .archived && archivedConversationCount == 0 && archivedProjectCount == 0
    }
}

struct HomeInboxEmptyState: View {
    let title: String
    let subtitle: String
    let symbolName: String
    var isLoading = false
    var actionTitle: String? = nil
    var actionSymbolName: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if isLoading {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: symbolName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionSymbolName ?? "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primaryAction)
                .background(Color.secondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}

struct HomeFilterStrip: View {
    @Binding var selectedFilter: HomeFilter
    let counts: [HomeFilter: Int]
    let onSelect: (HomeFilter) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            filterButtons

            Menu {
                ForEach(HomeFilter.allCases) { filter in
                    Button {
                        onSelect(filter)
                    } label: {
                        Label(filter.title, systemImage: filter.symbolName)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: selectedFilter.symbolName)
                    Text(selectedFilter == .all ? "Today" : "\(selectedFilter.title) items")
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
            }
        }
        .padding(4)
        .background(Color.appPanelBackground.opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var filterButtons: some View {
        HStack(spacing: 6) {
            ForEach(HomeFilter.allCases) { filter in
                Button {
                    onSelect(filter)
                } label: {
                    filterLabel(for: filter)
                }
                .buttonStyle(.plain)
                .accessibilityValue(selectedFilter == filter ? "Selected" : "")
            }
        }
    }

    private func filterLabel(for filter: HomeFilter) -> some View {
        let isSelected = selectedFilter == filter
        return HStack(spacing: 5) {
            Image(systemName: filter.symbolName)
                .font(.caption.weight(.bold))
            Text(filter.title)
                .font(.caption.weight(isSelected ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            if let count = counts[filter], count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? Color.primaryAction : Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background(
                        isSelected ? Color.primaryAction.opacity(0.12) : Color.appSecondaryBackground,
                        in: Capsule()
                    )
            }
        }
        .foregroundStyle(isSelected ? Color.primaryAction : Color.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(
            isSelected ? Color.primaryAction.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primaryAction.opacity(0.14), lineWidth: 1)
            }
        }
    }
}

struct HomeRecentsRow: View {
    let conversations: [ConversationSummary]
    let projectNameForConversation: (ConversationSummary) -> String?
    let onOpenConversation: (ConversationSummary) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(conversations) { conversation in
                    HomeRecentCard(
                        conversation: conversation,
                        projectName: projectNameForConversation(conversation),
                        onOpen: { onOpenConversation(conversation) }
                    )
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

struct HomeRecentCard: View {
    let conversation: ConversationSummary
    let projectName: String?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(conversation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.primaryAction)
                }

                Text(projectName ?? "Private chat")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text(timestampText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("Resume")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.primaryAction)
                }
            }
            .padding(12)
            .frame(minWidth: 222, idealWidth: 222, maxWidth: 222, minHeight: 104, alignment: .topLeading)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var timestampText: String {
        guard let createdAt = conversation.createdAt else { return "Recent" }
        let date = Date(timeIntervalSince1970: createdAt)
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 {
            return "Just now"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60))m ago"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3600))h ago"
        }
        if elapsed < 604_800 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct LoadingHomeRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
    }
}

struct ProjectContextSearchRow: View {
    let match: HomeProjectContextMatch

    var body: some View {
        HStack(spacing: 12) {
            SidebarSymbol(
                symbolName: match.kind.symbolName,
                isSelected: false,
                isAction: true,
                tintColor: match.project.tintColor,
                backgroundColor: match.project.tintBackgroundColor,
                size: 32
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(match.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("\(match.project.name) · \(match.kind.title)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let detail = match.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }
}

struct WorkspaceCommandHeader: View {
    let title: String
    let subtitle: String
    let onNewChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 11) {
                PrivacySeal(size: 46)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                    Text(subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 0)
            }

            Button(action: onNewChat) {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .font(.headline.weight(.bold))
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask NEAR")
                            .font(.headline.weight(.bold))
                            .lineLimit(1)
                        Text("Just type. NEAR handles routing.")
                            .font(.caption.weight(.semibold))
                            .opacity(0.72)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(Color.brandBlack)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color.brandSky, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background {
            CommandCardBackground(cornerRadius: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
        .shadow(color: Color.brandBlue.opacity(0.14), radius: 18, y: 8)
    }
}

struct CommandCardBackground: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.brandBlack,
                        Color.commandGradientMid,
                        Color.commandGradientEnd
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topTrailing) {
                LinearGradient(
                    colors: [
                        Color.brandBlue.opacity(0.78),
                        Color.brandSky.opacity(0.28),
                        Color.clear
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
    }
}

struct WorkspaceCommandButton: View {
    let title: String
    let symbolName: String
    let isPrimary: Bool
    var height: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .font(.subheadline.weight(.bold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isPrimary ? Color.brandBlack : .white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(isPrimary ? Color.brandSky : .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(isPrimary ? 0 : 0.14), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct WorkspaceModeButton: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: symbolName)
                    .font(.headline.weight(.bold))
                    .frame(width: 26, height: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                    Text(subtitle)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .opacity(isPrimary ? 0.74 : 0.68)
                }
            }
            .foregroundStyle(isPrimary ? Color.brandBlack : .white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 72)
            .padding(.horizontal, 12)
            .background(isPrimary ? Color.brandSky : .white.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(isPrimary ? 0 : 0.15), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct StatusChip: View {
    let title: String
    let symbolName: String
    let isPrimary: Bool

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isPrimary ? Color.primaryAction : Color.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isPrimary ? Color.primaryAction.opacity(0.08) : Color.secondarySurface, in: Capsule())
    }
}

struct ProjectRow: View {
    let title: String
    let subtitle: String?
    let symbolName: String
    let isSelected: Bool
    var isAction = false
    var tintColor: Color = .primaryAction
    var tintBackground: Color? = nil

    var body: some View {
        HStack(spacing: 12) {
            SidebarSymbol(
                symbolName: symbolName,
                isSelected: isSelected,
                isAction: isAction,
                tintColor: tintColor,
                backgroundColor: tintBackground,
                size: 32
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            isSelected ? (tintBackground ?? Color.brandBlue.opacity(0.07)) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tintColor.opacity(0.12), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }
}

struct SidebarSymbol: View {
    let symbolName: String
    let isSelected: Bool
    let isAction: Bool
    var tintColor: Color = .primaryAction
    var backgroundColor: Color? = nil
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbolName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(isSelected || isAction ? tintColor : .secondary)
            .frame(width: size, height: size)
            .background(
                (isSelected || isAction ? (backgroundColor ?? tintColor.opacity(0.11)) : Color.appSecondaryBackground.opacity(0.82)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

struct AccountToolbarButton: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var chatStore: ChatStore
    @State private var showingAccount = false
    let onRunSetupAgain: () -> Void

    var body: some View {
        Button {
            showingAccount = true
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 36, height: 36)
                .background(Color.panel.opacity(0.82), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account")
        .sheet(isPresented: $showingAccount) {
            AccountSettingsView(onRunSetupAgain: onRunSetupAgain)
                .environmentObject(sessionStore)
                .environmentObject(chatStore)
        }
    }
}
