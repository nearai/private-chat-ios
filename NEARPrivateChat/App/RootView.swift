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
                    initialProfile: UserSetupStorage.presentationProfile(
                        for: accountID,
                        currentDefaults: currentSetupProfile
                    ),
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
        let defaults = UserSetupProfile.defaults.normalizedForDefaults
        UserSetupStorage.saveWithoutPendingLaunchCard(defaults, for: accountID)
        chatStore.resetInteractionDefaults()
        recordSetupTelemetry(profile: defaults, outcome: .completed)
        presentedSetupAccountID = nil
    }

    private func completeSetup(_ profile: UserSetupProfile, for accountID: String) {
        let normalized = profile.normalizedForDefaults
        UserSetupStorage.saveWithoutPendingLaunchCard(normalized, for: accountID)
        presentedSetupAccountID = nil
        recordSetupTelemetry(profile: normalized, outcome: .completed)
        chatStore.applySetupProfile(normalized)
    }

    private func skipSetup(for accountID: String) {
        let profile = UserSetupStorage.presentationProfile(for: accountID, currentDefaults: currentSetupProfile)
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
        refreshSetupPresentation()
    }

    private func refreshSetupPresentation(previousAccountID: String? = nil) {
        guard sessionStore.isSignedIn, let accountID = sessionStore.setupAccountID else {
            presentedSetupAccountID = nil
            return
        }

        guard LegalTermsAcceptanceStore.hasAcceptedCurrentVersion(for: accountID) else {
            presentedSetupAccountID = nil
            return
        }

        if let previousAccountID, previousAccountID != accountID {
            UserSetupStorage.migrate(from: previousAccountID, to: accountID)
        } else if let presentedSetupAccountID, presentedSetupAccountID != accountID {
            UserSetupStorage.migrate(from: presentedSetupAccountID, to: accountID)
        }

        if !UserSetupStorage.isCompleted(for: accountID) {
            presentedSetupAccountID = accountID
        } else if presentedSetupAccountID == accountID {
            presentedSetupAccountID = nil
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
