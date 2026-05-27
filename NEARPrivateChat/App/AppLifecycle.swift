import SwiftUI

struct AppLifecycleModifier: ViewModifier {
    @ObservedObject private var sessionStore: SessionStore
    @ObservedObject private var chatStore: ChatStore
    @ObservedObject private var router: AppRouter

    init(sessionStore: SessionStore, chatStore: ChatStore, router: AppRouter) {
        self.sessionStore = sessionStore
        self.chatStore = chatStore
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
                await prepareAuthenticatedChatState()
                chatStore.updateCurrentUser(profile: sessionStore.profile)
                router.resetForAccountSwitch(sessionStore.setupAccountID)
            }
            .onChange(of: sessionStore.session?.token) { _, token in
                Task {
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
                        chatStore.updateCurrentUser(profile: nil)
                        chatStore.prepareForAuthenticatedAccount(nil)
                    } else {
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
                        chatStore.prepareForAuthenticatedAccount(accountID)
                    }
                    await chatStore.bootstrap()
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
        chatStore.updateCurrentUser(profile: sessionStore.profile)
        chatStore.prepareForAuthenticatedAccount(sessionStore.setupAccountID)
        sessionStore.scheduleProfileRefresh(force: false)
        await chatStore.bootstrap()
    }
}
