import SwiftUI

struct SetupPlanPreviewCard: View {
    let plan: AppSetupPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: plan.modelRoute.symbolName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 36, height: 36)
                    .background(Color.appSymbolBlueBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.modelRoute.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                    Text(plan.focusBehavior)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if !plan.goalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SetupPlanLine(symbolName: "text.badge.plus", title: "Goal", value: plan.goalText)
                }
                SetupPlanLine(symbolName: "person.crop.circle.badge.checkmark", title: "Mode", value: plan.experienceSummary)
                SetupPlanLine(symbolName: plan.focusMode.symbolName, title: "Focus", value: plan.focusMode.title)
                SetupPlanLine(symbolName: "checkmark.seal", title: "Readiness", value: plan.readinessStatus)
                if let routeDetail = plan.routeDetailContent {
                    SetupPlanLine(
                        symbolName: routeDetail.symbolName,
                        title: routeDetail.title,
                        value: routeDetail.summary
                    )
                }
                if let starterProjectName = plan.starterProjectName {
                    SetupPlanLine(symbolName: "folder.badge.plus", title: "Project", value: starterProjectName)
                }
                if let firstRunDraft = plan.firstRunDraft {
                    SetupPlanLine(symbolName: "text.cursor", title: "Prompt", value: firstRunDraft)
                }
                SetupPlanLine(symbolName: "arrow.right.circle", title: "First action", value: plan.expectedFirstAction)
            }

            if !plan.starterWorkspaceSeeds.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Starter Project")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(plan.starterWorkspaceSeeds) { seed in
                        SetupSeedRow(seed: seed)
                    }
                }
            }

            if !plan.starterSkillSuggestions.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Agent skills")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(plan.starterSkillSuggestions) { skill in
                        SetupSkillPreviewRow(skill: skill)
                    }
                }
            }

            if let agentMissionSuggestion = plan.agentMissionSuggestion {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Agent mission")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    SetupAgentMissionPreviewRow(suggestion: agentMissionSuggestion)
                }
            }

            if !plan.starterPromptSuggestions.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("First prompts")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(plan.starterPromptSuggestions) { suggestion in
                        SetupPromptPreviewRow(suggestion: suggestion)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}

private struct SetupSeedRow: View {
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
            }

            Spacer(minLength: 0)
        }
    }
}

private struct SetupSkillPreviewRow: View {
    let skill: IronclawSkillProfile

    var body: some View {
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
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct SetupPromptPreviewRow: View {
    let suggestion: SetupPromptSuggestion

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: suggestion.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(suggestion.prompt)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct SetupAgentMissionPreviewRow: View {
    let suggestion: SetupAgentMissionSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "terminal")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(suggestion.detail)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Text(suggestion.prompt)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 26)
        }
    }
}

struct SetupPlanLine: View {
    let symbolName: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbolName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 18, height: 18)

            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .frame(width: 78, alignment: .leading)
                .padding(.top, 1)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lineLimit: Int {
        switch title {
        case "Prompt", "Readiness", "Goal":
            return 2
        default:
            return 1
        }
    }
}
