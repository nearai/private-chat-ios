import Foundation

/// Records the REAL outcome of recent route requests — HTTP status, the
/// server's own message, model, and time — so a failing private route can be
/// diagnosed instead of guessed at. The user-facing copy elsewhere translates
/// errors for readability; this keeps the raw truth for the diagnostics screen.
@MainActor
final class ConnectionDiagnostics: ObservableObject {
    struct Outcome: Equatable {
        let route: ChatRouteKind
        let modelID: String
        let succeeded: Bool
        /// HTTP status when the failure was an APIError.status; nil for
        /// transport errors (no response) or successes.
        let statusCode: Int?
        /// The server's own message (or the transport error description).
        let message: String
        /// True when the failure was an authentication failure (bad or expired
        /// session token) per `RouteHealthMonitor.isAuthFailure` — NOT any
        /// 401/403, which the backend also uses for rate limits.
        let wasAuthFailure: Bool
        let at: Date

        var statusLabel: String {
            if succeeded { return "OK" }
            if let statusCode { return "HTTP \(statusCode)" }
            return "No response"
        }
    }

    @Published private(set) var lastPrivateOutcome: Outcome?
    @Published private(set) var lastCloudOutcome: Outcome?
    @Published private(set) var lastAgentOutcome: Outcome?

    var now: () -> Date = Date.init

    func record(route: ChatRouteKind, modelID: String, error: Error) {
        // User cancellations are not route outcomes — recording them would put
        // a phantom failure on the raw-truth screen.
        if error is CancellationError { return }
        if let urlError = error as? URLError, urlError.code == .cancelled { return }
        let outcome = Outcome(
            route: route,
            modelID: modelID,
            succeeded: false,
            statusCode: Self.statusCode(from: error),
            message: Self.rawMessage(from: error),
            wasAuthFailure: RouteHealthMonitor.isAuthFailure(error),
            at: now()
        )
        store(outcome)
    }

    func recordSuccess(route: ChatRouteKind, modelID: String) {
        let outcome = Outcome(
            route: route,
            modelID: modelID,
            succeeded: true,
            statusCode: nil,
            message: "Succeeded",
            wasAuthFailure: false,
            at: now()
        )
        store(outcome)
    }

    func reset() {
        lastPrivateOutcome = nil
        lastCloudOutcome = nil
        lastAgentOutcome = nil
    }

    private func store(_ outcome: Outcome) {
        switch outcome.route {
        case .nearPrivate:
            lastPrivateOutcome = outcome
        case .nearCloud:
            lastCloudOutcome = outcome
        case .ironclawMobile, .ironclawHosted:
            lastAgentOutcome = outcome
        }
    }

    nonisolated static func statusCode(from error: Error) -> Int? {
        if case let APIError.status(code, _) = error { return code }
        return nil
    }

    nonisolated static func rawMessage(from error: Error) -> String {
        if case let APIError.status(code, message) = error {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "HTTP \(code) (no body)" : trimmed
        }
        if let urlError = error as? URLError {
            return "\(urlError.code.rawValue): \(urlError.localizedDescription)"
        }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    /// True when private failed with an AUTH failure and cloud isn't also
    /// broken — the signature of a private-session problem. A plain 403 rate
    /// limit must not trip this: the remedy is to wait, not to sign back in.
    var privateLooksUnauthenticated: Bool {
        guard let lastPrivateOutcome,
              !lastPrivateOutcome.succeeded,
              lastPrivateOutcome.wasAuthFailure else { return false }
        // If cloud succeeded recently, the network and account are fine —
        // it's the private session specifically.
        return lastCloudOutcome?.succeeded == true || lastCloudOutcome == nil
    }

    /// The private route accepted the session for profile/conversation work but
    /// rejected inference with rate-limit-class wording. Retry remains the
    /// first recovery; if it persists, a fresh private session is the next
    /// honest action before sending the turn through Cloud.
    var privateLooksSessionRateLimited: Bool {
        guard let lastPrivateOutcome,
              !lastPrivateOutcome.succeeded,
              lastPrivateOutcome.route == .nearPrivate,
              !lastPrivateOutcome.wasAuthFailure else {
            return false
        }
        let message = lastPrivateOutcome.message.lowercased()
        return [403, 429].contains(lastPrivateOutcome.statusCode) &&
            (
                message.contains("temporarily restricted") ||
                message.contains("access temporarily restricted") ||
                message.contains("too many requests") ||
                message.contains("rate limit") ||
                message.contains("private route is rate-limited") ||
                message.contains("rate-limited for this session")
            )
    }
}
