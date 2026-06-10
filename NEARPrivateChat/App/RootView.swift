import SwiftUI

struct RootView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var chatStore: ChatStore
    @State private var presentedSetupAccountID: String?
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
        .preferredColorScheme(chatStore.appearancePreference.preferredColorScheme)
        .onAppear {
            refreshLegalTermsAcceptance()
        }
        .onChange(of: sessionStore.session?.token) { _, _ in
            refreshLegalTermsAcceptance()
        }
        .onReceive(NotificationCenter.default.publisher(for: .legalTermsAcceptanceDidChange)) { _ in
            if sessionStore.isSignedIn, sessionStore.setupAccountID != nil {
                // Promote AuthView's pending acceptance into the per-account
                // record so we exit the AuthView branch on the next render.
                acceptLegalTermsForCurrentAccount()
            } else {
                refreshLegalTermsAcceptance()
            }
        }
        .onChange(of: sessionStore.setupAccountID) { oldAccountID, accountID in
            refreshLegalTermsAcceptance(previousAccountID: oldAccountID, currentAccountID: accountID)
            migrateSetupStorageIfNeeded(previousAccountID: oldAccountID)
        }
        .sheet(
            isPresented: Binding(
                get: { presentedSetupAccountID != nil },
                set: { isPresented in
                    if !isPresented {
                        presentedSetupAccountID = nil
                    }
                }
            )
        ) {
            if let accountID = presentedSetupAccountID {
                UserSetupView(
                    initialProfile: setupDefaultsTuningProfile(for: accountID),
                    readiness: setupReadinessSnapshot,
                    onComplete: { profile in
                        completeSetup(profile, for: accountID)
                    },
                    onSkip: {
                        skipSetup(for: accountID)
                    }
                )
                .environmentObject(chatStore)
            }
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
        .overlay(alignment: .bottomTrailing) {
            // ReleaseGate state beacon: lets the live harness wait on app state
            // instead of scraping pixels. Invisible in normal use; only present
            // when launched with -NEARReleaseGate.
            #if DEBUG
            if Self.isReleaseGateRun {
                Text(gateStateDescription)
                    .font(.system(size: 4))
                    .frame(width: 4, height: 4)
                    .opacity(0.02)
                    .accessibilityIdentifier("gate.state")
                    .accessibilityLabel(gateStateDescription)
            }
            #endif
        }
    }

    #if DEBUG
    static let isReleaseGateRun = ProcessInfo.processInfo.arguments.contains("-NEARReleaseGate")

    private var gateStateDescription: String {
        let lastStatus = chatStore.messages.last?.status ?? "none"
        return "streaming=\(chatStore.isStreaming ? "1" : "0");last=\(lastStatus);count=\(chatStore.messages.count)"
    }
    #endif

    @ViewBuilder
    private var authenticatedRoot: some View {
        // v2 Claude Design Auth: a signed-in user whose terms have not been
        // accepted falls back to AuthView (terms-pending state) rather than
        // routing to a separate LegalTermsRequiredView. AuthView writes the
        // pending acceptance to LegalTermsAcceptanceStore and posts
        // `.legalTermsAcceptanceDidChange`; RootView promotes it for the
        // current account on receipt.
        if sessionStore.isSignedIn && (legalTermsAccepted || Self.isDebugInteractiveSession) {
            AppShellView {
                beginSetupRerun()
            }
        } else {
            AuthView()
        }
    }

    /// DEBUG interactive testing (launched with the env token, no demo flag):
    /// skip the per-account legal-terms gate so the real app opens straight to
    /// Home. Never true in a normal build/run.
    private static var isDebugInteractiveSession: Bool {
        #if DEBUG
        return DebugBackend.isEnabled && !DemoCapture.isEnabled
        #else
        return false
        #endif
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
        // Setup is optional defaults tuning now; completion state changes only
        // after the user saves or explicitly keeps current defaults.
        UserSetupStorage.clearPendingLaunchCard(for: accountID)
        presentedSetupAccountID = accountID
    }

    private func setupDefaultsTuningProfile(for accountID: String) -> UserSetupProfile {
        UserSetupStorage.load(for: accountID) ?? currentSetupProfile
    }

    private func completeSetup(_ profile: UserSetupProfile, for accountID: String) {
        let savedProfile = chatStore.setupProfileSnapshot(profile)
        UserSetupStorage.saveWithoutPendingLaunchCard(savedProfile, for: accountID)
        presentedSetupAccountID = nil
        recordSetupTelemetry(profile: savedProfile, outcome: .completed)
        chatStore.applySetupProfile(savedProfile)
    }

    private func skipSetup(for accountID: String) {
        let profile = chatStore.setupProfileSnapshot(
            setupDefaultsTuningProfile(for: accountID)
        )
        UserSetupStorage.saveWithoutPendingLaunchCard(profile, for: accountID)
        presentedSetupAccountID = nil
        recordSetupTelemetry(profile: profile, outcome: .skipped)
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
    }

    private func migrateSetupStorageIfNeeded(previousAccountID: String?) {
        guard sessionStore.isSignedIn, let accountID = sessionStore.setupAccountID else { return }
        if let previousAccountID, previousAccountID != accountID {
            UserSetupStorage.migrate(from: previousAccountID, to: accountID)
        } else if let presentedSetupAccountID, presentedSetupAccountID != accountID {
            UserSetupStorage.migrate(from: presentedSetupAccountID, to: accountID)
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
