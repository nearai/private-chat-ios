import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testRouteReadinessBlocksCouncilWithFewerThanTwoUsableModels() {
        let issue = RoutePlanner.routeReadinessIssue(
            selectedModelID: "zai-org/GLM-5.1-FP8",
            requestedCouncilModelIDs: ["zai-org/GLM-5.1-FP8"],
            isCouncilRequested: true,
            nearCloudKeyConfigured: true,
            hostedIronclawEndpointUsable: true
        )

        XCTAssertEqual(issue?.route, .council)
        XCTAssertEqual(issue?.recoveryAction, .editCouncilLineup)
    }

    func testRouteReadinessRequiresCloudKeyForCouncilCloudLegs() {
        let issue = RoutePlanner.routeReadinessIssue(
            selectedModelID: "zai-org/GLM-5.1-FP8",
            requestedCouncilModelIDs: [
                "zai-org/GLM-5.1-FP8",
                ModelOption.nearCloudModelID(for: "anthropic/claude-opus-4-7")
            ],
            isCouncilRequested: true,
            nearCloudKeyConfigured: false,
            hostedIronclawEndpointUsable: true
        )

        XCTAssertEqual(issue?.route, .nearCloud)
        XCTAssertEqual(issue?.recoveryAction, .addNearCloudKey)
    }

    func testRouteReadinessAllowsReadySingleAndCouncilRoutes() {
        XCTAssertNil(RoutePlanner.routeReadinessIssue(
            selectedModelID: ModelOption.nearCloudModelID(for: "openai/gpt-5.5"),
            requestedCouncilModelIDs: [],
            isCouncilRequested: false,
            nearCloudKeyConfigured: true,
            hostedIronclawEndpointUsable: true
        ))

        XCTAssertNil(RoutePlanner.routeReadinessIssue(
            selectedModelID: "zai-org/GLM-5.1-FP8",
            requestedCouncilModelIDs: [
                "zai-org/GLM-5.1-FP8",
                "Qwen/Qwen3.5-122B-A10B"
            ],
            isCouncilRequested: true,
            nearCloudKeyConfigured: true,
            hostedIronclawEndpointUsable: true
        ))
    }


    @MainActor
    func testSelectingSingleModelKeepsCouncilOffWithoutCompleteLineup() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.useDefaultCouncilLineup()
        XCTAssertFalse(store.isCouncilModeEnabled)

        let modelID = ChatStore.defaultModelID
        store.selectModel(modelID)

        XCTAssertEqual(store.selectedModel, modelID)
        XCTAssertEqual(store.councilModelIDs, [modelID])
        XCTAssertFalse(store.isCouncilModeEnabled)
    }


    @MainActor
    func testRequestCouncilHonorsExplicitLineupWithoutInjectingSelectedModel() {
        let memberA = "Qwen/Qwen3.5-122B-A10B"
        let memberB = "Qwen/Qwen3.6-35B-A3B-FP8"
        let memberC = "moonshotai/Kimi-K2-Instruct"
        let catalog = ModelCatalogStore(
            models: [
                ModelOption(modelID: ModelOption.nearPrivateDefaultModelID, publicModel: true, metadata: nil),
                ModelOption(modelID: memberA, publicModel: true, metadata: nil),
                ModelOption(modelID: memberB, publicModel: true, metadata: nil),
                ModelOption(modelID: memberC, publicModel: true, metadata: nil)
            ],
            preferredModelIDs: [ModelOption.nearPrivateDefaultModelID, memberA, memberB, memberC]
        )

        // GLM stays the selected model while the user builds a deliberate
        // 3-model lineup that excludes it. The old force-prepend added GLM and
        // prefix(3) then dropped the user's third pick.
        catalog.selectedModel = ModelOption.nearPrivateDefaultModelID
        catalog.councilModelIDs = [memberA, memberB, memberC]

        let resolved = catalog.requestCouncilModelIDs(for: ModelOption.nearPrivateDefaultModelID)
        XCTAssertFalse(resolved.contains(ModelOption.nearPrivateDefaultModelID), "selected model must not be force-injected")
        XCTAssertEqual(Set(resolved), Set([memberA, memberB, memberC]), "all three explicit picks survive")
    }

    @MainActor
    func testRecommendedCouncilLineupDoesNotInventCloudFallbackModels() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))

        store.useDefaultCouncilLineup()

        let visibleNames = store.activeCouncilModels.map(\.displayName).joined(separator: " ")
        XCTAssertFalse(visibleNames.contains("Qwen 3.7 Max"))
        XCTAssertFalse(visibleNames.contains("Claude Opus 4.7"))
        XCTAssertFalse(store.activeCouncilModels.contains { $0.isNearCloudModel })
    }

    func testHomeOrchestrationPlannerPromotesLiveBriefingsCouncilAndAgent() {
        let liveID = UUID()
        let scheduledID = UUID()
        let liveBriefing = Briefing(
            id: liveID,
            title: "ETH watcher",
            prompt: "Watch ETH",
            schedule: .daily(hour: 8, minute: 0),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastRunAt: Date(timeIntervalSince1970: 1_700_010_000),
            latestResult: MessageWidget(
                kind: .metric,
                title: "ETH threshold",
                time: "8:02am",
                metric: WidgetMetric(label: "ETH", value: "$3,124", delta: "-2.3%", trend: .down, caption: "Threshold broken")
            )
        )
        let scheduledBriefing = Briefing(
            id: scheduledID,
            title: "Weekly market",
            prompt: "Summarize market",
            schedule: .weekly(weekday: 2, hour: 7, minute: 0),
            createdAt: Date(timeIntervalSince1970: 1_699_900_000)
        )

        let plan = HomeOrchestrationPlanner.make(
            briefings: [scheduledBriefing, liveBriefing],
            projects: [],
            conversations: [],
            selectedProjectID: nil,
            isStreaming: false,
            routeLabel: "Private Council",
            isCouncilModeEnabled: true,
            defaultCouncilModelCount: 3,
            councilModelNames: ["GLM 5.1", "Claude", "Gemini"],
            hostedAgentAvailable: true,
            mobileAgentAvailable: true
        )

        XCTAssertEqual(plan.liveItems.first?.id, "briefing-\(liveID.uuidString)")
        XCTAssertEqual(plan.liveItems.first?.statusText, "8:02am")
        XCTAssertEqual(plan.liveItems.first?.action, .openBriefing(liveID))
        XCTAssertTrue(plan.liveItems.contains { $0.id == "council-room" && $0.action != .useAutoCouncil })
        XCTAssertTrue(plan.liveItems.contains { $0.id == "agent-builder" })
        XCTAssertEqual(plan.scheduledItems.map(\.id), [liveID, scheduledID])
        XCTAssertTrue(plan.commands.contains { $0.title == "Run Council" })
    }

    func testHomeOrchestrationPlannerUsesAutoCouncilBeforeCouncilIsEnabled() {
        let plan = HomeOrchestrationPlanner.make(
            briefings: [],
            projects: [],
            conversations: [],
            selectedProjectID: nil,
            isStreaming: false,
            routeLabel: "NEAR Private",
            isCouncilModeEnabled: false,
            defaultCouncilModelCount: 3,
            councilModelNames: ["GLM 5.1"],
            hostedAgentAvailable: false,
            mobileAgentAvailable: false
        )

        let councilItem = plan.liveItems.first(where: { $0.id == "council-room" })
        XCTAssertEqual(councilItem?.title, "Recommended Council")
        XCTAssertEqual(councilItem?.subtitle, "3 models available")
        XCTAssertEqual(councilItem?.detail, "Enable the recommended multi-model lineup.")
        XCTAssertEqual(councilItem?.action, .useAutoCouncil)
        XCTAssertEqual(plan.commands.first(where: { $0.id == "council" })?.action, .useAutoCouncil)
    }

    func testHomeOrchestrationPlannerAsksToCompleteIncompleteCouncilLineup() {
        let project = ChatProject(
            id: "project-ironclaw",
            name: "IronClaw Reborn Plan",
            createdAt: Date(timeIntervalSince1970: 1_700_200_000),
            conversationIDs: []
        )
        let plan = HomeOrchestrationPlanner.make(
            briefings: [],
            projects: [project],
            conversations: [],
            selectedProjectID: project.id,
            isStreaming: false,
            routeLabel: "Private Council",
            isCouncilModeEnabled: true,
            defaultCouncilModelCount: 1,
            councilModelNames: ["GLM 5.1"],
            hostedAgentAvailable: true,
            mobileAgentAvailable: false
        )

        let councilItem = plan.liveItems.first(where: { $0.id == "council-room" })
        XCTAssertEqual(councilItem?.title, "Finish Council setup")
        XCTAssertEqual(councilItem?.subtitle, "1 model selected")
        XCTAssertEqual(councilItem?.detail, "Add at least one more model before running Council.")
        XCTAssertEqual(councilItem?.statusText, "Needs 2")
        XCTAssertEqual(councilItem?.tone, .amber)
        XCTAssertEqual(councilItem?.action, .editCouncilLineup)
        // Subtitle format follows HomeOrchestrationPlanner.surfaceSubtitle; the
        // invariant under test is that an incomplete lineup never claims Council.
        XCTAssertEqual(plan.subtitle, "Project context loaded. Agent route ready.")
        XCTAssertFalse(plan.subtitle.contains("Council"))

        let councilCommand = plan.commands.first(where: { $0.id == "council" })
        XCTAssertEqual(councilCommand?.title, "Edit Council")
        XCTAssertEqual(councilCommand?.action, .editCouncilLineup)
        XCTAssertFalse(plan.commands.contains { $0.title == "Run Council" })
    }

    func testCouncilMessageProgressTracksFirstTokenAndUsableAnswer() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let firstTokenAt = createdAt.addingTimeInterval(1.4)
        let completed = ChatMessage(
            id: "council-1",
            role: .assistant,
            text: "Council answer",
            model: "zai-org/GLM-5.1-FP8",
            createdAt: createdAt,
            firstTokenAt: firstTokenAt,
            status: "completed",
            responseID: "resp-1",
            councilBatchID: "batch-1",
            isStreaming: false
        )
        let streaming = ChatMessage(
            id: "council-2",
            role: .assistant,
            text: "",
            model: "Qwen/Qwen3.5-122B-A10B",
            createdAt: createdAt,
            status: "streaming",
            responseID: nil,
            councilBatchID: "batch-1",
            isStreaming: true
        )

        XCTAssertEqual(try XCTUnwrap(completed.firstTokenLatency), 1.4, accuracy: 0.01)
        XCTAssertTrue(completed.hasUsableCouncilAnswer)
        XCTAssertFalse(streaming.hasUsableCouncilAnswer)
    }

    func testMessageTimelineGroupsCouncilBatchOnceAndKeepsChronologicalCouncilOrder() {
        let baseDate = Date(timeIntervalSince1970: 1_000)
        let user = makeMessage(id: "user-1", role: .user, text: "Compare this", createdAt: baseDate)
        let firstCouncil = ChatMessage(
            id: "council-late",
            role: .assistant,
            text: "Second model",
            model: "qwen",
            createdAt: baseDate.addingTimeInterval(3),
            status: "completed",
            responseID: "resp-late",
            councilBatchID: "batch-1",
            isStreaming: false
        )
        let secondCouncil = ChatMessage(
            id: "council-early",
            role: .assistant,
            text: "First model",
            model: "glm",
            createdAt: baseDate.addingTimeInterval(2),
            status: "completed",
            responseID: "resp-early",
            councilBatchID: "batch-1",
            isStreaming: false
        )
        let standaloneAssistant = makeMessage(
            id: "assistant-1",
            role: .assistant,
            text: "Done",
            createdAt: baseDate.addingTimeInterval(4)
        )

        let items = MessageTimelineStore.displayItems(from: [user, firstCouncil, secondCouncil, standaloneAssistant])

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.first?.id, "user-1")
        guard case let .council(batchID, messages) = items[1] else {
            return XCTFail("Expected the Council batch to be grouped into one display item.")
        }
        XCTAssertEqual(batchID, "batch-1")
        XCTAssertEqual(messages.map(\.id), ["council-early", "council-late"])
        XCTAssertEqual(items.last?.id, "assistant-1")
    }

    func testCouncilRoomModelParsesDisagreementsOrUncertaintyHeading() {
        let batchID = "batch-parse"
        let answer = ChatMessage(
            id: "answer-1",
            role: .assistant,
            text: "I agree with the cautious path.",
            model: "zai-org/GLM-5.1-FP8",
            createdAt: Date(timeIntervalSince1970: 1_000),
            status: "completed",
            responseID: "resp-answer",
            councilBatchID: batchID,
            isStreaming: false
        )
        let synthesis = ChatMessage(
            id: "synthesis-1",
            role: .assistant,
            text: """
            ## Direct answer
            Ship behind a flag.
            ## What the council agrees on
            The core path is ready.
            ## Disagreements or uncertainty
            Proof coverage is not complete.
            ## Recommended next step
            Add the proof gate.
            """,
            model: ModelOption.llmCouncilSynthesisModelID,
            createdAt: Date(timeIntervalSince1970: 1_001),
            status: "completed",
            responseID: "resp-synthesis",
            councilBatchID: batchID,
            isStreaming: false
        )

        let model = CouncilRoomModel.from(councilMessages: [answer, synthesis])

        XCTAssertEqual(model.synthesis?.disagreement, "Proof coverage is not complete.")
        XCTAssertEqual(model.synthesis?.nextStep, "Add the proof gate.")
    }

    func testCouncilBatchModelIDsIgnoreSynthesisAndPreserveOrder() {
        let batchID = "batch-route"
        let baseDate = Date(timeIntervalSince1970: 1_000)
        let qwen = ChatMessage(
            id: "qwen",
            role: .assistant,
            text: "Answer",
            model: "near-cloud/qwen",
            createdAt: baseDate.addingTimeInterval(2),
            status: "completed",
            responseID: nil,
            councilBatchID: batchID,
            isStreaming: false
        )
        let glm = ChatMessage(
            id: "glm",
            role: .assistant,
            text: "Answer",
            model: "zai-org/GLM-5.1-FP8",
            createdAt: baseDate.addingTimeInterval(1),
            status: "completed",
            responseID: nil,
            councilBatchID: batchID,
            isStreaming: false
        )
        let duplicateGLM = ChatMessage(
            id: "glm-2",
            role: .assistant,
            text: "Follow-up answer",
            model: "zai-org/GLM-5.1-FP8",
            createdAt: baseDate.addingTimeInterval(3),
            status: "completed",
            responseID: nil,
            councilBatchID: batchID,
            isStreaming: false
        )
        let synthesis = ChatMessage(
            id: "synthesis",
            role: .assistant,
            text: "Synthesis",
            model: ModelOption.llmCouncilSynthesisModelID,
            createdAt: baseDate.addingTimeInterval(4),
            status: "completed",
            responseID: nil,
            councilBatchID: batchID,
            isStreaming: false
        )

        XCTAssertEqual(
            CouncilStreamService.batchModelIDs(from: [qwen, synthesis, duplicateGLM, glm], batchID: batchID),
            ["zai-org/GLM-5.1-FP8", "near-cloud/qwen"]
        )
    }

    func testCouncilTargetedPromptScopesSingleModel() {
        let prompt = CouncilStreamService.targetedPrompt(
            text: "What did you disagree with?",
            modelDisplayName: "Gemini",
            previousAnswer: "I disagreed because proof is missing."
        )

        XCTAssertTrue(prompt.contains("Gemini"))
        XCTAssertTrue(prompt.contains("single selected member"))
        XCTAssertTrue(prompt.contains("What did you disagree with?"))
        XCTAssertTrue(prompt.contains("Your previous Council answer"))
        XCTAssertTrue(prompt.contains("proof is missing"))
        XCTAssertTrue(prompt.contains("Do not claim to speak for the whole council"))
    }

    func testCouncilSynthesisPromptPreservesRequiredSectionsAndRoutedPrompt() {
        let prompt = CouncilStreamService.synthesisPrompt(
            originalPrompt: "Should we ship?",
            routedPrompt: "Should we ship behind a feature flag?",
            responses: [
                ("Private model", "Ship behind a flag."),
                ("Cloud model", "Wait for proof coverage.")
            ]
        )

        XCTAssertTrue(prompt.contains("## Direct answer"))
        XCTAssertTrue(prompt.contains("## What the council agrees on"))
        XCTAssertTrue(prompt.contains("## Disagreements or uncertainty"))
        XCTAssertTrue(prompt.contains("## Recommended next step"))
        XCTAssertTrue(prompt.contains("Routed prompt actually sent"))
        XCTAssertTrue(prompt.contains("Private model"))
        XCTAssertTrue(prompt.contains("Cloud model"))
    }

    func testCouncilStreamServiceCollectsUsableResultsOnly() {
        let batchID = "batch-results"
        let complete = ChatMessage(
            id: "complete",
            role: .assistant,
            text: "Usable answer",
            model: "model-a",
            createdAt: Date(timeIntervalSince1970: 1),
            status: "completed",
            responseID: "response-a",
            councilBatchID: batchID,
            isStreaming: false
        )
        let failed = ChatMessage(
            id: "failed",
            role: .assistant,
            text: "Failed",
            model: "model-b",
            createdAt: Date(timeIntervalSince1970: 2),
            status: "failed",
            responseID: nil,
            councilBatchID: batchID,
            isStreaming: false
        )
        let synthesis = ChatMessage(
            id: "synthesis",
            role: .assistant,
            text: "Synthesis",
            model: ModelOption.llmCouncilSynthesisModelID,
            createdAt: Date(timeIntervalSince1970: 3),
            status: "completed",
            responseID: nil,
            councilBatchID: batchID,
            isStreaming: false
        )

        let results = CouncilStreamService.streamResults(from: [failed, synthesis, complete], batchID: batchID)

        XCTAssertEqual(results.map(\.modelID), ["model-a"])
        XCTAssertEqual(results.map(\.messageID), ["complete"])
    }

    func testCouncilRoomUsesLatestSynthesisAndHidesSynthesisRows() {
        let batchID = "batch"
        let now = Date()
        let user = ChatMessage(
            id: "u",
            role: .user,
            text: "Should we ship?",
            model: nil,
            createdAt: now,
            status: "completed",
            responseID: nil,
            councilBatchID: batchID,
            isStreaming: false
        )
        let answer = ChatMessage(
            id: "a",
            role: .assistant,
            text: "Ship behind a flag.",
            model: "model-a",
            createdAt: now.addingTimeInterval(1),
            status: "completed",
            responseID: "ra",
            councilBatchID: batchID,
            isStreaming: false
        )
        let oldSynthesis = ChatMessage(
            id: "syn-old",
            role: .assistant,
            text: "Old synthesis",
            model: ModelOption.llmCouncilSynthesisModelID,
            createdAt: now.addingTimeInterval(2),
            status: "completed",
            responseID: "old",
            councilBatchID: batchID,
            isStreaming: false
        )
        let newSynthesis = ChatMessage(
            id: "syn-new",
            role: .assistant,
            text: "## Direct answer\nNew synthesis",
            model: ModelOption.llmCouncilSynthesisModelID,
            createdAt: now.addingTimeInterval(3),
            status: "completed",
            responseID: "new",
            councilBatchID: batchID,
            isStreaming: false
        )

        let room = CouncilRoomModel.from(councilMessages: [user, answer, oldSynthesis, newSynthesis])

        XCTAssertEqual(room.messages.map(\.id), ["a"])
        XCTAssertTrue(room.synthesis?.fullText.contains("New synthesis") == true)
        XCTAssertFalse(room.synthesis?.fullText.contains("Old synthesis") == true)
    }

    func testStarterPresetPreviewPlanUsesCurrentCouncilDefaults() {
        let routeDefaults = SetupRouteDefaults(
            privateModelID: "private-model",
            councilModelIDs: ["council-a", "council-b"],
            ironclawMobileModelID: ModelOption.ironclawMobileModelID
        )

        let plan = UserSetupStarterPreset.researchBrief.previewPlan(
            readiness: .optimistic,
            routeDefaults: routeDefaults
        )

        XCTAssertEqual(plan.modelRoute, .council)
        XCTAssertEqual(plan.expectedFirstAction, "Ask the Council")
        XCTAssertEqual(plan.expectedRouteModelIDs, ["council-a", "council-b"])
        XCTAssertEqual(plan.routeDetailContent?.title, "Council lineup")
        XCTAssertEqual(plan.routeDetailContent?.summary, "Council A + Council B · proof depends on the selected models.")
        XCTAssertEqual(plan.routeDetailContent?.symbolName, "square.grid.2x2")
    }

    func testAppSetupPlanRespectsAgentToggleOffAndCouncilToggleOn() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]
        profile.contextStyle = .simple
        profile.wantsIronclaw = false
        profile.wantsCouncil = true

        let plan = AppSetupPlan(profile: profile, readiness: .optimistic)

        XCTAssertEqual(plan.modelRoute, .council)
        XCTAssertFalse(plan.agentEnabled)
        XCTAssertTrue(plan.councilEnabled)
        XCTAssertEqual(plan.focusMode, .auto)
        XCTAssertEqual(plan.expectedFirstAction, "Ask the Council")
    }

    func testAppSetupPlanFallsBackWhenCouncilIsNotReady() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research]
        profile.wantsCouncil = true
        let readiness = AppSetupReadinessSnapshot(
            modelCatalogLoaded: true,
            privateModelAvailable: true,
            defaultCouncilModelCount: 1,
            ironclawMobileAvailable: true,
            hostedIronclawAvailable: false,
            nearCloudKeyConfigured: false
        )

        let plan = AppSetupPlan(profile: profile, readiness: readiness)

        XCTAssertEqual(plan.modelRoute, .privateModel)
        XCTAssertTrue(plan.councilEnabled)
        XCTAssertEqual(plan.expectedFirstAction, "Start private chat; Council needs models")
        XCTAssertEqual(plan.readinessStatus, "Council needs at least two available models; private chat is ready first.")
    }

    func testSetupRestorePlannerFlagsCouncilLineupDrift() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research]
        profile.wantsCouncil = true

        let plan = AppSetupPlan(
            profile: profile,
            readiness: .optimistic,
            routeDefaults: SetupRouteDefaults(
                privateModelID: "zai-org/GLM-5.1-FP8",
                councilModelIDs: [
                    "zai-org/GLM-5.1-FP8",
                    ModelOption.nearCloudModelID(for: "provider/current-model")
                ],
                ironclawMobileModelID: ModelOption.ironclawMobileModelID
            )
        )
        let runtime = SetupRuntimeSnapshot(
            modelRoute: plan.modelRoute,
            focusMode: plan.focusMode,
            webSearchEnabled: profile.wantsWeb,
            researchModeEnabled: true,
            selectedProjectName: plan.starterProjectName,
            selectedModelID: "zai-org/GLM-5.1-FP8",
            councilModelIDs: [
                "zai-org/GLM-5.1-FP8",
                "anthropic/claude-opus-4-7"
            ]
        )

        let restoreState = SetupRestorePlanner.evaluate(profile: profile, plan: plan, runtime: runtime)

        XCTAssertTrue(restoreState.needsRestore)
        XCTAssertEqual(
            restoreState.summaryText,
            "Council lineup changed. Restore saved setup to recover your saved model mix."
        )
        XCTAssertEqual(
            restoreState.differences,
            [
                SetupRestoreDifference(
                    title: "Council",
                    savedValue: "GLM 5.1 + Current Model",
                    currentValue: "GLM 5.1 + Claude Opus 4 7"
                )
            ]
        )
    }

    func testRuntimeSetupProfileInferenceRequiresActiveCouncilMode() {
        let storedSingleModelProfile = UserSetupProfile.inferredCurrentDefaults(
            webSearchEnabled: false,
            sourceMode: .auto,
            selectedModelID: "zai-org/GLM-5.1-FP8",
            hasSelectedProject: false,
            isCouncilModeEnabled: false,
            researchModeEnabled: false
        )
        let activeCouncilProfile = UserSetupProfile.inferredCurrentDefaults(
            webSearchEnabled: true,
            sourceMode: .all,
            selectedModelID: "zai-org/GLM-5.1-FP8",
            hasSelectedProject: true,
            isCouncilModeEnabled: true,
            researchModeEnabled: false
        )

        XCTAssertFalse(storedSingleModelProfile.wantsCouncil)
        XCTAssertEqual(storedSingleModelProfile.useCases, [.privateChat])
        XCTAssertTrue(activeCouncilProfile.wantsCouncil)
        XCTAssertEqual(activeCouncilProfile.useCases, [.teamProjects])
    }

    func testAppSetupPlanUsesCouncilCTAWhenCouncilRouteIsReady() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research]
        profile.wantsCouncil = true

        let plan = AppSetupPlan(profile: profile, readiness: .optimistic)

        XCTAssertEqual(plan.modelRoute, .council)
        XCTAssertEqual(plan.expectedFirstAction, "Ask the Council")
    }


    @MainActor
    func testApplyingSetupRestoresSavedCouncilLineup() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))

        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research]
        profile.wantsCouncil = true
        profile.routeDefaults = SetupRouteDefaults(
            privateModelID: "zai-org/GLM-5.1-FP8",
            councilModelIDs: [
                "zai-org/GLM-5.1-FP8",
                "moonshotai/kimi-k2.6"
            ],
            ironclawMobileModelID: ModelOption.ironclawMobileModelID
        )

        store.applySetupProfile(profile)

        XCTAssertEqual(store.selectedModel, "zai-org/GLM-5.1-FP8")
        XCTAssertEqual(store.councilModelIDs, ["zai-org/GLM-5.1-FP8", "moonshotai/kimi-k2.6"])
    }

    func testAskOrchestratorOffersAgentAndCouncilWithoutChangingSelectedRoute() {
        let decision = AskOrchestrator.decide(
            AskOrchestrator.Input(
                prompt: "Compare options and implement the safest repo patch",
                selectedRoute: .nearPrivate,
                hasProjectContext: false,
                hasPromptAttachments: false,
                nearCloudKeyConfigured: true,
                hostedAgentAvailable: true,
                councilAvailable: true,
                councilActive: false
            )
        )

        XCTAssertEqual(decision.route, .nearPrivate)
        XCTAssertTrue(decision.shouldOfferAgent)
        XCTAssertTrue(decision.shouldOfferCouncil)
        XCTAssertFalse(decision.tools.contains(.agent))
        XCTAssertFalse(decision.tools.contains(.council))
    }

    func testBriefingRoundTripsCouncilFlag() throws {
        let original = Briefing(
            title: "Council briefing",
            prompt: "Analyze the AI market",
            schedule: .daily(hour: 8, minute: 0),
            kind: .customPrompt,
            council: true
        )
        let data = try JSONEncoder().encode(original)
        XCTAssertTrue(try JSONDecoder().decode(Briefing.self, from: data).council)

        // A briefings.json written before `council` existed decodes to false.
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "council")
        let legacy = try JSONDecoder().decode(Briefing.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertFalse(legacy.council)
    }

    func testQuickIntentParsesCouncilBriefingTracker() throws {
        let intent = QuickIntentParser.parse(
            "set up a daily briefing that analyzes the AI market using council"
        )
        guard case let .createTracker(spec) = intent else {
            return XCTFail("Expected a createTracker intent, got \(String(describing: intent)).")
        }
        XCTAssertEqual(spec.kind, .customPrompt)
        XCTAssertTrue(spec.council)
        XCTAssertEqual(spec.schedule, .daily(hour: 8, minute: 0))
        // The council runs on the user's question, not the scaffolding.
        let prompt = try XCTUnwrap(spec.prompt).lowercased()
        XCTAssertTrue(prompt.contains("ai market"))
        XCTAssertFalse(prompt.contains("council"))
        XCTAssertFalse(prompt.contains("daily"))
    }

    func testQuickIntentParsesNonCouncilBriefingTracker() throws {
        let intent = QuickIntentParser.parse(
            "set up a daily briefing that summarizes the top AI papers"
        )
        guard case let .createTracker(spec) = intent else {
            return XCTFail("Expected a createTracker intent, got \(String(describing: intent)).")
        }
        XCTAssertEqual(spec.kind, .customPrompt)
        XCTAssertFalse(spec.council)
        XCTAssertEqual(spec.schedule, .daily(hour: 8, minute: 0))
        let prompt = try XCTUnwrap(spec.prompt).lowercased()
        XCTAssertTrue(prompt.contains("ai papers"))
    }


    @MainActor
    func testCreateCouncilBriefingPromptLandsCouncilTracker() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("briefings-\(UUID().uuidString).json")
        let briefingStore = BriefingStore(briefings: [], fileURL: tempFile, runner: { _ in .failed(nil) })
        let chatStore = ChatStore(api: PrivateChatAPI(configuration: .production))
        chatStore.onCreateTracker = { [weak briefingStore] briefing in
            briefingStore?.add(briefing)
        }

        chatStore.draft = "set up a daily briefing that analyzes the AI market using council"
        chatStore.sendDraft()

        let landed = try XCTUnwrap(briefingStore.briefings.first)
        XCTAssertEqual(landed.kind, .customPrompt)
        XCTAssertTrue(landed.council)
        // The persisted prompt is the cleaned question, not the scaffolding.
        XCTAssertTrue(landed.prompt.lowercased().contains("ai market"))
        XCTAssertFalse(landed.prompt.lowercased().contains("council"))

        try? FileManager.default.removeItem(at: tempFile)
    }
}
