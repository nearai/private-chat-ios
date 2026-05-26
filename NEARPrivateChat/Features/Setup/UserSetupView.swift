import SwiftUI

private enum SetupDefaultToggle: Hashable {
    case web
    case ironclaw
    case council
}

struct UserSetupView: View {
    @EnvironmentObject private var chatStore: ChatStore
    let readiness: AppSetupReadinessSnapshot
    let onComplete: (UserSetupProfile) -> Void
    let onSkip: () -> Void
    @State private var profile: UserSetupProfile
    @State private var editedDefaultToggles: Set<SetupDefaultToggle> = []
    @State private var editedContextStyle = false

    init(
        initialProfile: UserSetupProfile = .defaults,
        readiness: AppSetupReadinessSnapshot = .optimistic,
        onComplete: @escaping (UserSetupProfile) -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.readiness = readiness
        self.onComplete = onComplete
        self.onSkip = onSkip
        _profile = State(initialValue: initialProfile)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    setupHero

                    SetupGoalField(text: $profile.goalText)

                    setupExamples

                    setupExperienceMode

                    SetupQuietWebToggle(isOn: setupToggleBinding(.web, keyPath: \.wantsWeb))

                    SetupReadinessLine(plan: setupPlan)

                    setupPreview
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(HomeSurfaceBackground())
            .navigationTitle("Setup")
            .platformInlineNavigationTitle()
            .safeAreaInset(edge: .bottom) {
                setupFooter
            }
        }
        .interactiveDismissDisabled()
    }

    private var setupFooter: some View {
        VStack(spacing: 8) {
            Button {
                onComplete(profile.normalizedForDefaults)
            } label: {
                Label(primarySetupActionTitle, systemImage: "arrow.right")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.primaryAction, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(primarySetupActionTitle)

            Button("Skip setup") {
                onSkip()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.appHairline)
                .frame(height: 1)
        }
    }

    private var primarySetupActionTitle: String {
        setupPlan.expectedFirstAction
    }

    private var setupPlan: AppSetupPlan {
        AppSetupPlan(profile: profile.normalizedForDefaults, readiness: readiness)
    }

    private var setupHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                PrivacySeal(size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Make it yours")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Tell NEAR Private Chat what should work first. It will set route, context, and proof defaults around that goal.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                SetupHeroMetric(title: "Private", symbolName: "lock.shield")
                SetupHeroMetric(title: "Web", symbolName: "globe")
                SetupHeroMetric(title: "Agents", symbolName: "terminal")
            }
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

    private func setupSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                content()
            }
        }
    }

    private var setupExperienceMode: some View {
        setupSection(title: "How much control do you want?") {
            ForEach(UserSetupExperienceMode.allCases) { mode in
                SetupChoiceRow(
                    title: mode.title,
                    subtitle: mode.subtitle,
                    symbolName: mode.symbolName,
                    isSelected: profile.experienceMode == mode
                ) {
                    profile.experienceMode = mode
                }
            }
        }
    }

    private var setupPreview: some View {
        setupSection(title: "What will happen next") {
            SetupPlanPreviewCard(plan: setupPlan)
        }
    }

    private func applyUseCaseDefaultsFromSelection() {
        let selected = Set(profile.useCases)
        profile.useCase = profile.useCases.setupPrimaryUseCase
        if !editedDefaultToggles.contains(.web) {
            profile.wantsWeb = false
        }
        if !editedDefaultToggles.contains(.ironclaw) {
            profile.wantsIronclaw = selected.contains(.buildAgents)
        }
        if !editedDefaultToggles.contains(.council) {
            profile.wantsCouncil = selected.contains(.research) && !profile.wantsIronclaw
        }
        if !editedContextStyle {
            if selected.contains(.research) || selected.contains(.buildAgents) || selected.contains(.teamProjects) {
                profile.contextStyle = .project
            } else {
                profile.contextStyle = .simple
            }
        }
    }

    private func setupToggleBinding(_ toggle: SetupDefaultToggle, keyPath: WritableKeyPath<UserSetupProfile, Bool>) -> Binding<Bool> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { value in
                profile[keyPath: keyPath] = value
                editedDefaultToggles.insert(toggle)
            }
        )
    }

    private var setupExamples: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Start with an example")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(UserSetupStarterPreset.allCases) { preset in
                        SetupExampleChip(
                            preset: preset,
                            isSelected: profile.useCases == [preset.useCase] && profile.goalText == preset.prompt
                        ) {
                            profile.applyStarterPreset(preset)
                            editedContextStyle = true
                            editedDefaultToggles.insert(.ironclaw)
                            editedDefaultToggles.insert(.council)
                        }
                    }
                }

                Menu {
                    ForEach(UserSetupStarterPreset.allCases) { preset in
                        Button {
                            profile.applyStarterPreset(preset)
                            editedContextStyle = true
                            editedDefaultToggles.insert(.ironclaw)
                            editedDefaultToggles.insert(.council)
                        } label: {
                            Label(preset.title, systemImage: preset.symbolName)
                        }
                    }
                } label: {
                    Label("Choose an example", systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

private struct SetupGoalField: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What should this app help you do?", systemImage: "text.badge.plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            TextField("Research, build agents, write code, manage projects...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .tokenInputTraits()
                .padding(12)
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.appBorder : Color.brandBlue.opacity(0.14), lineWidth: 1)
                }
                .onChange(of: text) { _, value in
                    if value.count > 280 {
                        text = String(value.prefix(280))
                    }
                }
        }
    }
}

private struct SetupHeroMetric: View {
    let title: String
    let symbolName: String

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Color.brandSky)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SetupExampleChip: View {
    let preset: UserSetupStarterPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(preset.title, systemImage: preset.symbolName)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isSelected ? Color.primaryAction : Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(isSelected ? Color.selectionSubtle : Color.panel, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.primaryAction.opacity(0.16) : Color.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct SetupQuietWebToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isOn ? "globe" : "globe.slash")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isOn ? Color.primaryAction : Color.textSecondary)
                .frame(width: 34, height: 34)
                .background(isOn ? Color.selectionSubtle : Color.secondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Use the web")
                    .font(.subheadline.weight(.semibold))
                Text(isOn ? "Current-source search can leave the private route." : "Off by default. Turn on only when current sources matter.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Toggle("Use the web", isOn: $isOn)
                .labelsHidden()
                .tint(.primaryAction)
        }
        .padding(12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        }
    }
}

private struct SetupChoiceRow: View {
    enum SelectionStyle {
        case single
        case multi
    }

    let title: String
    let subtitle: String
    let symbolName: String
    let isSelected: Bool
    var selectionStyle: SelectionStyle = .single
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbolName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? Color.brandBlue : .secondary)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? Color.appSymbolBlueBackground : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selectionSymbolName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.brandBlue : Color.secondary.opacity(0.35))
            }
            .padding(12)
            .background(isSelected ? Color.appSelection : Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.brandBlue.opacity(0.14) : Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var selectionSymbolName: String {
        switch selectionStyle {
        case .single:
            return isSelected ? "checkmark.circle.fill" : "circle"
        case .multi:
            return isSelected ? "checkmark.square.fill" : "square"
        }
    }
}

private struct SetupReadinessLine: View {
    let plan: AppSetupPlan

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: plan.modelRoute.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 26, height: 26)
                .background(Color.secondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.readinessStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(plan.focusBehavior)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct SetupToggleRow: View {
    let title: String
    let subtitle: String
    let symbolName: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: symbolName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isOn ? Color.brandBlue : .secondary)
                    .frame(width: 40, height: 40)
                    .background(isOn ? Color.appSymbolBlueBackground : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(.brandBlue)
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}

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
                if let starterProjectName = plan.starterProjectName {
                    SetupPlanLine(symbolName: "folder.badge.plus", title: "Project", value: starterProjectName)
                }
                if let firstRunDraft = plan.firstRunDraft {
                    SetupPlanLine(symbolName: "text.cursor", title: "Prompt", value: firstRunDraft)
                }
                SetupPlanLine(symbolName: "arrow.right.circle", title: "First action", value: plan.expectedFirstAction)
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
