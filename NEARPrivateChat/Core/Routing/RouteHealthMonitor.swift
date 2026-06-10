import Foundation
import SwiftUI

/// Error thrown by send pipelines when a route's circuit breaker is open —
/// the request is refused locally instead of burning a doomed network call.
enum RouteHealthError: LocalizedError {
    case routeRestricted(String)

    var errorDescription: String? {
        switch self {
        case let .routeRestricted(notice):
            return notice
        }
    }
}

/// Per-route circuit breaker. The backend rate-limits routes per account
/// ("Access temporarily restricted"); without a breaker the app amplifies the
/// restriction — fallback chains, council legs, tracker retries, and follow-ups
/// all hammer the restricted route and keep it restricted. The breaker observes
/// restricted-class failures, opens for an exponential cooldown, and lets a
/// single probe through when the window expires.
///
/// Deliberately narrow: plan errors, timeouts, and dropped connections do NOT
/// trip it — those are transient or model-specific, and tripping on them would
/// wrongly block the whole route.
@MainActor
final class RouteHealthMonitor: ObservableObject {
    struct RouteStatus: Equatable {
        enum Phase: Equatable {
            case healthy
            case restricted(until: Date)
        }

        var phase: Phase = .healthy
        var lastRestrictedAt: Date?
        var consecutiveRestrictions: Int = 0
        var lastFailureSummary: String?
    }

    @Published private(set) var statusByRoute: [ChatRouteKind: RouteStatus] = [:]

    /// Injectable clock so tests and the harness control cooldown expiry.
    var now: () -> Date = Date.init

    static let baseCooldown: TimeInterval = 60
    static let maxCooldown: TimeInterval = 600

    #if DEBUG
    /// Harness hook: NEAR_DEBUG_FORCE_RESTRICTED_ROUTES="nearPrivate,nearCloud"
    /// forces routes to read as restricted without any network traffic.
    var debugForcedRestrictedRoutes: Set<ChatRouteKind> = {
        guard let raw = ProcessInfo.processInfo.environment["NEAR_DEBUG_FORCE_RESTRICTED_ROUTES"] else {
            return []
        }
        return Set(raw.split(separator: ",").compactMap {
            ChatRouteKind(rawValue: $0.trimmingCharacters(in: .whitespaces))
        })
    }()
    #endif

    func recordSuccess(modelID: String) {
        let route = RoutePlanner.routeKind(forModelID: modelID)
        guard statusByRoute[route] != nil else { return }
        statusByRoute[route] = RouteStatus()
    }

    func recordFailure(modelID: String, error: Error) {
        guard Self.isRestrictedClassError(error) else { return }
        let route = RoutePlanner.routeKind(forModelID: modelID)
        var status = statusByRoute[route] ?? RouteStatus()
        status.consecutiveRestrictions += 1
        status.lastRestrictedAt = now()
        let cooldown = min(
            Self.baseCooldown * pow(2, Double(max(0, status.consecutiveRestrictions - 1))),
            Self.maxCooldown
        )
        status.phase = .restricted(until: now().addingTimeInterval(cooldown))
        status.lastFailureSummary = (error as? LocalizedError)?.errorDescription
        statusByRoute[route] = status
    }

    func isTripped(_ route: ChatRouteKind) -> Bool {
        #if DEBUG
        if debugForcedRestrictedRoutes.contains(route) { return true }
        #endif
        guard case let .restricted(until) = statusByRoute[route]?.phase else { return false }
        return until > now()
    }

    func shouldAttempt(modelID: String) -> Bool {
        !isTripped(RoutePlanner.routeKind(forModelID: modelID))
    }

    /// User copy for a tripped route, with remaining cooldown.
    func restrictionNotice(for route: ChatRouteKind) -> String? {
        guard isTripped(route) else { return nil }
        var remaining = 0
        if case let .restricted(until) = statusByRoute[route]?.phase {
            remaining = max(0, Int(until.timeIntervalSince(now()).rounded(.up)))
        }
        switch route {
        case .nearPrivate:
            if remaining > 0 {
                return "The private route is temporarily busy — retrying automatically in about \(remaining)s. Use the privacy proxy for this turn, or try private again from the route chip."
            }
            return "The private route is temporarily busy. Use the privacy proxy for this turn, or retry private in a moment."
        default:
            return "This route is temporarily busy. Try again in a moment."
        }
    }

    /// Manual "Try private now" — clears the cooldown so the next send probes.
    func resetRoute(_ route: ChatRouteKind) {
        statusByRoute[route] = RouteStatus()
    }

    func resetAll() {
        statusByRoute = [:]
    }

    /// Narrower than the recoverable-error matcher on purpose: only failures
    /// that indicate the ROUTE (not one model or one request) is rejecting the
    /// account should open the breaker.
    nonisolated static func isRestrictedClassError(_ error: Error) -> Bool {
        if case APIError.status(403, _) = error { return true }
        let message = ((error as? LocalizedError)?.errorDescription ?? String(describing: error)).lowercased()
        return message.contains("temporarily restricted") ||
            message.contains("temporarily busy") ||
            message.contains("access denied")
    }
}
