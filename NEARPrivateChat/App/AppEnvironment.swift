import Foundation

struct AppEnvironment {
    let api: PrivateChatAPI
    let sessionStore: SessionStore
    let chatStore: ChatStore

    @MainActor
    static func production() -> AppEnvironment {
        let api = PrivateChatAPI(configuration: .production)
        let sessionStore = SessionStore(api: api)
        return AppEnvironment(
            api: api,
            sessionStore: sessionStore,
            chatStore: ChatStore(api: api)
        )
    }
}
