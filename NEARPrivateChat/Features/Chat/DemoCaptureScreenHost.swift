import SwiftUI

#if DEBUG
struct DemoCaptureScreenHost: View {
    @EnvironmentObject private var chatStore: ChatStore
    let screen: DemoCaptureScreen

    var body: some View {
        Group {
            switch screen {
            case .onboarding:
                DemoOnboardingPreviewView()
            case .login:
                DemoMockLoginView()
            case .home:
                AppShellView()
            case .fileAttach:
                DemoFileAttachmentFlowView()
            case .glmResult:
                DemoPrivateAnswerView()
            case .councilOutput:
                DemoCouncilComparisonView()
            case .chat, .composer, .widgets, .generativeChat, .chatStarters, .councilBriefingLive, .chatFailure:
                NavigationStack {
                    ChatView()
                        .navigationTitle(chatStore.selectedConversationTitle)
                        .platformInlineNavigationTitle()
                }
            case .briefingBuilder:
                BriefingEditorSheet()
            case .dashboard:
                DashboardScreen(
                    store: demoDashboardStore(),
                    onOpenBriefing: { _ in },
                    onNewBriefing: {},
                    onAsk: { _ in },
                    onClose: {}
                )
            case .ironclaw:
                DemoIronClawResultView()
            case .ironclawThinking:
                DemoIronClawThinkingView()
            case .agent:
                DemoIronClawModesView()
            case .verification:
                SecurityView()
            case .models:
                ModelPickerView()
            case .cloudModels:
                DemoNearCloudModelsView()
            case .council:
                ModelPickerView(openingCouncil: true)
            case .councilRoom:
                CouncilRoomView(
                    model: demoCouncilRoomModel(),
                    supportsTargetedSend: true,
                    synthesizeTitle: "Synthesize again",
                    onSend: { _, _ in },
                    onSynthesize: {}
                )
            case .threaded:
                ThreadedBriefingView(
                    title: "Daily briefing",
                    schedule: "Every weekday · 8:00am",
                    deliveries: ThreadedBriefingView.demoDeliveries
                )
            case .markdownGallery:
                DemoMarkdownGalleryView()
            case .trackerFailure:
                // Failure-state QA surface: a tracker whose run failed must show
                // the reason and a Run again affordance, never "No delivery yet".
                let context = demoFailedTrackerContext()
                ThreadedBriefingView(briefing: context.briefing, store: context.store)
            case .liveData:
                LiveDataDemoView()
            case .project:
                ProjectFilesView(
                    projectContextRoutePreview: { chatStore.projectContextRoutePreview },
                    addProjectAttachment: { url in await chatStore.addProjectAttachment(from: url) },
                    removeProjectAttachment: { attachment in chatStore.removeProjectAttachment(attachment) },
                    onOpenConversation: { conversation in
                        chatStore.selectConversation(conversation)
                    },
                    onStagePrompt: { prompt in
                        chatStore.draft = prompt
                        chatStore.bannerMessage = "Project prompt ready."
                    }
                )
            case .share:
                if let conversation = chatStore.selectedConversation {
                    ShareConversationView(conversation: conversation, transcriptStore: chatStore.transcriptStore)
                } else {
                    AppShellView()
                }
            }
        }
        .tint(.actionPrimary)
    }
}
#endif
