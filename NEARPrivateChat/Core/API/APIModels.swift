import Foundation
import SwiftUI

struct SubscriptionPlan: Decodable, Identifiable, Hashable {
    struct Limit: Decodable, Hashable {
        let max: Int?
    }

    let name: String
    let price: Double?
    let trialPeriodDays: Int?
    let monthlyTokens: Limit?
    let allowedModels: [String]?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case price
        case trialPeriodDays = "trial_period_days"
        case monthlyTokens = "monthly_tokens"
        case allowedModels = "allowed_models"
    }
}

struct SubscriptionInfo: Decodable, Identifiable, Hashable {
    let subscriptionID: String
    let plan: String
    let provider: String
    let status: String
    let currentPeriodEnd: String?
    let cancelAtPeriodEnd: Bool?

    var id: String { subscriptionID }

    enum CodingKeys: String, CodingKey {
        case subscriptionID = "subscription_id"
        case plan
        case provider
        case status
        case currentPeriodEnd = "current_period_end"
        case cancelAtPeriodEnd = "cancel_at_period_end"
    }
}

struct SubscriptionPlansResponse: Decodable {
    let plans: [SubscriptionPlan]
}

struct SubscriptionsResponse: Decodable {
    let subscriptions: [SubscriptionInfo]
}

struct BillingSnapshot: Hashable {
    var plans: [SubscriptionPlan]
    var subscriptions: [SubscriptionInfo]
    var fetchedAt: Date

    var activeSubscription: SubscriptionInfo? {
        subscriptions.first { $0.status.localizedCaseInsensitiveContains("active") } ?? subscriptions.first
    }

    var summary: String {
        if let activeSubscription {
            return "\(activeSubscription.plan) · \(activeSubscription.status)"
        }
        if plans.isEmpty {
            return "No plan data"
        }
        return "\(plans.count) available plans"
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case unauthenticated
    case invalidCallback
    case status(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The API URL is invalid."
        case .unauthenticated: "Sign in to chat about anything with the general assistant."
        case .invalidCallback: "The sign-in callback did not include an authorization code."
        case let .status(code, message): Self.displayStatusMessage(code: code, rawMessage: message)
        case .emptyResponse: "The server returned an empty response."
        }
    }

    private static func displayStatusMessage(code: Int, rawMessage: String) -> String {
        let fallback = code == 0 ? "The request failed." : "Request failed with status \(code)."
        let normalized = rawMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty else { return fallback }

        let lowercased = normalized.lowercased()
        let looksRaw = normalized.count > 240 ||
            lowercased.hasPrefix("<!doctype") ||
            lowercased.hasPrefix("<html") ||
            (normalized.hasPrefix("{") && normalized.hasSuffix("}")) ||
            lowercased.contains("traceback") ||
            lowercased.contains("stack trace")
        return looksRaw ? fallback : normalized
    }
}
