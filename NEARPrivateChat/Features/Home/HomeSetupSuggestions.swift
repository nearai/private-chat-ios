import SwiftUI

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
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primaryAction)
                .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.control))
            }
        }
        .padding(12)
        .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.control))
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

struct SetupWorkspaceSeedSection: View {
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
                .foregroundStyle(Color.brandAccent)
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

struct SetupSkillSuggestionSection: View {
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
                .foregroundStyle(Color.brandAccent)
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

struct SetupAgentMissionSection: View {
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
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primaryAction)
                    .background(Color.secondarySurface, in: RoundedRectangle.app(AppRadius.control))
                    .accessibilityHint("Reopens setup defaults and fills the saved agent mission without sending.")
                }
            }
            .padding(12)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct SetupPromptSuggestionSection: View {
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
            .frame(minHeight: 44)
            .background(Color.appSecondaryBackground, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.appBorder, lineWidth: 1)
            }
    }
}
