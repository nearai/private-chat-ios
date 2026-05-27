import Foundation

struct ProjectStore {
    let projects: [ChatProject]
    let selectedProjectID: String?
    let conversations: [ConversationSummary]

    var selectedProject: ChatProject? {
        guard let selectedProjectID else { return nil }
        return projects.first(where: { $0.id == selectedProjectID })
    }

    var projectScopedConversations: [ConversationSummary] {
        guard let selectedProject else { return conversations }
        let ids = Set(selectedProject.conversationIDs)
        return conversations.filter { ids.contains($0.id) }
    }

    var visibleConversations: [ConversationSummary] {
        projectScopedConversations
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return (lhs.createdAt ?? 0) > (rhs.createdAt ?? 0)
            }
    }

    var allVisibleConversations: [ConversationSummary] {
        conversations
            .filter { !$0.isArchived }
            .sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
    }

    var archivedConversations: [ConversationSummary] {
        conversations
            .filter(\.isArchived)
            .sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
    }
}
