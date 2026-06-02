import SwiftUI

extension HomeScreen {
    var homePromptCaptureCard: some View {
        HomePromptCaptureCard(
            subtitle: homeLaunchSubtitle,
            draft: $homeStore.homeLaunchDraft,
            suggestions: homeLaunchSuggestions,
            selectedSuggestionID: homeStore.selectedHomeLaunchSuggestionID,
            selectedProjectName: chatStore.selectedProject?.name,
            actionTitle: homeLaunchActionTitle,
            actionSymbolName: homeLaunchActionSymbolName,
            actionEnabled: homeLaunchActionEnabled,
            onSelectSuggestion: toggleHomeLaunchSuggestion,
            onSubmit: runHomeLaunchPrompt
        )
    }


}
