import Foundation

enum AppRoute: Hashable {
    case chat(conversationID: String)
    case sharedConversation(id: String)
    case project(id: String)
    case security
    case account
}
