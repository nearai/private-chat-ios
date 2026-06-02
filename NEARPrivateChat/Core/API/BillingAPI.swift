import Foundation

protocol BillingAPI: AnyObject {
    func fetchSubscriptionPlans() async throws -> [SubscriptionPlan]
    func fetchSubscriptions(includeInactive: Bool) async throws -> [SubscriptionInfo]
}

final class PrivateChatBillingAPI: BillingAPI {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchSubscriptionPlans() async throws -> [SubscriptionPlan] {
        let response: SubscriptionPlansResponse = try await client.request("/v1/subscriptions/plans", method: "GET", authenticated: false)
        return response.plans
    }

    func fetchSubscriptions(includeInactive: Bool = false) async throws -> [SubscriptionInfo] {
        let suffix = includeInactive ? "?include_inactive=true" : ""
        let response: SubscriptionsResponse = try await client.request("/v1/subscriptions\(suffix)", method: "GET", authenticated: true)
        return response.subscriptions
    }
}
