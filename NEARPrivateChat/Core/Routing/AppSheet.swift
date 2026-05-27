import Foundation

enum AppSheet: Identifiable, Hashable {
    case modelPicker
    case share(conversationID: String)
    case projectFiles(projectID: String)
    case setup(accountID: String)
    case accountSettings

    var id: String {
        switch self {
        case .modelPicker:
            return "modelPicker"
        case .share(let conversationID):
            return "share:\(conversationID)"
        case .projectFiles(let projectID):
            return "projectFiles:\(projectID)"
        case .setup(let accountID):
            return "setup:\(accountID)"
        case .accountSettings:
            return "accountSettings"
        }
    }
}
