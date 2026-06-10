import SwiftUI

#if DEBUG
struct DemoCaptureRootView: View {
    @EnvironmentObject private var chatStore: ChatStore
    let screen: DemoCaptureScreen
    let autoPlay: Bool
    @State private var currentScreen: DemoCaptureScreen

    private let autoPlayScreens: [DemoCaptureScreen] = [
        .onboarding,
        .login,
        .home,
        .composer,
        .models,
        .glmResult,
        .verification,
        .council,
        .councilOutput,
        .project,
        .fileAttach,
        .agent,
        .ironclawThinking,
        .ironclaw,
        .share
    ]

    init(screen: DemoCaptureScreen, autoPlay: Bool) {
        self.screen = screen
        self.autoPlay = autoPlay
        _currentScreen = State(initialValue: screen)
    }

    var body: some View {
        DemoCaptureScreenHost(screen: currentScreen)
            .environmentObject(chatStore)
            .id(currentScreen.rawValue)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: currentScreen)
            .overlay {
                DemoSceneOverlay(screen: currentScreen)
                    .allowsHitTesting(false)
            }
            .task {
                guard autoPlay else { return }
                let delay = DemoCapture.autoPlayDelayNanoseconds
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                for screen in autoPlayScreens {
                    await MainActor.run {
                        currentScreen = screen
                        chatStore.prepareDemoCapture(screen: screen)
                    }
                    try? await Task.sleep(nanoseconds: duration(for: screen))
                }
            }
            .onAppear {
                chatStore.prepareDemoCapture(screen: currentScreen)
            }
    }

    private func duration(for screen: DemoCaptureScreen) -> UInt64 {
        switch screen {
        case .onboarding:
            return 2_000_000_000
        case .login:
            return 5_000_000_000
        case .home:
            return 4_000_000_000
        case .fileAttach:
            return 9_000_000_000
        case .glmResult:
            return 14_000_000_000
        case .chat, .widgets:
            return 3_500_000_000
        case .councilOutput:
            return 12_000_000_000
        case .verification:
            return 7_000_000_000
        case .cloudModels:
            return 4_000_000_000
        case .models:
            return 4_000_000_000
        case .council, .councilRoom, .threaded, .liveData:
            return 6_000_000_000
        case .generativeChat:
            return 8_000_000_000
        case .chatStarters:
            return 4_000_000_000
        case .chatFailure, .trackerFailure, .markdownGallery:
            return 4_000_000_000
        case .briefingBuilder:
            return 4_000_000_000
        case .councilBriefingLive:
            return 4_000_000_000
        case .composer:
            return 5_500_000_000
        case .agent:
            return 7_000_000_000
        case .ironclawThinking:
            return 10_000_000_000
        case .ironclaw:
            return 9_000_000_000
        case .project:
            return 5_000_000_000
        case .share:
            return 6_000_000_000
        }
    }
}

/// Demo-capture-only public data cards (CoinGecko, NEAR RPC, RSS). This is not
/// the normal chat route; user answers and recurring workflows route through the
/// model.
struct LiveDataDemoView: View {
    @State private var widgets: [MessageWidget] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Color.actionPrimary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Data API demo").font(.headline.weight(.semibold))
        Text("Debug cards · not normal chat routing").font(.caption).foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Color.appPanelBackground)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.appHairline).frame(height: 1) }

            ScrollView {
                VStack(spacing: 12) {
                    if isLoading {
                        HStack(spacing: 8) { ProgressView(); Text("Fetching live data…").foregroundStyle(Color.textSecondary) }
                            .padding(.top, 40)
                    }
                    ForEach(widgets) { widget in
                        MessageWidgetCard(widget: widget)
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground)
        }
        .background(Color.appBackground)
        .task {
            var result: [MessageWidget] = []
            if let eth = await LiveDataService.ethPriceWidget() { result.append(eth) }
            if let near = await LiveDataService.nearAccountWidget(account: "root.near") { result.append(near) }
            if let news = await LiveDataService.newsBriefWidget() { result.append(news) }
            widgets = result
            isLoading = false
        }
    }
}

/// Failure-state QA context: a tracker whose last run failed with the
/// restricted-route error, backed by a throwaway store so the Run again
/// affordance renders and behaves like the real screen.
@MainActor
func demoFailedTrackerContext() -> (store: BriefingStore, briefing: Briefing) {
    let failureCopy = "The private route is temporarily busy. Use the privacy proxy for this turn, or retry private in a moment."
    let briefing = Briefing(
        title: "NEAR price",
        prompt: "Track the NEAR price and summarize the move.",
        schedule: .daily(hour: 8, minute: 0),
        lastFailureAt: Date().addingTimeInterval(-120),
        lastFailureMessage: failureCopy
    )
    let store = BriefingStore(
        briefings: [briefing],
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("demo-failed-tracker.json"),
        runner: { _ in .failed(failureCopy) }
    )
    return (store, briefing)
}

func demoCouncilRoomModel() -> CouncilRoomModel {
    let now = Date()
    let batch = "demo-council"
    func message(_ id: String, _ model: String, _ text: String) -> ChatMessage {
        ChatMessage(id: id, role: .assistant, text: text, model: model, createdAt: now, status: "completed", responseID: "\(id)-r", councilBatchID: batch, isStreaming: false)
    }
    let messages = [
        message("c-private", ChatStore.defaultModelID, "I concur. The architecture is sound and the streaming path is stable in main, so shipping is reasonable."),
        message("c-independent-a", "near-cloud/anthropic/claude-opus-4-7", "Yes, with caveats. The latency budget on the streaming side is the one risk. If we cap concurrent models at 3 we hold the SLA at p95 < 1.4s."),
        message("c-independent-b", "near-cloud/openai/gpt-5.5", "I disagree. Per-message proof for cross-model consensus is not landed in main; however, shipping without it means the verification footer is silently wrong on Council answers."),
        message("c-syn", "llm-council/synthesis", "Synthesis: the council broadly supports shipping Council v2.\n\nAgreement: two of three models back shipping; the architecture and streaming path are considered stable.\n\nDisagreement: one model flags that per-message cross-model proof is not yet in main.\n\nRecommended next step: ship behind a flag, land the proof path, then enable by default.")
    ]
    return CouncilRoomModel.from(councilMessages: messages)
}
#endif
