import SwiftUI

extension HomeScreen {
    func openNewChat() {
        chatStore.startNewConversation()
        onStartNewChat()
    }

    func startPrivateChatFromFirstRun() {

        if let accountID = sessionStore.setupAccountID,
           UserSetupStorage.needsFirstRunSetup(for: accountID) {
            let profile = chatStore.setupProfileSnapshot(
                UserSetupStorage.completeFirstRunPrivateChat(for: accountID)
            )
            UserSetupStorage.saveWithoutPendingLaunchCard(profile, for: accountID)
            chatStore.applySetupProfile(profile)
        }

        AppHaptics.selection()
        chatStore.startNewConversation()
        onStartNewChat()
    }

    func startQuickStartFromFirstRun(_ preset: UserSetupStarterPreset) {

        let profile: UserSetupProfile
        if let accountID = sessionStore.setupAccountID,
           UserSetupStorage.needsFirstRunSetup(for: accountID) {
            profile = chatStore.setupProfileSnapshot(
                UserSetupStorage.completeFirstRunQuickStart(for: accountID, preset: preset)
            )
            UserSetupStorage.saveWithoutPendingLaunchCard(profile, for: accountID)
        } else {
            profile = chatStore.setupProfileSnapshot(preset.quickStartProfile)
        }

        chatStore.applySetupProfile(profile)

        if profile.firstRunDraft == nil {
            AppHaptics.selection()
            chatStore.startNewConversation()
            chatStore.draft = preset.prompt
            chatStore.bannerMessage = "Starter prompt ready."
            onStartNewChat()
        }
    }

    func openConversation(_ conversation: ConversationSummary) {
        chatStore.selectConversation(conversation)
        onOpenChat()
    }

    func runHomeOrchestrationAction(_ action: HomeOrchestrationAction) {
        switch action {
        case .openBriefing(let briefingID):
            homeStore.openedBriefing = briefingStore.briefings.first { $0.id == briefingID }
        case .openProject(let projectID):
            guard let project = projectStore.visibleProjects.first(where: { $0.id == projectID }) else { return }
            openProjectContext(project)
        case .openConversation(let conversationID):
            guard let conversation = conversationStore.allVisibleConversations.first(where: { $0.id == conversationID }) else { return }
            openConversation(conversation)
        case .openAgentSettings:
            AppHaptics.lightImpact()
            openAccountSettings(deepLink: .ironclawAgent)
        case .editCouncilLineup:
            AppHaptics.selection()
            homeStore.showingHomeCouncilPicker = true
            chatStore.bannerMessage = "Add at least two models to run Council."
        case .useAutoCouncil:
            AppHaptics.selection()
            chatStore.useDefaultCouncilLineup()
        case .newBriefing:
            AppHaptics.selection()
            homeStore.showingNewBriefing = true
        case .runSetupDefaults:
            AppHaptics.lightImpact()
            onRunSetupAgain()
        case .stagePrompt(let stagedPrompt):
            stageHomeOrchestrationPrompt(stagedPrompt)
        }
    }

    func stageHomeOrchestrationPrompt(_ stagedPrompt: HomeStagedPrompt) {

        if let projectID = stagedPrompt.projectID,
           let project = projectStore.visibleProjects.first(where: { $0.id == projectID }) {
            chatStore.selectProject(project)
        }

        let launchDraft = homeStore.homeLaunchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        chatStore.startNewConversation()
        chatStore.draft = stagedPrompt.resolvedPrompt(existingDraft: launchDraft)
        if !launchDraft.isEmpty {
            homeStore.clearLaunchComposer()
        }
        chatStore.bannerMessage = stagedPrompt.banner
        AppHaptics.selection()
        onStartNewChat()
    }

    func stageProjectPrompt(_ prompt: String) {

        chatStore.startNewConversation()
        chatStore.draft = prompt
        chatStore.bannerMessage = "Project prompt ready."
        AppHaptics.selection()
        onStartNewChat()
    }


}
