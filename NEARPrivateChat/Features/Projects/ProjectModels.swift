import Foundation
import SwiftUI

struct ProjectLink: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var urlString: String
    var createdAt: Date

    init(
        id: String = "link-\(UUID().uuidString)",
        title: String,
        urlString: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
    }

    var url: URL? {
        URL(string: urlString)
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return host ?? urlString
    }

    var host: String? {
        url?.host()
    }
}

struct ProjectNote: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var text: String
    var createdAt: Date
    var sourceMessageID: String?

    init(
        id: String = "note-\(UUID().uuidString)",
        title: String,
        text: String,
        createdAt: Date = Date(),
        sourceMessageID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
        self.sourceMessageID = sourceMessageID
    }
}

enum ProjectPalette: String, CaseIterable, Codable, Identifiable {
    case sky
    case mint
    case teal
    case violet
    case indigo
    case rose
    case amber
    case slate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sky: "Sky"
        case .mint: "Mint"
        case .teal: "Teal"
        case .violet: "Violet"
        case .indigo: "Indigo"
        case .rose: "Rose"
        case .amber: "Amber"
        case .slate: "Slate"
        }
    }

    var tintColor: Color {
        switch self {
        case .sky: Color.primaryAction
        case .mint: Color.proofVerified
        case .teal: Color.brandSky
        case .violet: Color.purple
        case .indigo: Color.indigo
        case .rose: Color.pink
        case .amber: Color.proofStale
        case .slate: Color.textSecondary
        }
    }

    var backgroundColor: Color {
        tintColor.opacity(0.13)
    }
}

enum ProjectIcon: String, CaseIterable, Codable, Identifiable {
    case folder
    case code
    case research
    case agent
    case memo
    case chart
    case launch
    case briefcase
    case globe
    case link
    case lock
    case shield
    case sparkles
    case bolt
    case book
    case database
    case server
    case cloud
    case terminalWindow
    case pullRequest
    case branch
    case hammer
    case wrench
    case flask
    case brain
    case eye
    case people
    case calendar
    case pin
    case archive

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .folder: "folder"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .research: "text.magnifyingglass"
        case .agent: "terminal"
        case .memo: "doc.text"
        case .chart: "chart.bar"
        case .launch: "paperplane"
        case .briefcase: "briefcase"
        case .globe: "globe"
        case .link: "link"
        case .lock: "lock.shield"
        case .shield: "checkmark.shield"
        case .sparkles: "sparkles"
        case .bolt: "bolt"
        case .book: "book.closed"
        case .database: "externaldrive"
        case .server: "server.rack"
        case .cloud: "cloud"
        case .terminalWindow: "terminal"
        case .pullRequest: "arrow.triangle.pull"
        case .branch: "arrow.triangle.branch"
        case .hammer: "hammer"
        case .wrench: "wrench.and.screwdriver"
        case .flask: "flask"
        case .brain: "brain.head.profile"
        case .eye: "eye"
        case .people: "person.2"
        case .calendar: "calendar"
        case .pin: "pin"
        case .archive: "archivebox"
        }
    }

    var label: String {
        switch self {
        case .folder: "Folder"
        case .code: "Code"
        case .research: "Research"
        case .agent: "Agent"
        case .memo: "Memo"
        case .chart: "Chart"
        case .launch: "Launch"
        case .briefcase: "Business"
        case .globe: "Web"
        case .link: "Links"
        case .lock: "Private"
        case .shield: "Proof"
        case .sparkles: "AI"
        case .bolt: "Fast"
        case .book: "Knowledge"
        case .database: "Data"
        case .server: "Server"
        case .cloud: "Cloud"
        case .terminalWindow: "Terminal"
        case .pullRequest: "Pull Request"
        case .branch: "Branch"
        case .hammer: "Build"
        case .wrench: "Tools"
        case .flask: "Experiment"
        case .brain: "Thinking"
        case .eye: "Review"
        case .people: "Team"
        case .calendar: "Plan"
        case .pin: "Pinned"
        case .archive: "Archive"
        }
    }

    func matches(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }
        return ([
            rawValue,
            label,
            symbolName
        ] + searchAliases)
            .contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
    }

    private var searchAliases: [String] {
        switch self {
        case .shield:
            return ["verified", "attested", "trust"]
        default:
            return []
        }
    }
}

struct ChatProject: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var createdAt: Date
    var archivedAt: Date?
    var conversationIDs: [String]
    var attachments: [ChatAttachment]
    var instructions: String
    var memorySummary: String
    var links: [ProjectLink]
    var notes: [ProjectNote]
    var iconName: String
    var paletteName: String

    init(
        id: String,
        name: String,
        createdAt: Date,
        archivedAt: Date? = nil,
        conversationIDs: [String],
        attachments: [ChatAttachment] = [],
        instructions: String = "",
        memorySummary: String = "",
        links: [ProjectLink] = [],
        notes: [ProjectNote] = [],
        iconName: String = ProjectIcon.folder.symbolName,
        paletteName: String = ProjectPalette.sky.rawValue
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.conversationIDs = conversationIDs
        self.attachments = attachments
        self.instructions = instructions
        self.memorySummary = memorySummary
        self.links = links
        self.notes = notes
        self.iconName = iconName
        self.paletteName = paletteName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case archivedAt
        case conversationIDs
        case attachments
        case instructions
        case memorySummary
        case links
        case notes
        case iconName
        case paletteName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        conversationIDs = try container.decode([String].self, forKey: .conversationIDs)
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        memorySummary = try container.decodeIfPresent(String.self, forKey: .memorySummary) ?? ""
        links = try container.decodeIfPresent([ProjectLink].self, forKey: .links) ?? []
        notes = try container.decodeIfPresent([ProjectNote].self, forKey: .notes) ?? []
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? ProjectIcon.folder.symbolName
        paletteName = try container.decodeIfPresent(String.self, forKey: .paletteName) ?? ProjectPalette.sky.rawValue
    }

    var projectIconName: String {
        if ProjectIcon.allCases.contains(where: { $0.symbolName == iconName }) {
            return iconName
        }
        if let icon = ProjectIcon(rawValue: iconName) {
            return icon.symbolName
        }
        return ProjectIcon.folder.symbolName
    }

    var projectPalette: ProjectPalette {
        ProjectPalette(rawValue: paletteName) ?? .sky
    }

    var tintColor: Color {
        projectPalette.tintColor
    }

    var tintBackgroundColor: Color {
        projectPalette.backgroundColor
    }

    var isArchived: Bool {
        archivedAt != nil
    }
}
