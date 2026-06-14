import SwiftUI
import CoreSpotlight

struct AppLifecycleModifier: ViewModifier {
    @ObservedObject private var sessionStore: SessionStore
    @ObservedObject private var chatStore: ChatStore
    @ObservedObject private var shareStore: ShareStore
    @ObservedObject private var briefingStore: BriefingStore
    @ObservedObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    init(sessionStore: SessionStore, chatStore: ChatStore, shareStore: ShareStore, briefingStore: BriefingStore, router: AppRouter) {
        self.sessionStore = sessionStore
        self.chatStore = chatStore
        self.shareStore = shareStore
        self.briefingStore = briefingStore
        self.router = router
    }

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                if !sessionStore.handleIncomingURL(url) {
                    chatStore.handleIncomingURL(url)
                }
            }
            .task {
                briefingStore.setNotificationAuthorizationRequestsEnabled(sessionStore.isSignedIn)
                await prepareAuthenticatedChatState()
                chatStore.updateCurrentUser(profile: sessionStore.profile)
                router.resetForAccountSwitch(sessionStore.setupAccountID)
                await consumeSiriCommands()
                await briefingStore.runDue()
                #if DEBUG
                if DemoCapture.isEnabled { return }
                #endif
                NEARPrivateChatApp.scheduleBriefingRefresh()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await consumeSiriCommands() }
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                    chatStore.openConversation(byID: id)
                }
            }
            .onChange(of: sessionStore.session?.token) { _, token in
                Task {
                    briefingStore.setNotificationAuthorizationRequestsEnabled(token?.isEmpty == false)
                    #if DEBUG
                    if DemoCapture.isEnabled {
                        sessionStore.configureDemoCaptureSession()
                        chatStore.prepareDemoCapture(screen: DemoCapture.initialScreen)
                        router.resetForAccountSwitch(sessionStore.setupAccountID)
                        return
                    }
                    #endif
                    if token == nil {
                        router.resetForSignOut()
                        shareStore.reset()
                        chatStore.updateCurrentUser(profile: nil)
                        chatStore.prepareForAuthenticatedAccount(nil)
                    } else {
                        chatStore.resetConnectionStateForCredentialChange()
                        router.resetForAccountSwitch(sessionStore.setupAccountID)
                        await prepareAuthenticatedChatState()
                    }
                }
            }
            .onChange(of: sessionStore.profile) { _, profile in
                chatStore.updateCurrentUser(profile: profile)
            }
            .onChange(of: sessionStore.setupAccountID) { oldAccountID, accountID in
                router.resetForAccountSwitch(accountID)
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
                    if oldAccountID != accountID {
                        shareStore.reset()
                        chatStore.prepareForAuthenticatedAccount(accountID)
                    }
                    await chatStore.bootstrap()
                }
            }
    }

    /// Drains anything staged by an out-of-process hand-off: a question from an
    /// App Intent (Siri/Shortcuts), text/URL from the share extension, and a
    /// request to refresh briefings. A Siri prompt wins if both are present
    /// (the share file stays for the next activation).
    @MainActor
    private func consumeSiriCommands() async {
        if !chatStore.consumePendingSiriPrompt() {
            await chatStore.consumePendingSharedItem()
        }
        if UserDefaults.standard.bool(forKey: ChatStore.pendingRunBriefingsKey) {
            UserDefaults.standard.removeObject(forKey: ChatStore.pendingRunBriefingsKey)
            await briefingStore.runDue()
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
        chatStore.updateCurrentUser(profile: sessionStore.profile)
        chatStore.prepareForAuthenticatedAccount(sessionStore.setupAccountID)
        shareStore.reset()
        sessionStore.scheduleProfileRefresh(force: false)
        // Probe the private session right after sign-in so an invalid/expired
        // session token surfaces in diagnostics immediately, instead of being
        // discovered (and laundered into "temporarily busy") on the first chat.
        // Concurrent with bootstrap — the probe informs diagnostics, it must
        // never delay launch.
        async let probe: ConnectionDiagnostics.Outcome? = chatStore.probePrivateSession()
        await chatStore.bootstrap()
        _ = await probe
        await shareStore.refreshSharedWithMe(showErrors: false)
    }
}
