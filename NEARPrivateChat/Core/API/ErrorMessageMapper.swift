import Foundation

enum ErrorMessageMapper {
    /// Maps transport-layer URLErrors to user copy before any string matching,
    /// so raw NSURLErrorDomain dumps never surface in chat or account banners.
    static func transportFailureMessage(_ urlError: URLError) -> String? {
        switch urlError.code {
        case .networkConnectionLost:
            return "Connection dropped mid-answer — retry. Your prompt is kept."
        case .timedOut:
            return "The model took too long to respond — retry, or switch models."
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return "You're offline. Reconnect, then retry."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Can't reach the private backend right now — retry in a moment."
        case .secureConnectionFailed, .serverCertificateUntrusted:
            return "Secure connection failed. Check your network, then retry."
        default:
            return nil
        }
    }

    static func displayFailureMessage(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if lowercased == "access denied" || lowercased.contains("\"access denied\"") {
            return "Access denied by the NEAR Private API. Sign in again or choose another available model."
        }
        if lowercased.contains("temporarily restricted") ||
            lowercased.contains("access temporarily restricted") ||
            lowercased.contains("rate-limited") ||
            lowercased.contains("rate limit") ||
            lowercased.contains("too many requests") ||
            lowercased.contains("retrying automatically") {
            return "Private route is rate-limited for this session. Retry private; if it keeps failing, sign out and back in. Use the privacy proxy only for this turn."
        }
        if lowercased.contains("the private route is temporarily busy") ||
            lowercased.contains("the private route is busy") ||
            lowercased.contains("private route is busy") {
            return "Private route is busy right now. Retry private in a moment, or use the privacy proxy only for this turn."
        }
        if lowercased.contains("-1005") || lowercased.contains("network connection was lost") {
            return "Connection dropped mid-answer — retry. Your prompt is kept."
        }
        if lowercased.contains("-1001") || lowercased.contains("request timed out") {
            return "The model took too long to respond — retry, or switch models."
        }
        if lowercased.contains("-1009") || lowercased.contains("not connected to the internet") || lowercased.contains("appears to be offline") {
            return "You're offline. Reconnect, then retry."
        }
        if lowercased.contains("response stream ended early") {
            return "The answer stream was interrupted — retry to continue."
        }
        if lowercased.contains("402") ||
            lowercased.contains("payment required") ||
            (lowercased.contains("billing") && lowercased.contains("required")) ||
            lowercased.contains("insufficient credits") ||
            lowercased.contains("budget exceeded") {
            return "Payment or credits required. Open Account, refresh Billing, then retry with an active plan or budget."
        }
        if lowercased.contains("chat route needs a valid ironclaw token") {
            return "Hosted IronClaw is reachable. The Agent token is missing or invalid. Open Account and test the Agent connection."
        }
        if lowercased.contains("missing authorization header") ||
            lowercased.contains("missing bearer") ||
            lowercased.contains("missing token") ||
            lowercased.contains("no authorization") ||
            lowercased.contains("invalid or expired authentication token") ||
            lowercased.contains("invalid token") ||
            lowercased.contains("expired token") ||
            lowercased.contains("invalid session token") ||
            lowercased.contains("expired session token") ||
            lowercased.contains("session token missing") ||
            lowercased.contains("token rejected") {
            return "Authentication is missing or expired. Sign in again, then retry."
        }
        if lowercased.contains("failed to check rate limit") {
            return "Could not verify account usage before sending. Refresh Account or sign in again, then retry."
        }
        if lowercased.contains("tool 'http' failed") &&
            lowercased.contains("request returned redirect") &&
            lowercased.contains("blocked to prevent ssrf") {
            return "IronClaw's web fetch tool hit a redirect and blocked it as an SSRF precaution. Upgrade or restart Hosted IronClaw 0.28.2 or newer, then retry."
        }
        if lowercased.contains("tool error") || lowercased.contains("tool '") || lowercased.contains("tool \"") {
            return "IronClaw tool failed before producing an answer: \(trimmed)"
        }
        if lowercased.contains("not available in your plan") {
            return "\(trimmed) Choose an allowed plan model from the picker or refresh Billing in Account."
        }
        if lowercased.contains("not authenticated") || lowercased.contains("unauthorized") {
            return "Sign in to start chatting."
        }
        return trimmed.isEmpty ? "The request failed." : trimmed
    }
}
