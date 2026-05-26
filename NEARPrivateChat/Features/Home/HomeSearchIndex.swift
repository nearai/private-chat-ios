import Foundation

enum HomeFilter: String, CaseIterable, Identifiable {
    case all
    case shared
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .shared: "Shared"
        case .archived: "Archived"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "bubble.left.and.bubble.right"
        case .shared: "person.2"
        case .archived: "archivebox"
        }
    }
}

struct SetupLaunchCardState: Identifiable {
    let accountID: String
    let profile: UserSetupProfile
    let plan: AppSetupPlan

    var id: String {
        "\(accountID)-\(plan.id)"
    }
}

struct HomeConversationGroup: Hashable {
    let title: String
    let conversations: [ConversationSummary]
}

struct HomeProjectContextMatch: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case file
        case link
        case note
        case instructions
        case memory

        var title: String {
            switch self {
            case .file: "File"
            case .link: "Link"
            case .note: "Note"
            case .instructions: "Instructions"
            case .memory: "Memory"
            }
        }

        var symbolName: String {
            switch self {
            case .file: "doc.text"
            case .link: "link"
            case .note: "bookmark"
            case .instructions: "text.alignleft"
            case .memory: "brain.head.profile"
            }
        }
    }

    let id: String
    let project: ChatProject
    let kind: Kind
    let title: String
    let detail: String?
}

enum HomeSearchIndex {
    static func conversationGroups(
        searchQuery: String,
        conversations: [ConversationSummary],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HomeConversationGroup] {
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conversations.isEmpty else { return [] }

        if !normalizedQuery.isEmpty {
            return [HomeConversationGroup(title: "Chats", conversations: conversations)]
        }

        let todayStart = calendar.startOfDay(for: now).timeIntervalSince1970
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))?.timeIntervalSince1970 ?? todayStart

        let pinned = conversations.filter(\.isPinned)
        let normal = conversations.filter { !$0.isPinned }
        let today = normal.filter { ($0.createdAt ?? 0) >= todayStart }
        let yesterday = normal.filter {
            let createdAt = $0.createdAt ?? 0
            return createdAt < todayStart && createdAt >= yesterdayStart
        }
        let older = normal.filter { ($0.createdAt ?? 0) < yesterdayStart }

        return [
            HomeConversationGroup(title: "Pinned", conversations: pinned),
            HomeConversationGroup(title: "Today", conversations: today),
            HomeConversationGroup(title: "Yesterday", conversations: yesterday),
            HomeConversationGroup(title: "Earlier", conversations: older)
        ].filter { !$0.conversations.isEmpty }
    }

    static func projectContextMatches(query: String, projects: [ChatProject]) -> [HomeProjectContextMatch] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        return projects.flatMap { project in
            var results: [HomeProjectContextMatch] = []

            for attachment in project.attachments where matches(attachment.name, query: normalizedQuery) {
                let detailParts = [attachment.displayKind, attachment.displaySize].compactMap { $0 }
                results.append(
                    HomeProjectContextMatch(
                        id: "\(project.id)-attachment-\(attachment.id)",
                        project: project,
                        kind: .file,
                        title: attachment.name,
                        detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · ")
                    )
                )
            }

            for link in project.links where matches(link.displayTitle, query: normalizedQuery) || matches(link.urlString, query: normalizedQuery) {
                results.append(
                    HomeProjectContextMatch(
                        id: "\(project.id)-link-\(link.id)",
                        project: project,
                        kind: .link,
                        title: link.displayTitle,
                        detail: link.host ?? link.urlString
                    )
                )
            }

            for note in project.notes where matches(note.title, query: normalizedQuery) || matches(note.text, query: normalizedQuery) {
                results.append(
                    HomeProjectContextMatch(
                        id: "\(project.id)-note-\(note.id)",
                        project: project,
                        kind: .note,
                        title: note.title,
                        detail: snippet(note.text)
                    )
                )
            }

            if matches(project.instructions, query: normalizedQuery) {
                results.append(
                    HomeProjectContextMatch(
                        id: "\(project.id)-instructions",
                        project: project,
                        kind: .instructions,
                        title: "Project instructions",
                        detail: snippet(project.instructions)
                    )
                )
            }

            if matches(project.memorySummary, query: normalizedQuery) {
                results.append(
                    HomeProjectContextMatch(
                        id: "\(project.id)-memory",
                        project: project,
                        kind: .memory,
                        title: "Memory summary",
                        detail: snippet(project.memorySummary)
                    )
                )
            }

            return results
        }
    }

    private static func matches(_ text: String, query: String) -> Bool {
        text.localizedCaseInsensitiveContains(query)
    }

    private static func snippet(_ text: String, limit: Int = 84) -> String? {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= limit {
            return collapsed
        }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
