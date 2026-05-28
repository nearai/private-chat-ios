import Foundation

struct AppEnvironment {
    let api: PrivateChatAPI
    let sessionStore: SessionStore
    let chatStore: ChatStore
    let briefingStore: BriefingStore

    @MainActor
    static func production() -> AppEnvironment {
        let api = PrivateChatAPI(configuration: .production)
        let sessionStore = SessionStore(api: api)
        let chatStore = ChatStore(api: api)
        let briefingStore = BriefingStore()
        #if DEBUG
        if DemoCapture.isEnabled {
            briefingStore.seedDemoSamples()
        } else {
            briefingStore.load()
        }
        #else
        briefingStore.load()
        #endif
        briefingStore.runner = { [weak chatStore] briefing in
            guard let chatStore else { return nil }
            return await chatStore.runBriefing(briefing)
        }
        return AppEnvironment(
            api: api,
            sessionStore: sessionStore,
            chatStore: chatStore,
            briefingStore: briefingStore
        )
    }
}
