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
        /// True when the most recent trip was an authentication failure (bad or
        /// expired session token) rather than a rate limit. An auth failure will
        /// NOT recover by waiting, so the notice must say "sign in" instead of
        /// "temporarily busy."
        var lastWasAuthFailure: Bool = false
        /// True when the most recent trip was an explicit quota/rate-limit
        /// signal rather than a merely busy route.
        var lastWasExplicitRateLimitFailure: Bool = false
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
        // Auth failures only trip the PRIVATE breaker. On cloud/agent routes a
        // 401 is a configuration problem (missing or stale key) thrown before
        // any network call — tripping would lock the route for 60s even after
        // the user fixes the key.
        if Self.isAuthFailure(error), route != .nearPrivate { return }
        var status = statusByRoute[route] ?? RouteStatus()
        status.consecutiveRestrictions += 1
        status.lastRestrictedAt = now()
        let cooldown = min(
            Self.baseCooldown * pow(2, Double(max(0, status.consecutiveRestrictions - 1))),
            Self.maxCooldown
        )
        status.phase = .restricted(until: now().addingTimeInterval(cooldown))
        status.lastFailureSummary = (error as? LocalizedError)?.errorDescription
        status.lastWasAuthFailure = Self.isAuthFailure(error)
        status.lastWasExplicitRateLimitFailure = Self.isExplicitRateLimitFailure(error)
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

    /// User copy for a tripped route.
    func restrictionNotice(for route: ChatRouteKind) -> String? {
        guard isTripped(route) else { return nil }
        // An auth failure won't recover by waiting — say so honestly instead of
        // implying a rate limit that clears on its own.
        if statusByRoute[route]?.lastWasAuthFailure == true {
            switch route {
            case .nearPrivate:
                return "Your private session isn't authenticated — the route rejected your session token. Sign out and sign back in. Use the privacy proxy for this turn if you need an answer now. See Connection diagnostics for the exact error."
            default:
                return "This route rejected your credentials. Reconnect it in Account."
            }
        }
        switch route {
        case .nearPrivate:
            if statusByRoute[route]?.lastWasExplicitRateLimitFailure == true {
                return "Private route is rate-limited for this session. Wait for the cooldown, or use the privacy proxy only for this turn. If it keeps failing after cooldown, sign out and back in."
            }
            return "Private route is busy right now. Retry private in a moment, or use the privacy proxy only for this turn."
        default:
            return "This route is temporarily busy. Try again in a moment."
        }
    }

    /// Manual "Try private now" — clears busy cooldowns so the next send probes.
    /// Explicit rate limits cannot be bypassed while active; hammering them
    /// can extend the backend bucket.
    @discardableResult
    func resetRoute(_ route: ChatRouteKind) -> Bool {
        if isTripped(route), statusByRoute[route]?.lastWasExplicitRateLimitFailure == true {
            return false
        }
        statusByRoute[route] = RouteStatus()
        return true
    }

    func resetAll() {
        statusByRoute = [:]
    }

    /// Narrower than the recoverable-error matcher on purpose: only failures
    /// that indicate the ROUTE (not one model or one request) is rejecting the
    /// account should open the breaker.
    nonisolated static func isRestrictedClassError(_ error: Error) -> Bool {
        // A 401 means the session token was rejected. Trip the breaker so the
        // app stops hammering an unauthenticated route on every send/foreground;
        // the notice copy distinguishes this from a rate limit.
        if case APIError.status(401, _) = error { return true }
        if case APIError.status(429, _) = error { return true }
        if case let APIError.status(403, message) = error {
            return isAuthFailure(error) || isRestrictedFailureMessage(message)
        }
        let message = ((error as? LocalizedError)?.errorDescription ?? String(describing: error)).lowercased()
        return isRestrictedFailureMessage(message)
    }

    /// A genuinely busy route can be worth one same-route retry before the
    /// breaker opens. Explicit rate limits should not retry automatically:
    /// another immediate request can extend or amplify the same limit bucket.
    nonisolated static func isTransientBusyFailure(_ error: Error) -> Bool {
        if case let APIError.status(503, message) = error {
            return !isAuthFailure(error) && !isExplicitRateLimitMessage(message)
        }
        return !isAuthFailure(error) && !isExplicitRateLimitFailure(error) && isBusyFailureMessage(errorMessage(error))
    }

    nonisolated static func isExplicitRateLimitFailure(_ error: Error) -> Bool {
        if case APIError.status(429, _) = error { return true }
        return isExplicitRateLimitMessage(errorMessage(error))
    }

    private nonisolated static func isRestrictedFailureMessage(_ message: String) -> Bool {
        isExplicitRateLimitMessage(message) || isBusyFailureMessage(message)
    }

    private nonisolated static func isExplicitRateLimitMessage(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("temporarily restricted") ||
            lowercased.contains("access temporarily restricted") ||
            lowercased.contains("rate-limited") ||
            lowercased.contains("rate limit") ||
            lowercased.contains("too many requests")
    }

    private nonisolated static func isBusyFailureMessage(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("temporarily busy") ||
            lowercased.contains("private route is busy") ||
            lowercased.contains("route is busy")
    }

    private nonisolated static func errorMessage(_ error: Error) -> String {
        if case let APIError.status(_, body) = error {
            return body
        }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    /// Distinguishes an authentication failure (bad/expired session token) from
    /// a rate limit. Both can arrive as 403; only the wording or a 401 tells
    /// them apart. Used to pick honest "sign in" copy over "temporarily busy."
    nonisolated static func isAuthFailure(_ error: Error) -> Bool {
        if case APIError.status(401, _) = error { return true }
        let message: String
        if case let APIError.status(_, body) = error {
            message = body.lowercased()
        } else {
            message = ((error as? LocalizedError)?.errorDescription ?? String(describing: error)).lowercased()
        }
        return message.contains("authorization header")
            || message.contains("missing bearer")
            || message.contains("missing token")
            || message.contains("invalid or expired")
            || message.contains("authentication token")
            || message.contains("unauthenticated")
            || message.contains("not authenticated")
            || message.contains("no authorization")
            || message.contains("invalid token")
            || message.contains("expired token")
            || message.contains("invalid session")
            || message.contains("expired session")
            || message.contains("session token missing")
            || message.contains("token rejected")
            // The private auth restrictionNotice gets re-wrapped as a 403 by
            // the agent pipeline's fail-fast path; match its copy so the
            // re-wrapped error still classifies as auth.
            || message.contains("isn't authenticated")
            || message.contains("rejected your session token")
    }
}
