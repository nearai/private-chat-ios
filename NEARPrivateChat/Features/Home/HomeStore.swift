import SwiftUI

@MainActor
final class HomeStore: ObservableObject {
    @Published var searchText = ""
    @Published var selectedHomeFilter: HomeFilter = .all
    @Published var selectedFeedScope: HomeFeedScope = .all
    @Published var showingNewProject = false
    @Published var showingProjectFiles = false
    @Published var showingAccountSettings = false
    @Published var accountSettingsDeepLink: AccountSettingsDeepLink?
    @Published var showingSecurity = false
    @Published var isSearchVisible = false
    @Published var editingProject: ChatProject?
    @Published var showingNewBriefing = false
    @Published var openedBriefing: Briefing?
    @Published var homeLaunchDraft = ""
    @Published var selectedHomeLaunchSuggestionID: String?
    @Published var pendingHomeLaunchSuggestion: EmptyChatStarterSuggestion?
    @Published var pendingHomeLaunchDraft = ""
    @Published var pendingHomeLaunchFollowUp: HomeLaunchFollowUp?
    @Published var showingHomeCouncilPicker = false

    var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resetDefaultFilter() {
        selectedHomeFilter = .all
        selectedFeedScope = .all
    }

    func toggleSearch() {
        isSearchVisible.toggle()
        if !isSearchVisible {
            searchText = ""
        }
    }

    func selectHomeFilter(_ filter: HomeFilter) {
        selectedHomeFilter = filter
    }

    func toggleLaunchSuggestion(_ suggestion: EmptyChatStarterSuggestion) {
        selectedHomeLaunchSuggestionID = selectedHomeLaunchSuggestionID == suggestion.id ? nil : suggestion.id
    }

    func queuePendingLaunch(
        suggestion: EmptyChatStarterSuggestion,
        draft: String,
        followUp: HomeLaunchFollowUp
    ) {
        pendingHomeLaunchSuggestion = suggestion
        pendingHomeLaunchDraft = draft
        pendingHomeLaunchFollowUp = followUp
    }

    func clearPendingLaunch() {
        pendingHomeLaunchSuggestion = nil
        pendingHomeLaunchDraft = ""
        pendingHomeLaunchFollowUp = nil
    }

    func clearLaunchComposer() {
        homeLaunchDraft = ""
        selectedHomeLaunchSuggestionID = nil
        clearPendingLaunch()
    }
}
