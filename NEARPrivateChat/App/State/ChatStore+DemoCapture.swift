import Foundation
#if canImport(UIKit)
import UIKit
#endif

#if DEBUG
extension ChatStore {
    #if canImport(UIKit)
    /// ReleaseGate seam: the system file picker cannot be driven headlessly,
    /// so a fixture PDF with a known sentinel is generated at runtime and
    /// attached through the REAL extraction + upload pipeline when the app is
    /// launched with -NEARReleaseGateFixture.
    func stageReleaseGateFixturePDF() async {
        guard !didStageReleaseGateFixture else { return }
        didStageReleaseGateFixture = true
        let body = """
        Hexagon Series B Term Sheet (Release Gate Fixture)

        Key verification fact: ZEPHYR-7 thermal margin is 42 percent.
        The raise is $4M on a $40M cap with a 1x non-participating preference.
        Obligations: monthly investor reporting; 60-day exclusivity window.
        """
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { context in
            context.beginPage()
            body.draw(
                in: CGRect(x: 48, y: 48, width: 516, height: 700),
                withAttributes: [.font: UIFont.systemFont(ofSize: 14)]
            )
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("release-gate-term-sheet.pdf")
        try? data.write(to: url)
        await addAttachment(from: url)
    }
    #endif

    func prepareDemoCapture(screen: DemoCaptureScreen = .home) {
        cancelBackgroundOwners()
        isLoading = false
        isStreaming = false
        isUploadingAttachment = false
        bannerMessage = nil

        let data = Self.demoCaptureData(now: Date())
        models = data.models
        nearCloudModels = data.nearCloudModels
        projectStore.replaceProjects([data.project], persist: false)
        conversations = data.conversations
        messageRepository.saveLocalMessages(data.glmMessages, for: data.glmConversation.id)
        messageRepository.saveLocalMessages(data.messages, for: data.primaryConversation.id)
        messageRepository.saveLocalMessages(data.agentMessages, for: data.agentConversation.id)
        fileStore.reset()
        securityStore.replaceAttestationSnapshot(data.attestation)
        ironclawSettings = IronclawSettings(
            isEnabled: true,
            baseURL: "https://ironclaw-demo.near.ai",
            threadID: "demo-thread-ironclaw-prs"
        )
        ironclawTokenConfigured = true
        ironclawStatusText = "Hosted IronClaw ready"
        ironclawLastVerifiedAt = Date().addingTimeInterval(-90)
        ironclawToolNames = ["read_files", "edit_code", "run_tests", "github"]
        nearCloudKeyConfigured = true
        billingSnapshot = nil
        routeReadinessIssue = nil
        attachmentStagingStore.resetAll()
        projectStore.selectProjectID(data.project.id, persist: false)
        selectedModel = Self.defaultModelID
        councilModelIDs = data.models
            .filter { !$0.isIronclawModel }
            .prefix(Self.maxCouncilModels)
            .map(\.id)
        webSearchEnabled = false
        sourceMode = .auto
        researchModeEnabled = false
        advancedModelParams = .defaults
        systemPrompt = ""
        soulMarkdown = ""

        switch screen {
        case .onboarding:
            selectedConversation = nil
            messages = []
            draft = ""
        case .login:
            selectedConversation = nil
            messages = []
            draft = ""
        case .home:
            selectedConversation = nil
            messages = []
            draft = ""
        case .dashboard:
            selectedConversation = nil
            messages = []
            draft = ""
        case .fileAttach:
            selectedConversation = nil
            messages = []
            pendingAttachments = data.project.attachments
            sourceMode = .files
            draft = "Update this project plan based on the latest IronClaw PRs."
        case .composer:
            selectedConversation = nil
            messages = []
            projectStore.selectProjectID(nil, persist: false)
            pendingAttachments = []
            pendingSharedFileURLs = [:]
            councilModelIDs = [Self.defaultModelID]
            sourceMode = .auto
            webSearchEnabled = false
            draft = "Turn this screenshot or file into actions I can approve."
        case .agent:
            selectedConversation = nil
            messages = []
            selectedModel = ModelOption.ironclawModelID
            councilModelIDs = []
            sourceMode = .all
            draft = "Use the attached project plan and latest nearai/ironclaw PRs to update the plan."
        case .ironclaw:
            selectedConversation = data.agentConversation
            messages = data.agentMessages
            selectedModel = ModelOption.ironclawModelID
            councilModelIDs = []
            sourceMode = .all
            draft = ""
        case .ironclawThinking:
            selectedConversation = data.agentConversation
            messages = data.agentMessages
            selectedModel = ModelOption.ironclawModelID
            councilModelIDs = []
            sourceMode = .all
            draft = ""
        case .glmResult:
            selectedConversation = data.glmConversation
            messages = data.glmMessages
            selectedModel = Self.defaultModelID
            councilModelIDs = []
            projectStore.selectProjectID(nil, persist: false)
            sourceMode = .web
            webSearchEnabled = true
            draft = ""
        case .verification:
            selectedConversation = data.glmConversation
            messages = data.glmMessages
            selectedModel = Self.defaultModelID
            councilModelIDs = []
            projectStore.selectProjectID(nil, persist: false)
            draft = ""
        case .models:
            selectedConversation = data.glmConversation
            messages = data.glmMessages
            selectedModel = Self.defaultModelID
            councilModelIDs = []
            projectStore.selectProjectID(nil, persist: false)
            draft = ""
        case .widgets:
            selectedConversation = data.glmConversation
            messages = Self.demoWidgetMessages(now: Date())
            selectedModel = Self.defaultModelID
            councilModelIDs = []
            projectStore.selectProjectID(nil, persist: false)
            sourceMode = .web
            webSearchEnabled = true
            draft = ""
        case .generativeChat:
            // Drives the REAL prompt through normal send routing. Override the
            // prompt with NEAR_DEMO_PROMPT to capture a specific chat flow.
            selectedConversation = data.primaryConversation
            projectStore.selectProjectID(nil, persist: false)
            messages = []
            draft = DemoCapture.demoPrompt ?? "What should I track from this project plan every morning?"
            sendDraft()
        case .chatStarters:
            // Empty new chat with council off so the default live-data starter
            // chips show current data/tracker examples without seeding Home.
            selectedConversation = nil
            projectStore.selectProjectID(nil, persist: false)
            messages = []
            councilModelIDs = [Self.defaultModelID]
            selectedModel = Self.defaultModelID
            draft = ""
        case .councilBriefingLive:
            // Runs a REAL scheduled council briefing against the backend using an
            // env-injected session token (DebugBackend). Verifies end-to-end that
            // "using council" trackers do real multi-model work on a schedule.
            selectedConversation = nil
            projectStore.selectProjectID(nil, persist: false)
            messages = []
            draft = ""
            if !didStartLiveCouncilDemo {
                didStartLiveCouncilDemo = true
                Task { @MainActor [weak self] in
                    await self?.runLiveCouncilBriefingDemo()
                }
            }
        case .chatFailure:
            // Failure-state QA surface: one successful turn next to a failed
            // turn, so proof/action affordances can be compared side by side.
            selectedConversation = data.glmConversation
            messages = Self.demoFailureMessages(now: Date())
            selectedModel = Self.defaultModelID
            councilModelIDs = []
            projectStore.selectProjectID(nil, persist: false)
            draft = ""
        case .trackerFailure, .markdownGallery:
            selectedConversation = nil
            messages = []
            draft = ""
        case .chat, .briefingBuilder, .councilOutput, .cloudModels, .council, .councilRoom, .threaded, .liveData, .project, .share:
            selectedConversation = data.primaryConversation
            messages = data.messages
            draft = ""
        }
    }

    /// Drives a real scheduled council briefing against the backend (token via
    /// DebugBackend) and renders its synthesized result inline for verification.
    @MainActor
    private func runLiveCouncilBriefingDemo() async {
        if let key = DebugBackend.cloudKey {
            saveNearCloudAPIKey(key)
        }
        // Load real models directly. NOT bootstrap() - it short-circuits to
        // prepareDemoCapture in demo mode, which would re-enter this case and
        // recursively spawn runs (the source of the earlier 502 storm).
        await refreshModels(loadCloudCatalog: nearCloudKeyConfigured)
        selectedConversation = ConversationSummary(
            id: "live-council-demo",
            createdAt: Date().timeIntervalSince1970,
            metadata: ConversationMetadata(title: "Council briefing")
        )
        messages = [
            ChatMessage(
                id: "live-council-user",
                role: .user,
                text: "Set up a daily briefing that summarizes today's most important AI developments - using council.",
                model: nil,
                createdAt: Date(),
                status: "completed",
                responseID: nil,
                isStreaming: false
            ),
            ChatMessage(
                id: "live-council-pending",
                role: .assistant,
                text: "Running the council...",
                model: ModelOption.llmCouncilSynthesisModelID,
                createdAt: Date(),
                status: "searching",
                responseID: nil,
                isStreaming: true
            )
        ]
        let briefing = Briefing(
            title: "AI briefing",
            prompt: "In 3 short bullets, summarize today's most important AI developments. Keep it under 100 words total.",
            schedule: .daily(hour: 8, minute: 0),
            kind: .customPrompt,
            council: true
        )
        let outcome = await runBriefing(briefing)
        updateMessage("live-council-pending") { message in
            message.isStreaming = false
            if case let .delivered(widget) = outcome {
                message.status = "completed"
                message.widget = widget
                message.text = ""
            } else {
                message.status = "briefing_no_result"
                message.text = "Council produced no result - check sign-in, models, or network."
            }
        }
    }
}
#endif
