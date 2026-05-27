import Foundation
import SwiftUI

struct AppConfiguration {
    var baseURL: URL
    var callbackScheme: String
    var callbackURL: URL

    static let production = AppConfiguration(
        baseURL: URL(string: "https://private.near.ai")!,
        callbackScheme: "nearprivatechat",
        callbackURL: URL(string: "nearprivatechat://auth")!
    )
}

struct AppDeepLinkAction: Equatable {
    static let maxDraftCharacters = 2_000

    enum Route: String, Equatable {
        case ask
        case agent
        case verified
    }

    var route: Route
    var sourceMode: ChatSourceMode?
    var researchMode: Bool
    var draft: String?

    static func parse(_ url: URL, callbackScheme: String = AppConfiguration.production.callbackScheme) -> AppDeepLinkAction? {
        guard url.scheme == callbackScheme,
              url.host?.lowercased() != "auth" else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") }
        )
        let command = normalizedCommand(from: url)
        let route = route(from: query["route"] ?? query["mode"] ?? command)

        guard command == "new" ||
              command == "ask" ||
              command == "agent" ||
              command == "ironclaw" ||
              command == "verified" ||
              command == "private" ||
              command == "chat" ||
              route != nil else {
            return nil
        }

        return AppDeepLinkAction(
            route: route ?? .ask,
            sourceMode: query["source"].flatMap(ChatSourceMode.init(rawValue:)),
            researchMode: boolValue(query["research"]),
            draft: cappedDraft(query["prompt"] ?? query["draft"])
        )
    }

    private static func normalizedCommand(from url: URL) -> String {
        let host = url.host?.lowercased()
        let firstPathComponent = url.pathComponents
            .first(where: { $0 != "/" })?
            .lowercased()

        if host == "chat", firstPathComponent == "new" {
            return "new"
        }
        return host ?? firstPathComponent ?? ""
    }

    private static func route(from value: String?) -> Route? {
        switch value?.lowercased() {
        case "agent", "ironclaw", "mobile", "workstation":
            return .agent
        case "verified", "private", "tee", "near-private":
            return .verified
        case "ask", "chat", "new":
            return .ask
        default:
            return nil
        }
    }

    private static func boolValue(_ value: String?) -> Bool {
        switch value?.lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cappedDraft(_ value: String?) -> String? {
        guard let draft = nonEmpty(value) else { return nil }
        return String(draft.prefix(maxDraftCharacters))
    }
}
