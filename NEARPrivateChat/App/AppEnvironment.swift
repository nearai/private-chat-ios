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
        #if DEBUG
        // Demo capture uses an isolated briefings file so its seeded samples
        // (and the saves their scheduled runs trigger) never pollute the real
        // briefings.json a normal/interactive session loads.
        let briefingStore = DemoCapture.isEnabled
            ? BriefingStore(fileURL: BriefingStore.demoFileURL())
            : BriefingStore()
        if DemoCapture.isEnabled {
            briefingStore.seedDemoSamples()
        } else {
            briefingStore.load()
        }
        #else
        let briefingStore = BriefingStore()
        briefingStore.load()
        #endif
        briefingStore.runner = { [weak chatStore] briefing in
            guard let chatStore else { return nil }
            let widget = await chatStore.runBriefing(briefing)
            if widget != nil {
                chatStore.activityLog.record("Ran briefing “\(briefing.title)”")
            }
            return widget
        }
        chatStore.onCreateTracker = { [weak briefingStore] briefing in
            guard let briefingStore else { return }
            briefingStore.add(briefing)
            Task { await briefingStore.run(briefing) }
        }
        chatStore.trackersProvider = { [weak briefingStore] in briefingStore?.briefings ?? [] }
        return AppEnvironment(
            api: api,
            sessionStore: sessionStore,
            chatStore: chatStore,
            briefingStore: briefingStore
        )
    }
}
