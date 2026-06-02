import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testAppSetupPlanUsesHostedIronclawWhenMobileRuntimeIsUnavailable() {
        let profile = UserSetupProfile(
            useCase: .buildAgents,
            contextStyle: .project,
            wantsWeb: false,
            wantsIronclaw: true,
            wantsCouncil: false,
            useCases: [.buildAgents],
            experienceMode: .power
        )
        let readiness = AppSetupReadinessSnapshot(
            modelCatalogLoaded: true,
            privateModelAvailable: true,
            defaultCouncilModelCount: 3,
            ironclawMobileAvailable: false,
            hostedIronclawAvailable: true,
            nearCloudKeyConfigured: false
        )

        let plan = AppSetupPlan(profile: profile, readiness: readiness)

        XCTAssertEqual(plan.modelRoute, .ironclaw)
        XCTAssertEqual(plan.expectedRouteModelIDs, [ModelOption.ironclawModelID])
        XCTAssertEqual(plan.expectedFirstAction, "Open Hosted IronClaw")
        XCTAssertEqual(plan.readinessStatus, "Hosted IronClaw is ready; mobile runtime is unavailable.")
        XCTAssertEqual(plan.routeDetailContent?.summary, "Hosted IronClaw · sends work outside this phone.")
    }

    func testRoutePlannerClassifiesModelRoutesOutsideChatStore() {
        XCTAssertEqual(RoutePlanner.routeKind(forModelID: ModelOption.ironclawMobileModelID), .ironclawMobile)
        XCTAssertEqual(RoutePlanner.routeKind(forModelID: ModelOption.ironclawModelID), .ironclawHosted)
        XCTAssertEqual(RoutePlanner.routeKind(forModelID: ModelOption.nearCloudModelID(for: "provider/current-model")), .nearCloud)
        XCTAssertEqual(RoutePlanner.routeKind(forModelID: ModelOption.nearCloudModelID(for: "openai/gpt-5.5")), .nearCloud)
        XCTAssertEqual(RoutePlanner.routeKind(forModelID: "zai-org/GLM-5.1-FP8"), .nearPrivate)
    }

    func testRouteDisclosureCopyDistinguishesPrivateCloudAndIronclaw() {
        XCTAssertEqual(ChatRouteKind.nearPrivate.disclosureTitle, "NEAR Private")
        XCTAssertTrue(ChatRouteKind.nearPrivate.disclosureBadge.localizedCaseInsensitiveContains("proof"))
        XCTAssertEqual(ChatRouteKind.nearCloud.disclosureTitle, "NEAR AI Cloud")
        XCTAssertTrue(ChatRouteKind.nearCloud.disclosureBadge.localizedCaseInsensitiveContains("external"))
        XCTAssertEqual(ChatRouteKind.ironclawHosted.disclosureTitle, "Hosted IronClaw")
        XCTAssertEqual(ChatRouteKind.ironclawHosted.disclosureBadge, "Agent connection")
    }

    func testRouteReadinessBlocksHostedIronclawWithoutUsableEndpoint() {
        let issue = RoutePlanner.routeReadinessIssue(
            selectedModelID: ModelOption.ironclawModelID,
            requestedCouncilModelIDs: [],
            isCouncilRequested: false,
            nearCloudKeyConfigured: true,
            hostedIronclawEndpointUsable: false,
            hostedIronclawEndpointMessage: "Use a hosted HTTPS IronClaw endpoint."
        )

        XCTAssertEqual(issue?.route, .hostedIronclaw)
        XCTAssertEqual(issue?.recoveryAction, .configureIronClawEndpoint)
        XCTAssertTrue(issue?.message.contains("hosted HTTPS IronClaw endpoint") == true)
    }


    @MainActor
    func testHostedIronclawDisabledEndpointBlocksSend() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.ironclawSettings = IronclawSettings(
            isEnabled: false,
            baseURL: "https://agent.example.com",
            threadID: ""
        )
        store.selectModel(ModelOption.ironclawModelID)
        store.draft = "Run the repo tests"

        store.sendDraft()

        XCTAssertEqual(store.routeReadinessIssue?.route, .hostedIronclaw)
        XCTAssertEqual(store.routeReadinessIssue?.recoveryAction, .configureIronClawEndpoint)
        XCTAssertTrue(store.routeReadinessIssue?.message.contains("Turn on Hosted IronClaw") == true)
        XCTAssertEqual(store.draft, "Run the repo tests")
        XCTAssertFalse(store.isStreaming)
    }

    func testHomeInboxSectionPlanRoutesVisibleSectionsByFilter() {
        let all = HomeInboxSectionPlan(
            selectedFilter: .all,
            searchQuery: "",
            activeConversationCount: 2,
            activeProjectCount: 1,
            projectContextMatchCount: 1,
            sharedWithMeCount: 3,
            archivedConversationCount: 4,
            archivedProjectCount: 1
        )

        XCTAssertTrue(all.showsWorkboard)
        XCTAssertTrue(all.showsProjectContext)
        XCTAssertTrue(all.showsProjects)
        XCTAssertTrue(all.showsConversations)
        XCTAssertFalse(all.showsSharedWithMe)
        XCTAssertFalse(all.showsArchivedConversations)
        XCTAssertEqual(all.filterCounts[.all] ?? -1, 4)

        let shared = HomeInboxSectionPlan(
            selectedFilter: .shared,
            searchQuery: "",
            activeConversationCount: 2,
            activeProjectCount: 1,
            projectContextMatchCount: 1,
            sharedWithMeCount: 3,
            archivedConversationCount: 4,
            archivedProjectCount: 1
        )

        XCTAssertFalse(shared.showsWorkboard)
        XCTAssertFalse(shared.showsConversations)
        XCTAssertTrue(shared.showsSharedWithMe)
        XCTAssertFalse(shared.showsArchivedProjects)
        XCTAssertEqual(shared.filterCounts[.shared] ?? -1, 3)

        let archived = HomeInboxSectionPlan(
            selectedFilter: .archived,
            searchQuery: "",
            activeConversationCount: 2,
            activeProjectCount: 1,
            projectContextMatchCount: 1,
            sharedWithMeCount: 3,
            archivedConversationCount: 4,
            archivedProjectCount: 1
        )

        XCTAssertFalse(archived.showsWorkboard)
        XCTAssertFalse(archived.showsSharedWithMe)
        XCTAssertTrue(archived.showsArchivedProjects)
        XCTAssertTrue(archived.showsArchivedConversations)
        XCTAssertEqual(archived.filterCounts[.archived] ?? -1, 5)
    }

    func testAppSetupPlanDoesNotDescribeIronclawMobileAsHostedBridge() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]
        profile.wantsIronclaw = true
        profile.wantsCouncil = false

        let plan = AppSetupPlan(profile: profile, readiness: .optimistic)
        let summary = plan.routeDetailContent?.summary ?? ""

        XCTAssertEqual(plan.modelRoute, .ironclaw)
        XCTAssertEqual(plan.expectedRouteModelIDs, [ModelOption.ironclawMobileModelID])
        XCTAssertTrue(summary.contains("Phone Agent route"))
        XCTAssertTrue(summary.contains("outside NEAR Private proof"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("hosted bridge"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("endpoint"))
    }

    func testSetupRestorePlannerFlagsRouteDrift() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research]
        profile.wantsCouncil = true

        let plan = AppSetupPlan(profile: profile, readiness: .optimistic)
        let runtime = SetupRuntimeSnapshot(
            modelRoute: .privateModel,
            focusMode: plan.focusMode,
            webSearchEnabled: profile.wantsWeb,
            researchModeEnabled: true,
            selectedProjectName: plan.starterProjectName
        )

        let restoreState = SetupRestorePlanner.evaluate(profile: profile, plan: plan, runtime: runtime)

        XCTAssertTrue(restoreState.needsRestore)
        XCTAssertEqual(restoreState.summaryText, "Current route changed. Restore saved setup to return to your saved route.")
        XCTAssertEqual(
            restoreState.differences,
            [SetupRestoreDifference(title: "Route", savedValue: "Council", currentValue: "Private model")]
        )
    }

    func testSetupRestorePlannerFlagsHostedIronclawDriftWithinAgentRoute() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]
        profile.contextStyle = .project
        profile.wantsIronclaw = true

        let plan = AppSetupPlan(
            profile: profile,
            readiness: .optimistic,
            routeDefaults: SetupRouteDefaults(
                privateModelID: "zai-org/GLM-5.1-FP8",
                councilModelIDs: [],
                ironclawMobileModelID: ModelOption.ironclawMobileModelID
            )
        )
        let runtime = SetupRuntimeSnapshot(
            modelRoute: plan.modelRoute,
            focusMode: plan.focusMode,
            webSearchEnabled: profile.wantsWeb,
            researchModeEnabled: false,
            selectedProjectName: plan.starterProjectName,
            selectedModelID: ModelOption.ironclawModelID
        )

        let restoreState = SetupRestorePlanner.evaluate(profile: profile, plan: plan, runtime: runtime)

        XCTAssertTrue(restoreState.needsRestore)
        XCTAssertEqual(
            restoreState.summaryText,
            "Current agent route changed. Restore saved setup to return to IronClaw Mobile."
        )
        XCTAssertEqual(
            restoreState.differences,
            [SetupRestoreDifference(title: "Agent route", savedValue: "IronClaw Mobile", currentValue: "Hosted IronClaw")]
        )
    }

    func testUserSetupStoragePersistsRouteDefaults() throws {
        let suiteName = "setup-route-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let accountID = "user:setup-route-defaults"

        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research]
        profile.wantsCouncil = true
        profile.routeDefaults = SetupRouteDefaults(
            privateModelID: " moonshotai/kimi-k2.6 ",
            councilModelIDs: [
                "zai-org/GLM-5.1-FP8",
                "moonshotai/kimi-k2.6",
                "zai-org/GLM-5.1-FP8"
            ],
            ironclawMobileModelID: " \(ModelOption.ironclawMobileModelID) "
        )

        UserSetupStorage.save(profile, for: accountID, defaults: defaults)

        let loaded = try XCTUnwrap(UserSetupStorage.load(for: accountID, defaults: defaults))
        XCTAssertEqual(
            loaded.routeDefaults,
            SetupRouteDefaults(
                privateModelID: "moonshotai/kimi-k2.6",
                councilModelIDs: ["zai-org/GLM-5.1-FP8", "moonshotai/kimi-k2.6"],
                ironclawMobileModelID: ModelOption.ironclawMobileModelID
            )
        )
    }

    func testDeprecatedPickerHidesLegacyRoutesButKeepsCurrentCloudChoices() {
        let hiddenCloud = [
            "openai/gpt-5.4",
            "openai/gpt-5.1",
            "google/gemini-2.5-flash",
            "anthropic/claude-sonnet-4-5",
            "anthropic/claude-haiku-4-5",
            "openai/o3"
        ].map { ModelOption(modelID: ModelOption.nearCloudModelID(for: $0), publicModel: true, metadata: nil) }
        let visibleCloud = [
            "qwen/qwen3-235b-a22b-thinking-2507",
            "moonshotai/kimi-k2-instruct",
            "zai-org/glm-4.5",
            "openai/gpt-oss-120b"
        ].map { ModelOption(modelID: ModelOption.nearCloudModelID(for: $0), publicModel: true, metadata: nil) }

        XCTAssertTrue(hiddenCloud.allSatisfy(\.isDeprecatedPickerModel))
        XCTAssertFalse(visibleCloud.contains(where: \.isDeprecatedPickerModel))
    }

    func testHostedIronclawIsDiscoverableAsAgentRoute() {
        let hosted = ModelOption(modelID: ModelOption.ironclawModelID, publicModel: true, metadata: nil)

        XCTAssertEqual(hosted.displayName, "Hosted IronClaw")
        XCTAssertTrue(hosted.isIronclawHostedModel)
        XCTAssertFalse(hosted.isDeprecatedPickerModel)
    }

    func testHostedAutoRouteRequiresHandoffEligibleModelAfterRouting() {
        let prompt = "Please review the repo, inspect the Swift files, and run tests."
        let routedModel = RoutePlanner.modelAfterHostedAutoRoute(
            selectedModelID: ChatStore.defaultModelID,
            text: prompt,
            hostedIronclawAvailable: true
        )

        XCTAssertTrue(RoutePlanner.promptNeedsRemoteWorkstation(prompt))
        XCTAssertEqual(routedModel, ModelOption.ironclawModelID)
    }

    func testHostedAutoRouteDoesNotTriggerWhenUserForbidsToolExecution() {
        let prompts = [
            "Review this repo and tell me how to test it, but do not run tools.",
            "Don't run tests; just explain how I should test this Xcode project.",
            "Give me a plan for this codebase. No shell, no terminal, no edits."
        ]

        for prompt in prompts {
            XCTAssertFalse(RoutePlanner.promptNeedsRemoteWorkstation(prompt), prompt)
            XCTAssertEqual(
                RoutePlanner.modelAfterHostedAutoRoute(
                    selectedModelID: ChatStore.defaultModelID,
                    text: prompt,
                    hostedIronclawAvailable: true
                ),
                ChatStore.defaultModelID,
                prompt
            )
        }
    }

    func testSourceRoutingSemanticsNearPrivateSeparatesLinksFromNativeWebTool() {
        let autoDefault = RoutePlanner.sourceRoutingSemantics(
            sourceMode: .auto,
            researchModeEnabled: false,
            webSearchEnabled: false,
            route: .nearPrivate
        )
        XCTAssertEqual(autoDefault.modelNativeWebToolPolicy, .whenFreshRequested)
        XCTAssertEqual(autoDefault.appWebGroundingPolicy, .never)
        XCTAssertTrue(autoDefault.attachesSavedLinkSourcePack)
        XCTAssertTrue(autoDefault.attachesProjectFileSourcePack)

        let links = RoutePlanner.sourceRoutingSemantics(
            sourceMode: .links,
            researchModeEnabled: false,
            webSearchEnabled: true,
            route: .nearPrivate
        )
        XCTAssertEqual(links.focus, .links)
        XCTAssertEqual(links.modelNativeWebToolPolicy, .whenFreshRequested)
        XCTAssertEqual(links.appWebGroundingPolicy, .never)
        XCTAssertTrue(links.attachesSavedLinkSourcePack)
        XCTAssertFalse(links.attachesProjectFileSourcePack)
        XCTAssertTrue(links.attachesPromptFiles)
        XCTAssertFalse(links.modelNativeWebToolEnabledByDefault)

        let web = RoutePlanner.sourceRoutingSemantics(
            sourceMode: .web,
            researchModeEnabled: false,
            webSearchEnabled: true,
            route: .nearPrivate
        )
        XCTAssertEqual(web.focus, .web)
        XCTAssertEqual(web.modelNativeWebToolPolicy, .always)
        XCTAssertFalse(web.attachesSavedLinkSourcePack)
        XCTAssertFalse(web.attachesProjectFileSourcePack)
        XCTAssertTrue(web.attachesPromptFiles)
    }

    func testAskOrchestratorRequestsCloudKeyWithoutChangingSelectedRoute() {
        let decision = AskOrchestrator.decide(
            AskOrchestrator.Input(
                prompt: "Use latest sources",
                selectedRoute: .nearCloud,
                hasProjectContext: false,
                hasPromptAttachments: false,
                nearCloudKeyConfigured: false,
                hostedAgentAvailable: false,
                councilAvailable: false,
                councilActive: false
            )
        )

        XCTAssertEqual(decision.route, .nearCloud)
        XCTAssertEqual(decision.failurePlan, .requestCloudKey)
        XCTAssertEqual(decision.proofState, .unverified)
    }

    func testSourceRoutingSemanticsResearchIsSingleFocusAcrossSourceModes() {
        let research = RoutePlanner.sourceRoutingSemantics(
            sourceMode: .files,
            researchModeEnabled: true,
            webSearchEnabled: false,
            route: .nearPrivate
        )
        XCTAssertEqual(research.focus, .research)
        XCTAssertTrue(research.isResearch)
        XCTAssertEqual(research.modelNativeWebToolPolicy, .always)
        XCTAssertTrue(research.attachesSavedLinkSourcePack)
        XCTAssertTrue(research.attachesProjectFileSourcePack)
        XCTAssertTrue(research.attachesPromptFiles)
    }

    func testSourceRoutingSemanticsIronclawMobileAndHostedRoutes() {
        XCTAssertEqual(ChatStore.routeKind(forModelID: ModelOption.ironclawMobileModelID), .ironclawMobile)
        XCTAssertEqual(ChatStore.routeKind(forModelID: ModelOption.ironclawModelID), .ironclawHosted)
        XCTAssertEqual(ChatStore.routeKind(forModelID: ModelOption.nearCloudModelID(for: "provider/current-model")), .nearCloud)
        XCTAssertEqual(ChatStore.routeKind(forModelID: ModelOption.nearCloudModelID(for: "openai/gpt-5.5")), .nearCloud)
        XCTAssertEqual(ChatStore.routeKind(forModelID: "zai-org/GLM-5.1-FP8"), .nearPrivate)

        let mobileResearch = RoutePlanner.sourceRoutingSemantics(
            sourceMode: .auto,
            researchModeEnabled: true,
            webSearchEnabled: false,
            route: .ironclawMobile
        )
        XCTAssertEqual(mobileResearch.modelNativeWebToolPolicy, .always)
        XCTAssertEqual(mobileResearch.appWebGroundingPolicy, .always)
        XCTAssertTrue(mobileResearch.attachesProjectFileSourcePack)
        XCTAssertTrue(mobileResearch.attachesSavedLinkSourcePack)

        let hostedResearch = RoutePlanner.sourceRoutingSemantics(
            sourceMode: .auto,
            researchModeEnabled: true,
            webSearchEnabled: false,
            route: .ironclawHosted
        )
        XCTAssertEqual(hostedResearch.modelNativeWebToolPolicy, .never)
        XCTAssertEqual(hostedResearch.appWebGroundingPolicy, .always)
        XCTAssertTrue(hostedResearch.attachesProjectFileSourcePack)
        XCTAssertTrue(hostedResearch.attachesSavedLinkSourcePack)
    }

    func testLiveWebRoutingCoversDeepResearchPrompts() {
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb("Deep research the latest Claude Code changes with citations."))
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb("Look up source-backed pricing for Rolex GMT Master II as of today."))
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb("Investigate current FDA supplement recalls from sources."))
        XCTAssertFalse(RoutePlanner.promptNeedsLiveWeb("Write a poem about focus."))
    }

    func testRoutePlannerDetectsCouncilPromptsWithoutChatStore() {
        XCTAssertTrue(RoutePlanner.promptRequestsCouncil("Ask multiple models and synthesize a consensus answer."))
        XCTAssertTrue(RoutePlanner.promptRequestsCouncil("Red team these model responses and compare the answers."))
        XCTAssertFalse(RoutePlanner.promptRequestsCouncil("Summarize this source in one paragraph."))
    }


    @MainActor
    func testSendDraftLeavesUnrecognizedPromptToNormalRouting() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.draft = "write me a haiku about the sea"

        store.sendDraft()

        // No QuickIntent match: the local fast-path does not consume the turn,
        // so no local user/assistant pair is synthesized here.
        XCTAssertTrue(store.messages.isEmpty)
    }

    func testEmptyChatChipVisibleLabelDisclosesRouteSideEffect() {
        let suggestions = EmptyChatStarterPlanner.suggestions(
            projectName: nil,
            isCouncilModeEnabled: false,
            councilAvailable: true,
            routeKind: .nearPrivate,
            agentAvailable: true
        )
        let research = suggestions.first { $0.action == .research }
        let agent = suggestions.first { $0.action == .agent }

        XCTAssertTrue(research?.title.localizedCaseInsensitiveContains("Web") == true)
        XCTAssertTrue(agent?.title.localizedCaseInsensitiveContains("Agent") == true)
    }

    func testEmptyChatMutatingSuggestionsDiscloseVisibleRouteOrModeChange() {
        let cases: [(name: String, suggestions: [EmptyChatStarterSuggestion])] = [
            (
                "home-agent",
                EmptyChatStarterPlanner.suggestions(
                    projectName: nil,
                    isCouncilModeEnabled: false,
                    councilAvailable: true,
                    routeKind: .nearPrivate,
                    agentAvailable: true
                )
            ),
            (
                "home-council",
                EmptyChatStarterPlanner.suggestions(
                    projectName: nil,
                    isCouncilModeEnabled: false,
                    councilAvailable: true,
                    routeKind: .nearPrivate,
                    agentAvailable: false
                )
            ),
            (
                "project-agent",
                EmptyChatStarterPlanner.suggestions(
                    projectName: "Launch",
                    isCouncilModeEnabled: false,
                    councilAvailable: true,
                    routeKind: .nearCloud,
                    agentAvailable: true
                )
            ),
            (
                "project-council",
                EmptyChatStarterPlanner.suggestions(
                    projectName: "Launch",
                    isCouncilModeEnabled: false,
                    councilAvailable: true,
                    routeKind: .nearPrivate,
                    agentAvailable: false
                )
            )
        ]

        for testCase in cases {
            for suggestion in testCase.suggestions {
                switch suggestion.action {
                case .research:
                    XCTAssertTrue(suggestion.title.localizedCaseInsensitiveContains("Web"), "\(testCase.name): \(suggestion.title)")
                case .project:
                    XCTAssertTrue(
                        suggestion.title.localizedCaseInsensitiveContains("Files") ||
                            suggestion.title.localizedCaseInsensitiveContains("Project"),
                        "\(testCase.name): \(suggestion.title)"
                    )
                case .council:
                    XCTAssertTrue(suggestion.title.localizedCaseInsensitiveContains("Council"), "\(testCase.name): \(suggestion.title)")
                case .agent:
                    XCTAssertTrue(suggestion.title.localizedCaseInsensitiveContains("Agent"), "\(testCase.name): \(suggestion.title)")
                case .draft, .trust:
                    continue
                }
            }
        }
    }
}
