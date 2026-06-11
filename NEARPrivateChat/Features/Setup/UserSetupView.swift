import SwiftUI

private enum SetupDefaultToggle: Hashable {
    case web
    case ironclaw
    case council
}

struct UserSetupView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    let readiness: AppSetupReadinessSnapshot
    let onComplete: (UserSetupProfile) -> Void
    let onSkip: () -> Void
    @State private var profile: UserSetupProfile
    @State private var editedDefaultToggles: Set<SetupDefaultToggle> = []
    @State private var editedContextStyle = false
    @State private var showsCapabilitySetup: Bool

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
        _showsCapabilitySetup = State(
            initialValue: initialProfile.experienceMode == .power ||
                initialProfile.wantsIronclaw ||
                initialProfile.wantsCouncil ||
                initialProfile.contextStyle != .simple ||
                initialProfile.wantsWeb
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    setupHero

                    SetupGoalField(text: $profile.goalText)

                    setupExamples

                    setupUseCases

                    setupExperienceMode

                    setupCapabilitiesDisclosure

                    SetupReadinessLine(plan: setupPlan)

                    setupPreview
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(HomeSurfaceBackground())
            .navigationTitle("Defaults")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                setupFooter
            }
        }
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

            Button("Keep current defaults") {
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
        "Save defaults"
    }

    private var setupPlan: AppSetupPlan {
        AppSetupPlan(profile: profile.normalizedForDefaults, readiness: readiness)
    }

    private var setupHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                PrivacySeal(size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Tune defaults for new chats")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Choose what new chats use by default. Private chat stays first; web, Agent, and Council add reach with more setup and off-device requests.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                SetupHeroMetric(title: "Private", symbolName: "lock.shield")
                SetupHeroMetric(title: "Sources", symbolName: "folder")
                SetupHeroMetric(title: "Routes", symbolName: "slider.horizontal.3")
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
        .shadow(color: Color.brandAccent.opacity(0.14), radius: 18, y: 8)
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
        setupSection(title: "Default controls") {
            ForEach(UserSetupExperienceMode.allCases) { mode in
                SetupChoiceRow(
                    title: mode.title,
                    subtitle: mode.subtitle,
                    symbolName: mode.symbolName,
                    isSelected: profile.experienceMode == mode
                ) {
                    setExperienceMode(mode)
                }
            }
        }
    }

    private var setupUseCases: some View {
        setupSection(title: "Default work mode") {
            ForEach(UserSetupUseCase.allCases) { useCase in
                SetupChoiceRow(
                    title: useCase.title,
                    subtitle: useCase.subtitle,
                    symbolName: useCase.symbolName,
                    isSelected: profile.useCases.contains(useCase),
                    selectionStyle: .multi
                ) {
                    profile.toggleUseCase(useCase)
                    applyUseCaseDefaultsFromSelection()
                }
            }
        }
    }

    private var setupContextStyle: some View {
        setupSection(title: "Sources & memory") {
            ForEach(UserSetupContextStyle.allCases) { style in
                SetupChoiceRow(
                    title: style.title,
                    subtitle: style.subtitle,
                    symbolName: style.symbolName,
                    isSelected: profile.contextStyle == style
                ) {
                    profile.contextStyle = style
                    editedContextStyle = true
                }
            }
        }
    }

    private var setupCapabilitiesDisclosure: some View {
        setupSection(title: "Optional capabilities") {
            DisclosureGroup(isExpanded: $showsCapabilitySetup) {
                VStack(alignment: .leading, spacing: 16) {
                    setupContextStyle

                    SetupQuietWebToggle(isOn: setupToggleBinding(.web, keyPath: \.wantsWeb))

                    setupAdvancedRoutesContent

                    Text("You can change these defaults later from Account. Existing chats keep their history.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)
            } label: {
                SetupCapabilityDisclosureLabel(
                    title: capabilityDisclosureTitle,
                    detail: capabilityDisclosureDetail,
                    sourceStyle: profile.contextStyle.title,
                    webEnabled: profile.wantsWeb,
                    wantsIronclaw: profile.wantsIronclaw,
                    wantsCouncil: profile.wantsCouncil,
                    experienceMode: profile.experienceMode
                )
            }
            .tint(.primary)
            .padding(12)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.border, lineWidth: 1)
            }
        }
    }

    private var setupPreview: some View {
        setupSection(title: "Default behavior preview") {
            SetupPlanPreviewCard(plan: setupPlan)
        }
    }

    private func applyUseCaseDefaultsFromSelection() {
        profile.applyUseCaseSelectionDefaults(
            editedWeb: editedDefaultToggles.contains(.web),
            editedIronclaw: editedDefaultToggles.contains(.ironclaw),
            editedCouncil: editedDefaultToggles.contains(.council),
            editedContextStyle: editedContextStyle
        )
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

    private func setExperienceMode(_ mode: UserSetupExperienceMode) {
        guard profile.experienceMode != mode else { return }
        profile.experienceMode = mode
        if mode == .beginner {
            editedDefaultToggles.remove(.ironclaw)
            editedDefaultToggles.remove(.council)
            profile.wantsIronclaw = false
            profile.wantsCouncil = false
        } else {
            showsCapabilitySetup = true
            applyUseCaseDefaultsFromSelection()
        }
    }

    private var capabilityDisclosureTitle: String {
        if profile.experienceMode == .power {
            return "Optional capabilities are available"
        }
        return "Private-first defaults are enough to start"
    }

    private var capabilityDisclosureDetail: String {
        if profile.experienceMode == .power {
            return "Turn on web, Council, and Agent defaults only when you want the extra reach."
        }
        if profile.useCases.contains(.research) && profile.wantsWeb {
            return "Research starts with web search on. Queries and selected context can leave the private route."
        }
        return "Expand to decide what can use Project context, live web, or advanced routes."
    }

    @ViewBuilder
    private var setupAdvancedRoutesContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Model route")
                .font(.headline.weight(.bold))
                .foregroundStyle(.secondary)

            if profile.experienceMode == .power {
                VStack(spacing: 8) {
                    SetupToggleRow(
                        title: "Agent",
                        subtitle: ironclawToggleSubtitle,
                        symbolName: "terminal",
                        isOn: setupToggleBinding(.ironclaw, keyPath: \.wantsIronclaw)
                    )

                    SetupToggleRow(
                        title: "LLM Council",
                        subtitle: councilToggleSubtitle,
                        symbolName: "square.grid.2x2",
                        isOn: setupToggleBinding(.council, keyPath: \.wantsCouncil)
                    )
                }
            } else {
                SetupInfoCard(
                    title: "Beginner mode keeps the route simple",
                    detail: "Start with private chat, sources, and Project memory. Switch to Power whenever you want Agent or Council defaults visible.",
                    symbolName: "sparkles"
                )
            }
        }
    }

    private var ironclawToggleSubtitle: String {
        if readiness.ironclawMobileAvailable {
            return "Agent tasks can use hosted tools and Project context. Use it when actions matter more than staying private-only."
        }
        return "Private chat stays ready first while Agent setup finishes."
    }

    private var councilToggleSubtitle: String {
        if !readiness.modelCatalogLoaded {
            return "The model lineup is still loading. Private chat stays ready first."
        }
        if readiness.councilReady {
            return "Ask several models at once for comparison. It can cost more and may use non-private routes."
        }
        return "Needs at least two available models. Private chat stays ready first."
    }

    private var setupExamples: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Load a preset")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(UserSetupStarterPreset.allCases) { preset in
                        SetupExampleChip(
                            preset: preset,
                            isSelected: profile.useCases == [preset.useCase] &&
                                profile.goalText == preset.setupExampleGoalText
                        ) {
                            selectStarterPreset(preset)
                        }
                    }
                }

                Menu {
                    ForEach(UserSetupStarterPreset.allCases) { preset in
                        Button {
                            selectStarterPreset(preset)
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

    private func selectStarterPreset(_ preset: UserSetupStarterPreset) {
        profile.applyStarterPreset(preset)
        if preset.wantsIronclaw || preset.wantsCouncil {
            profile.experienceMode = .power
            showsCapabilitySetup = true
        }
        // Starter presets are shortcuts, not manual lock-ins for later use-case changes.
        editedContextStyle = false
        editedDefaultToggles.removeAll()
    }
}
