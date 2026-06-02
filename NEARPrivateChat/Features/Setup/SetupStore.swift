import Combine
import Foundation

@MainActor
final class SetupStore: ObservableObject {
    @Published private(set) var profile: UserSetupProfile?
    @Published private(set) var isCompleted = false
    @Published private(set) var hasPendingLaunchCard = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for accountID: String, currentDefaults: UserSetupProfile = .defaults) {
        profile = UserSetupStorage.presentationProfile(
            for: accountID,
            currentDefaults: currentDefaults,
            defaults: defaults
        )
        isCompleted = UserSetupStorage.isCompleted(for: accountID, defaults: defaults)
        hasPendingLaunchCard = UserSetupStorage.hasPendingLaunchCard(for: accountID, defaults: defaults)
    }

    func save(_ profile: UserSetupProfile, for accountID: String) {
        UserSetupStorage.save(profile, for: accountID, defaults: defaults)
        load(for: accountID, currentDefaults: profile)
    }

    func saveWithoutPendingLaunchCard(_ profile: UserSetupProfile, for accountID: String) {
        UserSetupStorage.saveWithoutPendingLaunchCard(profile, for: accountID, defaults: defaults)
        load(for: accountID, currentDefaults: profile)
    }

    func clearPendingLaunchCard(for accountID: String) {
        UserSetupStorage.clearPendingLaunchCard(for: accountID, defaults: defaults)
        load(for: accountID, currentDefaults: profile ?? .defaults)
    }

    func needsFirstRunSetup(for accountID: String) -> Bool {
        UserSetupStorage.needsFirstRunSetup(for: accountID, defaults: defaults)
    }
}
