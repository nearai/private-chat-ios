import Foundation

enum UserSetupUseCase: String, CaseIterable, Codable, Identifiable, Hashable {
    case privateChat
    case research
    case buildAgents
    case teamProjects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateChat: "Ask privately"
        case .research: "Research with sources"
        case .buildAgents: "Run an Agent"
        case .teamProjects: "Work in a Project"
        }
    }

    var subtitle: String {
        switch self {
        case .privateChat: "Fast private answers, web only when useful."
        case .research: "Current sources, citations, and saveable memos."
        case .buildAgents: "Plan code, PR, and test work from Project context."
        case .teamProjects: "Files, links, notes, and shared context."
        }
    }

    var symbolName: String {
        switch self {
        case .privateChat: "lock.shield"
        case .research: "doc.text.magnifyingglass"
        case .buildAgents: "terminal"
        case .teamProjects: "folder.badge.gearshape"
        }
    }

    var starterProjectName: String? {
        switch self {
        case .privateChat:
            return nil
        case .research:
            return "Research Room"
        case .buildAgents:
            return "Build Project"
        case .teamProjects:
            return "Project Hub"
        }
    }

    var starterInstructions: String {
        switch self {
        case .privateChat:
            return "Keep answers direct, private, and practical. Use live web only when the question needs current facts."
        case .research:
            return "Prioritize dated sources, citations, contradictions, and a concise recommendation. Save strong outputs as Project notes."
        case .buildAgents:
            return "Use Project files, pull requests, issues, and source links to plan careful code work. Suggest destructive changes only when asked."
        case .teamProjects:
            return "Use Project files, saved links, notes, and outputs before broad web. Keep context tidy; ask only when a missing source blocks progress."
        }
    }

    var starterPrompt: String {
        switch self {
        case .privateChat:
            return "Think through the most important question to ask first."
        case .research:
            return "Write a sourced brief on the latest AI developments, with dates, citations, and a short recommendation."
        case .buildAgents:
            return "Plan the first repo task: what to inspect, what to change, and which focused tests should run."
        case .teamProjects:
            return "Set up this Project: what files, links, instructions, and first chat to add?"
        }
    }

    var workspaceSeed: SetupWorkspaceSeed? {
        switch self {
        case .privateChat:
            return nil
        case .research:
            return SetupWorkspaceSeed(
                title: "Research brief",
                detail: "Starter prompts ask for dated sources, contradictions, citations, and a concise recommendation.",
                symbolName: "doc.text.magnifyingglass"
            )
        case .buildAgents:
            return SetupWorkspaceSeed(
                title: "Repo plan",
                detail: "Starter prompts ask for a safe patch plan and focused verification before code changes.",
                symbolName: "terminal"
            )
        case .teamProjects:
            return SetupWorkspaceSeed(
                title: "Project memory",
                detail: "Links, files, notes, and reusable instructions stay together inside one active project.",
                symbolName: "folder.badge.gearshape"
            )
        }
    }

    var starterSkillIDs: [String] {
        switch self {
        case .privateChat:
            return []
        case .research:
            return ["llm-council", "plan-mode", "decision-capture"]
        case .buildAgents:
            return ["project-setup", "plan-mode", "developer-setup", "coding", "local-test", "review-readiness", "github-workflow"]
        case .teamProjects:
            return ["new-project", "project-setup", "decision-capture", "commitment-triage"]
        }
    }
}

extension Array where Element == UserSetupUseCase {
    var setupOrderedUnique: [UserSetupUseCase] {
        let selected = Set(self)
        let ordered = UserSetupUseCase.allCases.filter { selected.contains($0) }
        return ordered.isEmpty ? [.privateChat] : ordered
    }

    var setupPrimaryUseCase: UserSetupUseCase {
        let selected = Set(setupOrderedUnique)
        if selected.contains(.buildAgents) {
            return .buildAgents
        }
        if selected.contains(.research) {
            return .research
        }
        if selected.contains(.teamProjects) {
            return .teamProjects
        }
        return .privateChat
    }
}

enum UserSetupContextStyle: String, CaseIterable, Codable, Identifiable, Hashable {
    case simple
    case project
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: "Automatic"
        case .project: "Project context"
        case .files: "Files first"
        }
    }

    var subtitle: String {
        switch self {
        case .simple: "Use the chat, web, and saved context only when it helps."
        case .project: "Keep links, notes, instructions, and files together."
        case .files: "Prioritize attached and project files before anything else."
        }
    }

    var symbolName: String {
        switch self {
        case .simple: "sparkles"
        case .project: "folder"
        case .files: "paperclip"
        }
    }

    var sourceMode: ChatSourceMode {
        switch self {
        case .simple: .auto
        case .project: .all
        case .files: .files
        }
    }

    init(sourceMode: ChatSourceMode) {
        switch sourceMode {
        case .files:
            self = .files
        case .all, .links:
            self = .project
        case .auto, .web:
            self = .simple
        }
    }
}

enum UserSetupExperienceMode: String, CaseIterable, Codable, Identifiable, Hashable {
    case beginner
    case power

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner: "Beginner"
        case .power: "Power"
        }
    }

    var subtitle: String {
        switch self {
        case .beginner: "Start with private chat, sources, and proof. Other capabilities stay available later."
        case .power: "Show agents, Council, Cloud models, and developer controls from day one."
        }
    }

    var symbolName: String {
        switch self {
        case .beginner: "sparkles"
        case .power: "bolt"
        }
    }
}
