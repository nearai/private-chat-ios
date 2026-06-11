import SwiftUI

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
                .foregroundStyle(Color.brandAccent)
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
                    .foregroundStyle(Color.brandAccent)
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
                .stroke(Color.brandAccent.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: Color.brandAccent.opacity(0.05), radius: 12, y: 6)
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

