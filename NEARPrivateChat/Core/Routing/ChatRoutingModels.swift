import Foundation
import SwiftUI

struct ChatPromptSourcePrivacyOverride: Equatable {
    var blocksWeb: Bool = false
    var prefersFileOnly: Bool = false
    var requiresPrivateRoute: Bool = false

    var isEmpty: Bool {
        !blocksWeb && !prefersFileOnly && !requiresPrivateRoute
    }

    func sourceInstruction(attachmentNames: [String]) -> String? {
        guard blocksWeb || prefersFileOnly || requiresPrivateRoute else { return nil }
        let names = attachmentNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if prefersFileOnly {
            let source = names.isEmpty
                ? "Use only the attached or selected file context already present in this turn."
                : "Use only these attached files: \(names.joined(separator: ", "))."
            return "\(source) Do not browse, use live web, pull saved links, or add unstated project context."
        }
        if blocksWeb {
            return "Do not browse or use live web. Use the conversation, attached files, and selected project sources already present."
        }
        if requiresPrivateRoute {
            return "Keep this turn on the private route; do not hand it to hosted or cloud routes."
        }
        return nil
    }
}

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
        case .all: "Web + Files"
        }
    }

    var shortTitle: String {
        switch self {
        case .auto: "Auto"
        case .web: "Web"
        case .links: "Links"
        case .files: "Files"
        case .all: "Web + Files"
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
        case .web: "Use live web and prompt attachments."
        case .links: "Use saved source links."
        case .files: "Use project and prompt files."
        case .all: "Use live web, project files, saved links, and prompt attachments."
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

    var disclosureTitle: String {
        switch self {
        case .nearPrivate:
            return "NEAR Private"
        case .nearCloud:
            return "NEAR AI Cloud"
        case .ironclawMobile:
            return "IronClaw Mobile"
        case .ironclawHosted:
            return "Hosted IronClaw"
        }
    }

    var disclosureBadge: String {
        switch self {
        case .nearPrivate:
            return "Proof when fetched"
        case .nearCloud:
            return "External API · outside proof"
        case .ironclawMobile:
            return "IronClaw Mobile · outside proof"
        case .ironclawHosted:
            return "Agent connection"
        }
    }

    var disclosureSymbolName: String {
        switch self {
        case .nearPrivate:
            return "lock.shield"
        case .nearCloud:
            return "cloud"
        case .ironclawMobile:
            return "iphone"
        case .ironclawHosted:
            return "terminal"
        }
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
        let appGroundingPolicy = appGroundingPolicy(
            for: focus,
            webSearchEnabled: webSearchEnabled,
            route: route
        )
        let supportsNativeWebTool = route == .nearPrivate || route == .ironclawMobile
        let supportsAppGrounding = route == .nearPrivate || route == .nearCloud || route == .ironclawMobile || route == .ironclawHosted

        return ChatSourceRoutingSemantics(
            route: route,
            focus: focus,
            modelNativeWebToolPolicy: supportsNativeWebTool ? sourceWebPolicy : .never,
            appWebGroundingPolicy: supportsAppGrounding ? appGroundingPolicy : .never,
            attachesSavedLinkSourcePack: focus == .auto || focus == .links || focus == .project || focus == .research,
            attachesProjectFileSourcePack: focus == .auto || focus == .files || focus == .project || focus == .research,
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

    private static func appGroundingPolicy(
        for focus: ChatFocusState,
        webSearchEnabled: Bool,
        route: ChatRouteKind
    ) -> ChatWebUsePolicy {
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
            if route == .nearCloud {
                return webSearchEnabled ? .whenHelpful : .whenFreshRequested
            }
            return webSearchEnabled ? .whenHelpful : .never
        }
    }
}

enum ChatWebGroundingDecision {
    static func shouldEnableNativeWebTool(
        semantics: ChatSourceRoutingSemantics,
        benefitsFromSearch: Bool,
        needsFreshFacts: Bool,
        privacyBlocksWeb: Bool,
        appWebContextPresent: Bool = false
    ) -> Bool {
        guard !privacyBlocksWeb, !appWebContextPresent else { return false }
        return semantics.modelNativeWebToolPolicy.resolves(
            benefitsFromSearch: benefitsFromSearch,
            needsFreshFacts: needsFreshFacts
        )
    }

    static func shouldUseAppGrounding(
        route: ChatRouteKind,
        semantics: ChatSourceRoutingSemantics,
        benefitsFromSearch: Bool,
        needsFreshFacts: Bool,
        privacyBlocksWeb: Bool,
        promptNeedsRemoteWorkstation: Bool
    ) -> Bool {
        guard !privacyBlocksWeb else { return false }
        guard semantics.appWebGroundingPolicy != .never else { return false }
        if route == .ironclawMobile,
           semantics.modelNativeWebToolPolicy == .always,
           shouldEnableNativeWebTool(
                semantics: semantics,
                benefitsFromSearch: benefitsFromSearch,
                needsFreshFacts: needsFreshFacts,
                privacyBlocksWeb: privacyBlocksWeb
           ) {
            return false
        }
        if route == .ironclawHosted, promptNeedsRemoteWorkstation, !needsFreshFacts {
            return false
        }
        return semantics.appWebGroundingPolicy.resolves(
            benefitsFromSearch: benefitsFromSearch,
            needsFreshFacts: needsFreshFacts
        )
    }
}
