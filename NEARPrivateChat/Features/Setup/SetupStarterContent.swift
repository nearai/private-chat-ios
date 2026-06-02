import Foundation

struct SetupPromptSuggestion: Codable, Identifiable, Hashable {
    let title: String
    let symbolName: String
    let prompt: String

    var id: String {
        "\(title)-\(prompt)"
    }
}

struct SetupWorkspaceSeed: Codable, Identifiable, Hashable {
    let title: String
    let detail: String
    let symbolName: String

    var id: String {
        "\(title)-\(detail)"
    }
}

struct SetupAgentMissionSuggestion: Codable, Hashable {
    let title: String
    let detail: String
    let prompt: String
}
