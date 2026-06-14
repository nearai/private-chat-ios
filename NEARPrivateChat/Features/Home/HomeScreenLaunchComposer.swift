import SwiftUI

extension HomeScreen {
    var homePromptCaptureCard: some View {
        HomePromptCaptureCard(
            subtitle: homeLaunchSubtitle,
            draft: $homeStore.homeLaunchDraft,
            suggestions: homeLaunchSuggestions,
            selectedSuggestionID: homeStore.selectedHomeLaunchSuggestionID,
            selectedProjectName: chatStore.selectedProject?.name,
            routeTitle: chatStore.isCouncilModeEnabled ? "Council" : "Private route",
            routeDetail: homeLaunchRouteDetail,
            actionTitle: homeLaunchActionTitle,
            actionSymbolName: homeLaunchActionSymbolName,
            actionEnabled: homeLaunchActionEnabled,
            onSelectSuggestion: toggleHomeLaunchSuggestion,
            onSubmit: runHomeLaunchPrompt
        )
    }

    var homeLaunchRouteDetail: String {
        if chatStore.isCouncilModeEnabled {
            return chatStore.activeCouncilRouteSummary
        }
        if ChatStore.shouldDiscloseAutoLiveWeb(
            sourceMode: chatStore.sourceMode,
            researchModeEnabled: chatStore.researchModeEnabled,
            prompt: homeStore.homeLaunchDraft
        ) {
            return "\(chatStore.selectedModelDisplayName) · Web"
        }
        return chatStore.selectedModelDisplayName
    }

}
