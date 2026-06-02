import SwiftUI

extension HomeScreen {
    func toggleHomeLaunchSuggestion(_ suggestion: EmptyChatStarterSuggestion) {
        AppHaptics.selection()
        homeStore.toggleLaunchSuggestion(suggestion)
    }

    func runHomeLaunchPrompt() {
        guard !chatStore.isStreaming else {
            chatStore.bannerMessage = "Finish or cancel the current response before staging a prompt."
            return
        }

        let trimmedDraft = homeStore.homeLaunchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestion = selectedHomeLaunchSuggestion
        guard suggestion != nil || !trimmedDraft.isEmpty else { return }

        if let suggestion {
            let readyToLaunch = EmptyChatStarterCoordinator.prepare(
                suggestion,
                to: chatStore,
                onOpenProject: {
                    queuePendingHomeLaunch(
                        suggestion: suggestion,
                        draft: trimmedDraft,
                        followUp: .project
                    )
                    homeStore.showingProjectFiles = true
                    chatStore.bannerMessage = "Choose a Project; the prompt will open in chat."
                },
                onOpenCouncil: {
                    queuePendingHomeLaunch(
                        suggestion: suggestion,
                        draft: trimmedDraft,
                        followUp: .council
                    )
                    homeStore.showingHomeCouncilPicker = true
                    chatStore.bannerMessage = "Adjust the Council lineup; the prompt will open in chat."
                }
            )
            guard readyToLaunch else { return }
        }

        commitHomeLaunchPrompt(
            prefix: suggestion?.prompt,
            draft: trimmedDraft,
            banner: suggestion.map { "\($0.title) prompt ready." } ?? "Prompt ready."
        )
    }

    func queuePendingHomeLaunch(
        suggestion: EmptyChatStarterSuggestion,
        draft: String,
        followUp: HomeLaunchFollowUp
    ) {
        homeStore.queuePendingLaunch(
            suggestion: suggestion,
            draft: draft,
            followUp: followUp
        )
    }

    func resumePendingHomeLaunchIfPossible(after followUp: HomeLaunchFollowUp) {
        guard homeStore.pendingHomeLaunchFollowUp == followUp,
              let suggestion = homeStore.pendingHomeLaunchSuggestion else {
            return
        }

        switch followUp {
        case .project:
            guard chatStore.selectedProject != nil else {
                clearPendingHomeLaunch()
                return
            }
        case .council:
            guard chatStore.isCouncilModeEnabled else {
                clearPendingHomeLaunch()
                return
            }
        }

        commitHomeLaunchPrompt(
            prefix: suggestion.prompt,
            draft: homeStore.pendingHomeLaunchDraft,
            banner: "\(suggestion.title) prompt ready."
        )
    }

    func commitHomeLaunchPrompt(prefix: String?, draft: String, banner: String) {
        chatStore.startNewConversation()
        chatStore.draft = EmptyChatStarterCoordinator.stagedPrompt(prefix ?? "", existingDraft: draft)
        chatStore.bannerMessage = banner
        homeStore.clearLaunchComposer()
        AppHaptics.selection()
        onStartNewChat()
    }

    func clearPendingHomeLaunch() {
        homeStore.clearPendingLaunch()
    }

    var filterCounts: [HomeFilter: Int] {
        homeInboxSectionPlan.filterCounts
    }

    func selectHomeFilter(_ filter: HomeFilter) {
        homeStore.selectHomeFilter(filter)
        if filter == .all {
            chatStore.selectAllChats()
        } else if filter == .shared, shareStore.sharedWithMe.isEmpty {
            Task {
                await shareStore.refreshSharedWithMe(showErrors: false)
            }
        }
    }

    func toggleSearch() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            homeStore.toggleSearch()
        }
    }


}
