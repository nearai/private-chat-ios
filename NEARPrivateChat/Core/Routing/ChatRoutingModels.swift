import Foundation
import SwiftUI

enum ChatSourceMode: String, CaseIterable, Codable, Identifiable, Hashable {
    case auto
    case web
    case links
    case files
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .web: "Web"
        case .links: "Links"
        case .files: "Files"
        case .all: "Project"
        }
    }

    var shortTitle: String {
        switch self {
        case .auto: "Auto"
        case .web: "Web"
        case .links: "Links"
        case .files: "Files"
        case .all: "Project"
        }
    }

    var symbolName: String {
        switch self {
        case .auto: "sparkles"
        case .web: "globe"
        case .links: "link"
        case .files: "folder"
        case .all: "rectangle.3.group"
        }
    }

    var detail: String {
        switch self {
        case .auto: "Use files and web when helpful."
        case .web: "Use live web first."
        case .links: "Use saved source links."
        case .files: "Use project and prompt files."
        case .all: "Use live sources, project files, and saved links."
        }
    }
}

enum ChatRouteKind: String, Hashable {
    case nearPrivate
    case nearCloud
    case ironclawMobile
    case ironclawHosted

    var isIronclawRoute: Bool {
        self == .ironclawMobile || self == .ironclawHosted
    }
}

enum ChatFocusState: String, Hashable {
    case auto
    case web
    case links
    case files
    case project
    case research
}

enum ChatWebUsePolicy: String, Hashable {
    case never
    case always
    case whenHelpful
    case whenFreshRequested

    var isEnabledByDefault: Bool {
        switch self {
        case .always, .whenHelpful:
            return true
        case .never, .whenFreshRequested:
            return false
        }
    }

    func resolves(benefitsFromSearch: Bool, needsFreshFacts: Bool) -> Bool {
        switch self {
        case .never:
            return false
        case .always:
            return true
        case .whenHelpful:
            return benefitsFromSearch || needsFreshFacts
        case .whenFreshRequested:
            return needsFreshFacts
        }
    }
}

struct ChatSourceRoutingSemantics: Hashable {
    let route: ChatRouteKind
    let focus: ChatFocusState
    let modelNativeWebToolPolicy: ChatWebUsePolicy
    let appWebGroundingPolicy: ChatWebUsePolicy
    let attachesSavedLinkSourcePack: Bool
    let attachesProjectFileSourcePack: Bool
    let attachesPromptFiles: Bool

    var isResearch: Bool {
        focus == .research
    }

    var modelNativeWebToolEnabledByDefault: Bool {
        modelNativeWebToolPolicy.isEnabledByDefault
    }

    static func evaluate(
        sourceMode: ChatSourceMode,
        researchModeEnabled: Bool,
        webSearchEnabled: Bool,
        route: ChatRouteKind
    ) -> ChatSourceRoutingSemantics {
        let focus: ChatFocusState = if researchModeEnabled {
            .research
        } else {
            switch sourceMode {
            case .auto: .auto
            case .web: .web
            case .links: .links
            case .files: .files
            case .all: .project
            }
        }
        let sourceWebPolicy = webPolicy(for: focus, webSearchEnabled: webSearchEnabled)
        let appGroundingPolicy = appGroundingPolicy(for: focus, webSearchEnabled: webSearchEnabled)
        let supportsNativeWebTool = route == .nearPrivate || route == .ironclawMobile
        let supportsAppGrounding = route == .nearCloud || route == .ironclawMobile || route == .ironclawHosted

        return ChatSourceRoutingSemantics(
            route: route,
            focus: focus,
            modelNativeWebToolPolicy: supportsNativeWebTool ? sourceWebPolicy : .never,
            appWebGroundingPolicy: supportsAppGrounding ? appGroundingPolicy : .never,
            attachesSavedLinkSourcePack: focus == .auto || focus == .web || focus == .links || focus == .project || focus == .research,
            attachesProjectFileSourcePack: focus == .auto || focus == .web || focus == .files || focus == .project || focus == .research,
            attachesPromptFiles: true
        )
    }

    private static func webPolicy(for focus: ChatFocusState, webSearchEnabled: Bool) -> ChatWebUsePolicy {
        switch focus {
        case .auto:
            return webSearchEnabled ? .whenHelpful : .whenFreshRequested
        case .web, .project, .research:
            return .always
        case .links:
            return .whenFreshRequested
        case .files:
            return .never
        }
    }

    private static func appGroundingPolicy(for focus: ChatFocusState, webSearchEnabled: Bool) -> ChatWebUsePolicy {
        switch focus {
        case .web, .research:
            return .always
        case .files:
            return .never
        case .project:
            return webSearchEnabled ? .whenHelpful : .never
        case .links:
            return webSearchEnabled ? .whenFreshRequested : .never
        case .auto:
            return webSearchEnabled ? .whenHelpful : .never
        }
    }
}
