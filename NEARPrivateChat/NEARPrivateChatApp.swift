import SwiftUI

#if DEBUG
enum DemoCaptureScreen: String, CaseIterable {
    case onboarding
    case login
    case home
    case fileAttach
    case glmResult
    case chat
    case councilOutput
    case verification
    case models
    case cloudModels
    case council
    case composer
    case agent
    case ironclawThinking
    case ironclaw
    case project
    case share

    init(rawValueOrDefault rawValue: String?) {
        guard let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let screen = DemoCaptureScreen.allCases.first(where: { $0.rawValue.lowercased() == normalized }) else {
            self = .onboarding
            return
        }
        self = screen
    }
}

enum DemoCapture {
    static var isEnabled: Bool {
        CommandLine.arguments.contains("-NEARDemoCapture") ||
            ProcessInfo.processInfo.environment["NEAR_DEMO_CAPTURE"] == "1"
    }

    static var isAutoPlayEnabled: Bool {
        CommandLine.arguments.contains("-NEARDemoAutoPlay") ||
            ProcessInfo.processInfo.environment["NEAR_DEMO_AUTOPLAY"] == "1"
    }

    static var initialScreen: DemoCaptureScreen {
        let argumentPrefix = "-NEARDemoScreen="
        let argumentValue = CommandLine.arguments.first { $0.hasPrefix(argumentPrefix) }
            .map { String($0.dropFirst(argumentPrefix.count)) }
        return DemoCaptureScreen(rawValueOrDefault: argumentValue ?? ProcessInfo.processInfo.environment["NEAR_DEMO_SCREEN"])
    }

    static var autoPlayDelayNanoseconds: UInt64 {
        let argumentPrefix = "-NEARDemoAutoPlayDelayMS="
        let argumentValue = CommandLine.arguments.first { $0.hasPrefix(argumentPrefix) }
            .flatMap { UInt64(String($0.dropFirst(argumentPrefix.count))) }
        let environmentValue = ProcessInfo.processInfo.environment["NEAR_DEMO_AUTOPLAY_DELAY_MS"].flatMap(UInt64.init)
        return (argumentValue ?? environmentValue ?? 0) * 1_000_000
    }
}
#endif

@main
struct NEARPrivateChatApp: App {
    @StateObject private var sessionStore: SessionStore
    @StateObject private var chatStore: ChatStore

    init() {
        let api = PrivateChatAPI(configuration: .production)
        let sessionStore = SessionStore(api: api)
        _sessionStore = StateObject(wrappedValue: sessionStore)
        _chatStore = StateObject(wrappedValue: ChatStore(api: api))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionStore)
                .environmentObject(chatStore)
                .onOpenURL { url in
                    if !sessionStore.handleIncomingURL(url) {
                        chatStore.handleIncomingURL(url)
                    }
                }
                .task {
                    await prepareAuthenticatedChatState()
                }
                .onChange(of: sessionStore.session?.token) { _, token in
                    Task {
                        #if DEBUG
                        if DemoCapture.isEnabled {
                            sessionStore.configureDemoCaptureSession()
                            chatStore.prepareDemoCapture(screen: DemoCapture.initialScreen)
                            return
                        }
                        #endif
                        if token == nil {
                            chatStore.prepareForAuthenticatedAccount(nil)
                        } else {
                            await prepareAuthenticatedChatState()
                        }
                    }
                }
                .onChange(of: sessionStore.setupAccountID) { _, accountID in
                    guard sessionStore.isSignedIn else { return }
                    #if DEBUG
                    if DemoCapture.isEnabled {
                        chatStore.prepareForAuthenticatedAccount(accountID)
                        chatStore.prepareDemoCapture(screen: DemoCapture.initialScreen)
                        return
                    }
                    #endif
                    if let accountID,
                       UserSetupStorage.isFallbackAccountID(accountID),
                       sessionStore.profile == nil {
                        return
                    }
                    Task {
                        chatStore.prepareForAuthenticatedAccount(accountID)
                        await chatStore.bootstrap()
                    }
                }
        }
    }

    @MainActor
    private func prepareAuthenticatedChatState() async {
        #if DEBUG
        if DemoCapture.isEnabled {
            sessionStore.configureDemoCaptureSession()
            chatStore.prepareForAuthenticatedAccount(sessionStore.setupAccountID)
            chatStore.prepareDemoCapture(screen: DemoCapture.initialScreen)
            return
        }
        #endif

        guard sessionStore.isSignedIn else { return }
        await sessionStore.refreshProfile()
        chatStore.prepareForAuthenticatedAccount(sessionStore.setupAccountID)
        await chatStore.bootstrap()
    }
}

private struct RootView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var chatStore: ChatStore
    @State private var setupAccountID: String?
    @State private var legalTermsAccepted = true

    var body: some View {
        Group {
            #if DEBUG
            if DemoCapture.isEnabled {
                DemoCaptureRootView(screen: DemoCapture.initialScreen, autoPlay: DemoCapture.isAutoPlayEnabled)
            } else {
                authenticatedRoot
            }
            #else
            authenticatedRoot
            #endif
        }
        .onAppear {
            refreshLegalTermsAcceptance()
            refreshSetupPresentation()
        }
        .onChange(of: sessionStore.session?.token) { _, _ in
            refreshLegalTermsAcceptance()
            refreshSetupPresentation()
        }
        .onChange(of: sessionStore.setupAccountID) { oldAccountID, accountID in
            refreshLegalTermsAcceptance(previousAccountID: oldAccountID, currentAccountID: accountID)
            refreshSetupPresentation(previousAccountID: oldAccountID)
        }
        .overlay(alignment: .top) {
            #if DEBUG
            let shouldSuppressDemoBanner = DemoCapture.isEnabled
            #else
            let shouldSuppressDemoBanner = false
            #endif
            if !shouldSuppressDemoBanner, let message = sessionStore.bannerMessage ?? chatStore.bannerMessage {
                StatusBanner(message: message)
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var authenticatedRoot: some View {
        if sessionStore.isSignedIn {
            if legalTermsAccepted {
                AppShellView {
                    beginSetupRerun()
                }
            } else {
                LegalTermsRequiredView {
                    acceptLegalTermsForCurrentAccount()
                }
            }
        } else {
            AuthView()
        }
    }

    private var currentSetupProfile: UserSetupProfile {
        UserSetupProfile.inferredCurrentDefaults(
            webSearchEnabled: chatStore.webSearchEnabled,
            sourceMode: chatStore.sourceMode,
            selectedModelID: chatStore.selectedModel,
            hasSelectedProject: chatStore.selectedProjectID != nil,
            isCouncilModeEnabled: chatStore.isCouncilModeEnabled,
            researchModeEnabled: chatStore.researchModeEnabled
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

    private func beginSetupRerun() {
        guard sessionStore.isSignedIn, let accountID = sessionStore.setupAccountID else { return }
        setupAccountID = accountID
        UserSetupStorage.save(.defaults, for: accountID)
        chatStore.resetInteractionDefaults()
        recordSetupTelemetry(profile: .defaults, outcome: .completed)
    }

    private func recordSetupTelemetry(profile: UserSetupProfile, outcome: TelemetrySetupOutcome) {
        let store = PrivateTelemetryStore()
        let context = TelemetryContext(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "local",
            profileBucket: profile.telemetryProfileBucket
        )
        try? store.record(.setupGoalSelected(profile.telemetrySetupGoal), context: context)
        try? store.record(.setupCompletedOrSkipped(outcome), context: context)
    }

    private func refreshLegalTermsAcceptance(previousAccountID: String? = nil, currentAccountID: String? = nil) {
        guard sessionStore.isSignedIn, let accountID = currentAccountID ?? sessionStore.setupAccountID else {
            legalTermsAccepted = true
            return
        }

        if let previousAccountID, previousAccountID != accountID {
            LegalTermsAcceptanceStore.migrate(from: previousAccountID, to: accountID)
        }

        if LegalTermsAcceptanceStore.hasAcceptedCurrentVersion(for: accountID) ||
            LegalTermsAcceptanceStore.consumePendingAcceptance(for: accountID) {
            legalTermsAccepted = true
            return
        }

        legalTermsAccepted = false
    }

    private func acceptLegalTermsForCurrentAccount() {
        guard let accountID = sessionStore.setupAccountID else { return }
        LegalTermsAcceptanceStore.acceptCurrentVersion(for: accountID)
        legalTermsAccepted = true
        refreshSetupPresentation()
    }

    private func refreshSetupPresentation(previousAccountID: String? = nil) {
        guard sessionStore.isSignedIn, let accountID = sessionStore.setupAccountID else {
            setupAccountID = nil
            return
        }

        guard LegalTermsAcceptanceStore.hasAcceptedCurrentVersion(for: accountID) else {
            setupAccountID = accountID
            return
        }

        if let previousAccountID, previousAccountID != accountID {
            UserSetupStorage.migrate(from: previousAccountID, to: accountID)
        } else if let setupAccountID, setupAccountID != accountID {
            UserSetupStorage.migrate(from: setupAccountID, to: accountID)
        }

        setupAccountID = accountID
        if !UserSetupStorage.isCompleted(for: accountID) {
            UserSetupStorage.save(.defaults, for: accountID)
            recordSetupTelemetry(profile: .defaults, outcome: .skipped)
        }
    }
}

private struct LegalTermsRequiredView: View {
    let onAccept: () -> Void
    @State private var showingTerms = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AuthHeroCard()

                VStack(alignment: .leading, spacing: 14) {
                    Label("Review terms to continue", systemImage: "doc.text.magnifyingglass")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)

                    Text("Accept the current Terms before using private chat, Cloud models, files, sharing, web grounding, Council, or agent tools.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(LegalTerms.signupSummary, id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        showingTerms = true
                    } label: {
                        Label("Review terms", systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.brandBlue)
                    .background(Color.brandBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button {
                        onAccept()
                    } label: {
                        Text("Accept and continue")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.brandBlue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(18)
                .frame(maxWidth: 390, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.brandBlue.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 12, y: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
        .background { HomeSurfaceBackground().ignoresSafeArea() }
        .sheet(isPresented: $showingTerms) {
            LegalTermsSheet()
        }
    }
}

private extension UserSetupProfile {
    var telemetrySetupGoal: TelemetrySetupGoal {
        if useCases.count > 1 {
            return .unsure
        }
        switch useCases.setupPrimaryUseCase {
        case .privateChat:
            return .privateChat
        case .research:
            return .research
        case .buildAgents:
            return .agentWork
        case .teamProjects:
            return .verifiedMode
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

private enum SetupDefaultToggle: Hashable {
    case web
    case ironclaw
    case council
}

private struct UserSetupView: View {
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

                    SetupQuietWebToggle(isOn: setupToggleBinding(.web, keyPath: \.wantsWeb))

                    SetupReadinessLine(plan: AppSetupPlan(profile: profile.normalizedForDefaults, readiness: readiness))
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
        AppSetupPlan(profile: profile.normalizedForDefaults, readiness: readiness).expectedFirstAction
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

private struct StatusBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 360, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }
}
