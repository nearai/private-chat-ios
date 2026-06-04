import SwiftUI

import SwiftUI

enum HomeOrchestrationFilter: String, CaseIterable, Identifiable {
    case all
    case streams
    case agents
    case projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .streams:
            return "Workflows"
        case .agents:
            return "Agents"
        case .projects:
            return "Projects"
        }
    }

    var symbolName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .streams:
            return "calendar.badge.clock"
        case .agents:
            return "sparkles"
        case .projects:
            return "folder"
        }
    }
}

enum HomeOrchestrationTone: Equatable {
    case blue
    case green
    case amber
    case red
    case violet
    case neutral

    var tintColor: Color {
        switch self {
        case .blue:
            return Color.brandBlue
        case .green:
            return Color.proofVerified
        case .amber:
            return Color.proofStale
        case .red:
            return Color.proofMismatch
        case .violet:
            return Color.purple
        case .neutral:
            return Color.textSecondary
        }
    }
}

enum HomeOrchestrationItemKind: String, Equatable {
    case briefing
    case council
    case agent
    case project
    case chat
    case setup

    var filter: HomeOrchestrationFilter {
        switch self {
        case .briefing:
            return .streams
        case .council, .agent, .setup:
            return .agents
        case .project:
            return .projects
        case .chat:
            return .all
        }
    }
}

struct HomeStagedPrompt: Equatable {
    let prompt: String
    let projectID: String?
    let banner: String

    init(prompt: String, projectID: String? = nil, banner: String = "Prompt ready.") {
        self.prompt = prompt
        self.projectID = projectID
        self.banner = banner
    }

    func resolvedPrompt(existingDraft: String) -> String {
        EmptyChatStarterCoordinator.stagedPrompt(prompt, existingDraft: existingDraft)
    }
}

enum HomeOrchestrationAction: Equatable {
    case openBriefing(UUID)
    case openProject(String)
    case openConversation(String)
    case openAgentSettings
    case useAutoCouncil
    case newBriefing
    case runSetupDefaults
    case stagePrompt(HomeStagedPrompt)
}

struct HomeOrchestrationCommand: Identifiable, Equatable {
    let id: String
    let title: String
    let symbolName: String
    let action: HomeOrchestrationAction
}

struct HomeOrchestrationItem: Identifiable, Equatable {
    let id: String
    let kind: HomeOrchestrationItemKind
    let title: String
    let subtitle: String
    let detail: String
    let statusText: String
    let symbolName: String
    let tone: HomeOrchestrationTone
    let action: HomeOrchestrationAction

    func matches(_ filter: HomeOrchestrationFilter) -> Bool {
        filter == .all || kind.filter == filter
    }
}

struct HomeOrchestrationScheduleItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
    let scheduleLabel: String
    let symbolName: String
    let tone: HomeOrchestrationTone
    let action: HomeOrchestrationAction
}

struct HomeOrchestrationPlan: Equatable {
    let subtitle: String
    let liveItems: [HomeOrchestrationItem]
    let scheduledItems: [HomeOrchestrationScheduleItem]
    let commands: [HomeOrchestrationCommand]

    var activeCount: Int { liveItems.count }
}
