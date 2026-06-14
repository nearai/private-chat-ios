import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testIronclawSettingsAcceptsRebornHTTPSAndRejectsLocalGateways() {
        let reborn = IronclawSettings(
            isEnabled: true,
            baseURL: " https://dangwalvaidy.family/reborn ",
            threadID: ""
        )
        XCTAssertNil(reborn.endpointValidationMessage)
        XCTAssertEqual(reborn.standalonePhoneSanitized.baseURL, "https://dangwalvaidy.family/reborn")

        let local = IronclawSettings(
            isEnabled: true,
            baseURL: "http://127.0.0.1:18789/ironclaw",
            threadID: ""
        )
        XCTAssertNotNil(local.endpointValidationMessage)
        XCTAssertFalse(local.standalonePhoneSanitized.isEnabled)
        XCTAssertEqual(local.standalonePhoneSanitized.baseURL, "")
    }

    @MainActor
    func testAgentStoreVerifiedRebornToolsExposeShellAndGit() {
        let toolNames = AgentStore.verifiedRebornToolNames
        XCTAssertEqual(toolNames, ["shell", "git"])
    }

    func testIronclawRetryClassifierSeparatesTransientAndAuthFailures() {
        XCTAssertEqual(IronclawAPI.retryClassification(statusCode: 429), .retryable)
        XCTAssertEqual(IronclawAPI.retryClassification(statusCode: 503), .retryable)
        XCTAssertEqual(IronclawAPI.retryClassification(for: URLError(.timedOut)), .retryable)

        XCTAssertEqual(IronclawAPI.retryClassification(statusCode: 401), .permanentAuthFailure)
        XCTAssertEqual(IronclawAPI.retryClassification(statusCode: 403), .permanentAuthFailure)
        XCTAssertEqual(IronclawAPI.retryClassification(statusCode: 400), .permanentFailure)
    }

    func testIronclawSubmitResponseUsesActiveRunIDForDeferredBusy() throws {
        let data = Data("""
        {
          "outcome": "deferred_busy",
          "status": "queued",
          "active_run_id": "run_active_123"
        }
        """.utf8)

        XCTAssertEqual(try IronclawAPI.resolvedSubmitRunIDForTesting(from: data), "run_active_123")
    }

    func testAgentThreadPersistenceStoresTrimmedThreadMappingAndMigrationFlag() throws {
        let defaults = try makeIsolatedDefaults()
        let accountID = "agent-thread-\(UUID().uuidString)"
        let persistence = AgentThreadPersistence(accountID: accountID, defaults: defaults)
        defer {
            FileCache(accountID: accountID, defaults: defaults).remove(
                filename: AgentThreadPersistence.cacheFilename,
                legacyDefaultsKey: AgentThreadPersistence.legacyDefaultsKey
            )
        }

        persistence.ensureMappingMigrationFlagSet()
        XCTAssertTrue(defaults.bool(forKey: "ironclawThreadMappingMigrationV1"))

        XCTAssertTrue(persistence.rememberThreadID("  thread_123  ", for: "conv_1"))
        XCTAssertEqual(persistence.loadThreadID(for: "conv_1"), "thread_123")

        XCTAssertTrue(persistence.removeThreadID(for: "conv_1"))
        XCTAssertNil(persistence.loadThreadID(for: "conv_1"))
    }

    @MainActor
    func testAgentStoreOwnsThreadMappingAndConversationSettings() {
        let accountID = "agent-store-thread-\(UUID().uuidString)"
        let store = AgentStore(accountID: accountID)
        defer {
            FileCache(accountID: accountID).remove(
                filename: AgentThreadPersistence.cacheFilename,
                legacyDefaultsKey: AgentThreadPersistence.legacyDefaultsKey
            )
            SettingsPersistence(accountID: accountID).saveIronclawSettings(.default)
        }

        store.ironclawSettings = IronclawSettings(
            isEnabled: true,
            baseURL: "https://ironclaw.example.com",
            threadID: ""
        )

        XCTAssertTrue(store.rememberIronclawThreadID("  thread_abc123  ", for: "conv_1"))
        XCTAssertEqual(store.loadIronclawThreadID(for: "conv_1"), "thread_abc123")
        XCTAssertEqual(store.ironclawSettings(for: "conv_1").threadID, "thread_abc123")
        XCTAssertTrue(store.ironclawStatusText.contains("thread_a"))

        XCTAssertTrue(store.removeIronclawThreadID(for: "conv_1"))
        XCTAssertNil(store.loadIronclawThreadID(for: "conv_1"))
        XCTAssertEqual(store.ironclawSettings(for: "conv_1").threadID, "")
    }

    @MainActor
    func testAgentStoreOwnsHostedHandoffPreflightDisclosure() throws {
        let accountID = "agent-store-preflight-\(UUID().uuidString)"
        let store = AgentStore(accountID: accountID)
        defer {
            SettingsPersistence(accountID: accountID).saveIronclawSettings(.default)
        }
        store.ironclawSettings = IronclawSettings(
            isEnabled: true,
            baseURL: "https://agent.example.com",
            threadID: ""
        )
        let attachment = ChatAttachment(id: "file_1", name: "services-template.pdf", kind: "pdf", bytes: 1_024)
        let projectDisclosure = ProjectHostedHandoffDisclosure(
            disclosedItems: ["Project: Services agreement", "Saved notes: 1"],
            fingerprint: "project-v1"
        )

        let preflight = try XCTUnwrap(store.hostedHandoffPreflight(
            text: "Draft a services agreement.",
            promptAttachments: [attachment],
            selectedModelID: ModelOption.ironclawModelID,
            promptNeedsHostedWorkstation: false,
            projectDisclosure: projectDisclosure
        ))

        XCTAssertEqual(preflight.destinationHost, "agent.example.com")
        XCTAssertEqual(preflight.promptPreview, "Draft a services agreement.")
        XCTAssertTrue(preflight.disclosedItems.contains("Prompt text: 27 bytes"))
        XCTAssertTrue(preflight.disclosedItems.contains("Prompt files: services-template.pdf"))
        XCTAssertTrue(preflight.disclosedItems.contains("Project: Services agreement"))
        XCTAssertTrue(preflight.disclosedItems.contains("Saved notes: 1"))

        store.pendingHostedHandoffPreflight = preflight
        store.reset()

        XCTAssertNil(store.pendingHostedHandoffPreflight)
    }

    @MainActor
    func testAgentStoreBuildsMissionPromptAndExtractsBrief() throws {
        let prompt = try XCTUnwrap(AgentStore.phoneAgentMissionPrompt(
            for: "Agent: run a security audit on https://github.com/near/nearcore/pull/42"
        ))

        XCTAssertTrue(prompt.contains("Hosted IronClaw Mission: Security Review"))
        XCTAssertTrue(prompt.contains("Mission brief from phone:"))
        XCTAssertTrue(prompt.contains("run a security audit on https://github.com/near/nearcore/pull/42"))
        XCTAssertTrue(prompt.contains("Do not commit, push, or open a PR unless I explicitly ask."))
        XCTAssertEqual(
            AgentStore.agentMissionBrief(from: prompt),
            "run a security audit on https://github.com/near/nearcore/pull/42"
        )
        XCTAssertNil(AgentStore.phoneAgentMissionPrompt(for: prompt))
    }

    @MainActor
    func testAgentStoreNormalizesRepoLinksPromptsAndToolMarkdown() throws {
        let url = try XCTUnwrap(AgentStore.firstRepoURL(
            in: "Please triage github.com/near/nearcore/pull/42 before release."
        ))

        XCTAssertEqual(AgentStore.repoProjectName(from: url), "near/nearcore")
        XCTAssertEqual(AgentStore.repoRootURL(from: url)?.absoluteString, "https://github.com/near/nearcore")
        XCTAssertEqual(AgentStore.repoTaskLinkTitle(from: url, projectName: "near/nearcore"), "PR #42")
        XCTAssertEqual(AgentStore.normalizedIronclawPrompt("use ironclaw to run the focused tests"), "run the focused tests")

        let markdown = AgentStore.ironclawToolResultMarkdown([
            IronclawMobileToolResult(
                callName: IronclawMobileToolNames.runtimeCapabilities,
                status: .completed,
                summary: "Checked runtime capabilities",
                detail: "web search\nproject notes"
            )
        ])
        XCTAssertTrue(markdown.contains("**IronClaw Mobile actions**"))
        XCTAssertTrue(markdown.contains("- Checked runtime capabilities"))
        XCTAssertTrue(markdown.contains("web search"))
    }

    func testChatRoleDecodesDeveloperAndToolRoles() throws {
        let decoder = JSONDecoder()

        let developer = try decoder.decode(ChatRole.self, from: Data(#""developer""#.utf8))
        let tool = try decoder.decode(ChatRole.self, from: Data(#""tool""#.utf8))

        XCTAssertEqual(developer, .system)
        XCTAssertEqual(tool, .assistant)
    }

    func testAgentQuickStartUsesHostedAgentCTAWhenHostedFallbackIsReady() {
        let readiness = AppSetupReadinessSnapshot(
            modelCatalogLoaded: true,
            privateModelAvailable: true,
            defaultCouncilModelCount: 3,
            ironclawMobileAvailable: false,
            hostedIronclawAvailable: true,
            nearCloudKeyConfigured: false
        )
        let plan = UserSetupStarterPreset.agentMission.previewPlan(
            readiness: readiness,
            routeDefaults: SetupRouteDefaults(
                privateModelID: "private-model",
                councilModelIDs: ["council-a", "council-b"],
                ironclawMobileModelID: ModelOption.ironclawMobileModelID
            )
        )

        XCTAssertEqual(plan.modelRoute, .ironclaw)
        XCTAssertEqual(plan.expectedFirstAction, "Open Hosted IronClaw")
        XCTAssertEqual(plan.readinessStatus, "Hosted IronClaw is ready; mobile runtime is unavailable.")
        XCTAssertEqual(plan.routeDetailContent?.summary, "Hosted IronClaw · sends work outside this phone.")
    }

    func testAppSetupPlanReflectsAgentProfile() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]
        profile.contextStyle = .project
        profile.wantsIronclaw = true
        profile.wantsCouncil = true

        let plan = AppSetupPlan(profile: profile)

        XCTAssertEqual(plan.modelRoute, .ironclaw)
        XCTAssertEqual(plan.focusMode, .all)
        XCTAssertEqual(plan.starterProjectName, "Build Project")
        XCTAssertTrue(plan.agentEnabled)
        XCTAssertTrue(plan.councilEnabled)
        XCTAssertEqual(plan.expectedFirstAction, "Plan a build task")
        XCTAssertEqual(plan.readinessStatus, "Ready: Agent")
    }

    func testAppSetupPlanFallsBackWhenIronclawMobileIsNotReady() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]
        profile.wantsIronclaw = true
        let readiness = AppSetupReadinessSnapshot(
            modelCatalogLoaded: true,
            privateModelAvailable: true,
            defaultCouncilModelCount: 3,
            ironclawMobileAvailable: false,
            hostedIronclawAvailable: false,
            nearCloudKeyConfigured: false
        )

        let plan = AppSetupPlan(profile: profile, readiness: readiness)

        XCTAssertEqual(plan.modelRoute, .privateModel)
        XCTAssertTrue(plan.agentEnabled)
        XCTAssertEqual(plan.expectedFirstAction, "Start private chat while Agent tools load")
        XCTAssertEqual(plan.readinessStatus, "IronClaw Mobile is still loading; private chat is ready first.")
    }

    func testMultiTrackSetupBuildsMixedWorkspaceSeeds() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents, .research, .teamProjects]
        profile.contextStyle = .project

        let plan = AppSetupPlan(profile: profile.normalizedForDefaults, readiness: .optimistic)

        XCTAssertEqual(
            plan.starterWorkspaceSeeds.map(\.title),
            ["Project", "Repo plan", "Research brief", "Project memory", "Shared guide"]
        )
        XCTAssertEqual(
            plan.starterWorkspaceSeeds[1].detail,
            "Starter prompts ask for a safe patch plan and focused verification before code changes."
        )
        XCTAssertEqual(
            plan.starterWorkspaceSeeds.last?.detail,
            "3 setup tracks share one reusable guide note and project instructions."
        )
    }

    func testPowerToolsCanBeUnlockedWithoutRerunningSetup() throws {
        let suiteName = "power-tools-unlock-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let accountID = "user:power-tools"

        var profile = UserSetupProfile.defaults
        profile.goalText = "Keep my private chat defaults."
        UserSetupStorage.save(profile, for: accountID, defaults: defaults)

        var unlocked = try XCTUnwrap(UserSetupStorage.load(for: accountID, defaults: defaults))
        unlocked.experienceMode = .power
        UserSetupStorage.save(unlocked, for: accountID, defaults: defaults)

        let loaded = try XCTUnwrap(UserSetupStorage.load(for: accountID, defaults: defaults))
        XCTAssertEqual(loaded.experienceMode, .power)
        XCTAssertEqual(loaded.goalText, "Keep my private chat defaults.")
        XCTAssertEqual(loaded.useCases, [.privateChat])
    }

    func testUserSetupBlankGoalKeepsStaticBuildAgentSkillDefaults() {
        var profile = UserSetupProfile.defaults
        profile.useCases = [.buildAgents]
        profile.useCase = .buildAgents
        profile.contextStyle = .project
        profile.wantsIronclaw = true

        XCTAssertEqual(profile.setupSkillSuggestions.map(\.id), ["plan-mode", "developer-setup", "project-setup", "coding"])
    }

    func testUserSetupGoalInjectsMatchingIronclawSkillsIntoOnboarding() {
        var profile = UserSetupProfile.defaults
        profile.useCases = [.buildAgents]
        profile.useCase = .buildAgents
        profile.contextStyle = .project
        profile.wantsIronclaw = true
        profile.goalText = "Run a security audit with a manual test plan before merge."

        XCTAssertEqual(
            profile.setupSkillSuggestions.map(\.id),
            ["plan-mode", "developer-setup", "qa-review", "security-review", "review-readiness"]
        )
    }

    func testBuildAgentSetupProducesSavedGoalMissionSuggestion() {
        var profile = UserSetupProfile.defaults
        profile.useCases = [.buildAgents]
        profile.useCase = .buildAgents
        profile.contextStyle = .project
        profile.wantsIronclaw = true
        profile.goalText = "Review the repo and plan the first safe patch."

        let suggestion = profile.agentMissionSuggestion

        XCTAssertEqual(suggestion?.title, "Use saved setup goal")
        XCTAssertEqual(suggestion?.detail, "Saved setup runs Agent work for this goal first.")
        XCTAssertEqual(
            suggestion?.prompt,
            "Plan the first build or repo task for this goal: Review the repo and plan the first safe patch."
        )
    }

    func testAppSetupPlanCarriesSavedAgentMissionSuggestion() {
        var profile = UserSetupProfile.defaults
        profile.useCases = [.buildAgents]
        profile.useCase = .buildAgents
        profile.contextStyle = .project
        profile.wantsIronclaw = true
        profile.goalText = "Review the repo and plan the first safe patch."

        let plan = AppSetupPlan(profile: profile, readiness: .optimistic)

        XCTAssertEqual(plan.agentMissionSuggestion?.title, "Use saved setup goal")
        XCTAssertEqual(
            plan.agentMissionSuggestion?.prompt,
            "Plan the first build or repo task for this goal: Review the repo and plan the first safe patch."
        )
    }

    func testBuildAgentSetupWithoutGoalProducesStarterMissionSuggestion() {
        var profile = UserSetupProfile.defaults
        profile.useCases = [.buildAgents]
        profile.useCase = .buildAgents
        profile.contextStyle = .project
        profile.wantsIronclaw = true

        let suggestion = profile.agentMissionSuggestion

        XCTAssertEqual(suggestion?.title, "Use saved Agent starter")
        XCTAssertEqual(suggestion?.detail, "Saved setup keeps repo and Agent work ready from day one.")
        XCTAssertEqual(suggestion?.prompt, UserSetupUseCase.buildAgents.starterPrompt)
    }

    func testPrivateChatSetupDoesNotProduceAgentMissionSuggestion() {
        XCTAssertNil(UserSetupProfile.defaults.agentMissionSuggestion)
    }

    func testIronclawSkillMissionPromptSharpensExistingMission() throws {
        let skill = try XCTUnwrap(IronclawSkillCatalog.all.first(where: { $0.id == "code-review" }))

        let prompt = skill.missionPrompt(
            seed: "Review the chat export diff before merging",
            projectName: "Verifier"
        )

        XCTAssertTrue(prompt.contains("Use the Verifier project context when it helps."))
        XCTAssertTrue(prompt.contains("Review this code carefully: Review the chat export diff before merging."))
        XCTAssertTrue(prompt.contains("Lead with findings"))
    }

    func testIronclawSkillMissionPromptSupportsTechDebtTracking() throws {
        let skill = try XCTUnwrap(IronclawSkillCatalog.all.first(where: { $0.id == "tech-debt-tracker" }))

        let prompt = skill.missionPrompt(
            seed: "Capture the cleanup we should defer after shipping setup onboarding",
            projectName: "NEAR Private Chat"
        )

        XCTAssertTrue(prompt.contains("Use the NEAR Private Chat project context when it helps."))
        XCTAssertTrue(prompt.contains("Track this technical debt: Capture the cleanup we should defer after shipping setup onboarding."))
        XCTAssertTrue(prompt.contains("smallest remediation step"))
    }

    func testWidgetTaskCommandCanBecomeReminderDraft() throws {
        let now = Date(timeIntervalSince1970: 1_782_777_600) // 2026-06-30 00:00 UTC
        let action = WidgetActionItem(
            title: "Send the deck",
            type: "task",
            detail: nil,
            schedule: nil,
            command: "Remind me to send the deck 2026-07-01 9:00 AM",
            source: nil,
            date: nil,
            time: nil,
            duration: nil,
            recurrence: nil,
            timezone: nil,
            location: nil,
            attendees: [],
            missingFields: [],
            confidence: nil,
            tone: nil
        )

        let draft = try XCTUnwrap(action.systemActionDraft(now: now))

        XCTAssertEqual(draft.kind, .reminder)
        XCTAssertEqual(draft.title, "Send the deck")
        XCTAssertTrue(draft.notes?.contains("Command: Remind me to send the deck") == true)
    }

    func testAgentActivityLogPersistsNewestFirst() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("activity-\(UUID().uuidString).json")
        let log = AgentActivityLog(fileURL: tempFile)
        log.record("Ran briefing “ETH watcher”")
        log.record("Created tracker “Daily news”")
        XCTAssertEqual(log.entries.count, 2)
        XCTAssertEqual(log.entries.first?.summary, "Created tracker “Daily news”") // newest first
        log.record("   ") // blank ignored
        XCTAssertEqual(log.entries.count, 2)

        let reloaded = AgentActivityLog(fileURL: tempFile)
        XCTAssertEqual(reloaded.entries.count, 2)
        reloaded.clear()
        XCTAssertTrue(reloaded.entries.isEmpty)

        try? FileManager.default.removeItem(at: tempFile)
    }

    func testQuickIntentParsesGenericRecurringAgentTracker() throws {
        let intent = QuickIntentParser.parse(
            "check Claude Code release notes every 6 hours"
        )
        guard case let .createTracker(spec) = intent else {
            return XCTFail("Expected a createTracker intent, got \(String(describing: intent)).")
        }
        XCTAssertEqual(spec.kind, .customPrompt)
        XCTAssertEqual(spec.schedule, .everyNHours(6))
        XCTAssertEqual(spec.title, "Claude Code release notes")
        let prompt = try XCTUnwrap(spec.prompt)
        XCTAssertTrue(prompt.contains("Claude Code release notes"))
        XCTAssertTrue(prompt.lowercased().contains("recurring task"))
    }


    @MainActor
    func testEmptyChatStarterCoordinatorAgentActionSelectsIronclawMobile() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.selectModel("zai-org/GLM-5.1-FP8")
        let suggestion = EmptyChatStarterSuggestion(
            title: "Agent",
            symbolName: "terminal",
            prompt: "Draft an Agent mission for this task: ",
            action: .agent
        )

        XCTAssertTrue(suggestion.title.localizedCaseInsensitiveContains("Agent"))
        let shouldFocusComposer = EmptyChatStarterCoordinator.apply(suggestion, to: store)

        XCTAssertTrue(shouldFocusComposer)
        XCTAssertEqual(store.selectedModel, ModelOption.ironclawMobileModelID)
        XCTAssertTrue(store.draft.hasPrefix("Draft an Agent mission"))
    }

    // MARK: - Reborn run completion (SSE projection + timeline), grounded in
    // payloads captured verbatim from a live `ironclaw-reborn serve`.

    func testIronclawRunPhaseMapsRebornProjectionStatuses() {
        XCTAssertEqual(IronclawAPI.runPhaseLabelForTesting(status: "completed"), "completed")
        XCTAssertEqual(IronclawAPI.runPhaseLabelForTesting(status: "Completed"), "completed")
        XCTAssertEqual(IronclawAPI.runPhaseLabelForTesting(status: "queued"), "running")
        XCTAssertEqual(IronclawAPI.runPhaseLabelForTesting(status: "running"), "running")
        XCTAssertEqual(IronclawAPI.runPhaseLabelForTesting(status: "failed"), "failed")
        XCTAssertEqual(IronclawAPI.runPhaseLabelForTesting(status: "recovery_required"), "failed")
        XCTAssertEqual(IronclawAPI.runPhaseLabelForTesting(status: "cancelled"), "cancelled")
        XCTAssertEqual(IronclawAPI.runPhaseLabelForTesting(status: "blocked_approval"), "blocked")
        XCTAssertEqual(IronclawAPI.runPhaseLabelForTesting(status: nil), "running")
    }

    func testIronclawProjectionFrameDecodesRunStatusFromRebornStream() throws {
        let data = Data(#"{"cursor":"opaque","type":"projection_update","state":{"thread_id":"0cea4249-3086-54c5-9430-007ebe88075f","items":[{"run_status":{"run_id":"2a7697a4-bb6e-43d8-8861-5f7a55c24d0f","status":"completed"}}]}}"#.utf8)

        let frame = try JSONDecoder().decode(IronclawProjectionFrame.self, from: data)
        XCTAssertEqual(frame.type, "projection_update")
        let runStatus = try XCTUnwrap(frame.state?.items?.first?.runStatus)
        XCTAssertEqual(runStatus.runID, "2a7697a4-bb6e-43d8-8861-5f7a55c24d0f")
        XCTAssertEqual(IronclawAPI.runPhaseLabelForTesting(status: runStatus.status), "completed")
    }

    func testIronclawKeepAliveAndSnapshotFramesDecodeWithoutRunStatus() throws {
        let keepAlive = try JSONDecoder().decode(IronclawProjectionFrame.self, from: Data(#"{"type":"keep_alive"}"#.utf8))
        XCTAssertEqual(keepAlive.type, "keep_alive")
        XCTAssertNil(keepAlive.state)
    }

    func testIronclawTimelineScopesAssistantAnswerToRun() throws {
        let data = Data(#"{"thread":{"thread_id":"t"},"messages":[{"message_id":"m1","kind":"user","turn_run_id":"630d4b3c-2a62-4646-bf54-81810b27af1a","content":"hi"},{"message_id":"m2","kind":"assistant","status":"finalized","turn_run_id":"630d4b3c-2a62-4646-bf54-81810b27af1a","content":"Hello from the other side of the terminal."}],"summary_artifacts":[]}"#.utf8)

        XCTAssertEqual(
            try IronclawAPI.assistantTextForTesting(timeline: data, runID: "630d4b3c-2a62-4646-bf54-81810b27af1a"),
            "Hello from the other side of the terminal."
        )
        // A different run id must not pick up this thread's prior answer.
        XCTAssertNil(try IronclawAPI.assistantTextForTesting(timeline: data, runID: "no-such-run"))
    }

    /// End-to-end check of the reborn agent route through IronclawAPI's SSE+timeline
    /// path against a live `ironclaw-reborn serve`. Skips unless both env vars are
    /// set, so the normal suite is unaffected.
    func testRebornAgentRouteReturnsAnswerLive() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let baseURL = env["IRONCLAW_REBORN_BASE_URL"],
              !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let token = env["IRONCLAW_REBORN_TOKEN"],
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XCTSkip("Live reborn test: set IRONCLAW_REBORN_BASE_URL + IRONCLAW_REBORN_TOKEN.")
        }

        final class Sink: @unchecked Sendable {
            var answer = ""
            var failure: String?
        }
        let sink = Sink()
        let api = IronclawAPI()
        let settings = IronclawSettings(isEnabled: true, baseURL: baseURL, threadID: "")

        try await api.streamPrompt(
            prompt: "Reply with exactly one short sentence: hello from the iOS reborn integration test.",
            attachments: [],
            settings: settings,
            authToken: token
        ) { event in
            switch event {
            case let .itemDone(text): sink.answer += text ?? ""
            case let .failed(message): sink.failure = message
            default: break
            }
        }

        XCTAssertNil(sink.failure, "reborn agent send reported failure: \(sink.failure ?? "")")
        XCTAssertFalse(
            sink.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "reborn agent returned no answer text"
        )
    }

    /// Deterministic end-to-end of the reborn agent flow (createThread -> send ->
    /// SSE projection -> timeline -> answer) against a stubbed URLProtocol — no
    /// live server or token needed. Locks in the SSE+timeline completion path.
    func testRebornAgentFlowEndToEndStubbed() async throws {
        URLProtocol.registerClass(RebornStubURLProtocol.self)
        defer { URLProtocol.unregisterClass(RebornStubURLProtocol.self) }

        final class Sink: @unchecked Sendable {
            var answer = ""
            var failure: String?
        }
        let sink = Sink()
        let api = IronclawAPI()
        let settings = IronclawSettings(isEnabled: true, baseURL: "https://dangwalvaidy.family/reborn", threadID: "")

        try await api.streamPrompt(
            prompt: "hi",
            attachments: [],
            settings: settings,
            authToken: "stub-token"
        ) { event in
            switch event {
            case let .itemDone(text): sink.answer += text ?? ""
            case let .failed(message): sink.failure = message
            default: break
            }
        }

        XCTAssertNil(sink.failure, "stubbed reborn flow failed: \(sink.failure ?? "")")
        XCTAssertEqual(
            sink.answer.trimmingCharacters(in: .whitespacesAndNewlines),
            "Hello from the stub."
        )
    }
}

/// URLProtocol that stubs the reborn WebChat v2 endpoints (threads / messages /
/// events / timeline) so the full agent flow can be exercised offline.
private final class RebornStubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "dangwalvaidy.family"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let path = url.path
        let method = request.httpMethod ?? "GET"
        let contentType: String
        let body: String
        if method == "POST", path.hasSuffix("/threads") {
            contentType = "application/json"
            body = #"{"thread":{"thread_id":"t1"}}"#
        } else if method == "POST", path.hasSuffix("/messages") {
            contentType = "application/json"
            body = #"{"outcome":"submitted","run_id":"r1","status":"Queued"}"#
        } else if path.hasSuffix("/events") {
            contentType = "text/event-stream"
            body = "event: projection_update\ndata: {\"type\":\"projection_update\",\"state\":{\"items\":[{\"run_status\":{\"run_id\":\"r1\",\"status\":\"completed\"}}]}}\n\n"
        } else if path.hasSuffix("/timeline") {
            contentType = "application/json"
            body = #"{"messages":[{"kind":"assistant","turn_run_id":"r1","content":"Hello from the stub."}]}"#
        } else {
            contentType = "application/json"
            body = "{}"
        }
        if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType]) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
