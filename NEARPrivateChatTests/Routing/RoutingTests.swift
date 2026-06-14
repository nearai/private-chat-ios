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
            "openai/o3",
            "openai/gpt-oss-120b"
        ].map { ModelOption(modelID: ModelOption.nearCloudModelID(for: $0), publicModel: true, metadata: nil) }
        let visibleCloud = [
            "qwen/qwen3-235b-a22b-thinking-2507",
            "moonshotai/kimi-k2-instruct",
            "zai-org/glm-4.5"
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

    func testHostedAutoRouteDoesNotTriggerForCurrentEventsResearch() {
        let prompts = [
            "Using live web sources, check today's reporting on SpaceX IPO or private-market news and the latest Iran conflict developments. Separate confirmed facts from uncertainty and cite sources.",
            "Give me the latest reporting on GitHub Copilot pricing and developer tool competition with sources.",
            "Investigate current Apple Vision Pro release-date rumors and summarize the source-backed uncertainty.",
            "Research repo-market pricing for a Rolex GMT Master II today and cite current sources."
        ]

        for prompt in prompts {
            XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb(prompt), prompt)
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
        XCTAssertEqual(web.appWebGroundingPolicy, .always)
        XCTAssertFalse(web.attachesSavedLinkSourcePack)
        XCTAssertFalse(web.attachesProjectFileSourcePack)
        XCTAssertTrue(web.attachesPromptFiles)
    }

    func testSourceRoutingSemanticsNearCloudAutoKeepsCloudRouteForFreshPrompts() {
        let cloudAuto = RoutePlanner.sourceRoutingSemantics(
            sourceMode: .auto,
            researchModeEnabled: false,
            webSearchEnabled: false,
            route: .nearCloud
        )

        XCTAssertEqual(cloudAuto.modelNativeWebToolPolicy, .never)
        XCTAssertEqual(cloudAuto.appWebGroundingPolicy, .whenFreshRequested)
        XCTAssertTrue(cloudAuto.attachesSavedLinkSourcePack)
        XCTAssertTrue(cloudAuto.attachesProjectFileSourcePack)

        XCTAssertFalse(RoutePlanner.promptNeedsLiveWeb("Do not use web. Answer from this chat only."))
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

    func testAskOrchestratorTreatsCurrentYearAsTimeSensitiveNotAStaleLiteral() {
        // The recency-year cue is derived from the calendar, so a prompt naming
        // the current year routes web on the auto path without a hardcoded list
        // that would go stale each January.
        let currentYear = Calendar.current.component(.year, from: Date())
        let decision = AskOrchestrator.decide(
            AskOrchestrator.Input(
                prompt: "What happened in \(currentYear)?",
                selectedRoute: .nearPrivate,
                hasProjectContext: false,
                hasPromptAttachments: false,
                nearCloudKeyConfigured: true,
                hostedAgentAvailable: false,
                councilAvailable: false,
                councilActive: false
            )
        )
        XCTAssertTrue(decision.tools.contains(.web), "Current year should read as time-sensitive.")
    }

    func testPrivateLiveWebUsesAppGroundingBeforeNativeWebTool() {
        let privateWeb = RoutePlanner.sourceRoutingSemantics(
            sourceMode: .web,
            researchModeEnabled: false,
            webSearchEnabled: true,
            route: .nearPrivate
        )

        XCTAssertTrue(ChatWebGroundingDecision.shouldUseAppGrounding(
            route: .nearPrivate,
            semantics: privateWeb,
            benefitsFromSearch: true,
            needsFreshFacts: true,
            privacyBlocksWeb: false,
            promptNeedsRemoteWorkstation: false
        ))
        XCTAssertFalse(ChatWebGroundingDecision.shouldEnableNativeWebTool(
            semantics: privateWeb,
            benefitsFromSearch: true,
            needsFreshFacts: true,
            privacyBlocksWeb: false,
            appWebContextPresent: true
        ))
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
        XCTAssertEqual(research.appWebGroundingPolicy, .always)
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

    func testWebGroundingDecisionDoesNotDoubleRunAppAndNativeWebSearch() {
        let mobileResearch = RoutePlanner.sourceRoutingSemantics(
            sourceMode: .auto,
            researchModeEnabled: true,
            webSearchEnabled: false,
            route: .ironclawMobile
        )

        XCTAssertFalse(ChatWebGroundingDecision.shouldUseAppGrounding(
            route: .ironclawMobile,
            semantics: mobileResearch,
            benefitsFromSearch: true,
            needsFreshFacts: true,
            privacyBlocksWeb: false,
            promptNeedsRemoteWorkstation: false
        ))
        XCTAssertTrue(ChatWebGroundingDecision.shouldEnableNativeWebTool(
            semantics: mobileResearch,
            benefitsFromSearch: true,
            needsFreshFacts: true,
            privacyBlocksWeb: false
        ))
        XCTAssertFalse(ChatWebGroundingDecision.shouldEnableNativeWebTool(
            semantics: mobileResearch,
            benefitsFromSearch: true,
            needsFreshFacts: true,
            privacyBlocksWeb: false,
            appWebContextPresent: true
        ))

        let cloudWeb = RoutePlanner.sourceRoutingSemantics(
            sourceMode: .web,
            researchModeEnabled: false,
            webSearchEnabled: true,
            route: .nearCloud
        )
        XCTAssertTrue(ChatWebGroundingDecision.shouldUseAppGrounding(
            route: .nearCloud,
            semantics: cloudWeb,
            benefitsFromSearch: true,
            needsFreshFacts: true,
            privacyBlocksWeb: false,
            promptNeedsRemoteWorkstation: false
        ))
        XCTAssertFalse(ChatWebGroundingDecision.shouldEnableNativeWebTool(
            semantics: cloudWeb,
            benefitsFromSearch: true,
            needsFreshFacts: true,
            privacyBlocksWeb: false
        ))
    }

    @MainActor
    func testChatStoreNativeWebRouteDoesNotDoubleRunAppSearch() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.selectedModel = ModelOption.ironclawMobileModelID
        store.sourceMode = .auto
        store.researchModeEnabled = true
        let prompt = "Research the latest NEAR ecosystem news with citations."

        XCTAssertFalse(
            store.shouldUseAppWebGrounding(model: store.selectedModel, prompt: prompt),
            "Native-web routes should not also trigger app-side web grounding."
        )
        XCTAssertTrue(
            store.shouldEnableModelNativeWebTool(model: store.selectedModel, prompt: prompt),
            "The same send decision should leave native web enabled for the model."
        )
        XCTAssertFalse(
            store.shouldEnableModelNativeWebTool(
                model: store.selectedModel,
                prompt: prompt,
                appWebContext: WebGroundingContext(
                    query: "latest NEAR ecosystem news",
                    fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    results: []
                )
            ),
            "If an app web context exists, native web must be disabled to avoid double search."
        )
    }

    func testLiveWebRoutingCoversDeepResearchPrompts() {
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb("Deep research the latest Claude Code changes with citations."))
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb("Look up source-backed pricing for Rolex GMT Master II as of today."))
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb("Investigate current FDA supplement recalls from sources."))
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb("Apple Vision Pro vs Meta Quest 3 price"))
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb("Apple Watch Ultra price"))
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb("compare Apple Watch Ultra and Oura Ring prices"))
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb("Create an AI product release digest every weekday at 8am covering model launches, developer tools, safety updates, and pricing changes."))
        XCTAssertFalse(RoutePlanner.promptNeedsLiveWeb("Write a poem about focus."))
        XCTAssertFalse(RoutePlanner.promptNeedsLiveWeb("Write a paragraph about price elasticity."))
        XCTAssertFalse(RoutePlanner.promptNeedsLiveWeb("Compose a release note from this diff summary."))
    }

    func testAutoSourceDisclosureShowsInferredWebForFreshPrompts() {
        XCTAssertTrue(
            RoutePlanner.shouldDiscloseAutoLiveWeb(
                sourceMode: .auto,
                researchModeEnabled: false,
                prompt: "What is happening in Iran right now? Give a concise sourced update."
            )
        )
        XCTAssertTrue(
            RoutePlanner.shouldDiscloseAutoLiveWeb(
                sourceMode: .auto,
                researchModeEnabled: false,
                prompt: "Look up source-backed pricing for Rolex GMT Master II as of today."
            )
        )
        XCTAssertTrue(
            RoutePlanner.shouldDiscloseAutoLiveWeb(
                sourceMode: .auto,
                researchModeEnabled: false,
                prompt: "Create an AI product release digest every weekday at 8am covering model launches and pricing changes."
            )
        )
        XCTAssertFalse(
            RoutePlanner.shouldDiscloseAutoLiveWeb(
                sourceMode: .auto,
                researchModeEnabled: false,
                prompt: "Do not use web. Summarize this from memory."
            )
        )
        XCTAssertFalse(
            RoutePlanner.shouldDiscloseAutoLiveWeb(
                sourceMode: .web,
                researchModeEnabled: false,
                prompt: "What is happening in Iran right now?"
            )
        )
        XCTAssertFalse(
            RoutePlanner.shouldDiscloseAutoLiveWeb(
                sourceMode: .auto,
                researchModeEnabled: true,
                prompt: "What is happening in Iran right now?"
            )
        )
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

        XCTAssertTrue(research?.title.localizedCaseInsensitiveContains("Research") == true)
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
                    XCTAssertTrue(suggestion.title.localizedCaseInsensitiveContains("Research"), "\(testCase.name): \(suggestion.title)")
                case .project:
                    XCTAssertTrue(
                        suggestion.title.localizedCaseInsensitiveContains("File") ||
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

    func testHostileReviewHundredPlusPromptRoutingMatrix() {
        struct PromptCase {
            let id: String
            let prompt: String
        }
        struct PrivacyCase {
            let id: String
            let prompt: String
            let hasAttachments: Bool
            let expectsFileOnly: Bool
        }

        var executedCaseIDs = Set<String>()
        func record(_ id: String) {
            XCTAssertTrue(executedCaseIDs.insert(id).inserted, "Duplicate hostile case id: \(id)")
        }

        let liveWebTrue: [PromptCase] = [
            PromptCase(id: "HW-001", prompt: "latest pricing for Apple Watch Ultra"),
            PromptCase(id: "HW-002", prompt: "current FDA supplement recalls"),
            PromptCase(id: "HW-003", prompt: "what happened in AI policy today"),
            PromptCase(id: "HW-004", prompt: "what is the NEAR ecosystem doing right now"),
            PromptCase(id: "HW-005", prompt: "summarize this week's SwiftUI release notes"),
            PromptCase(id: "HW-006", prompt: "recent security incidents affecting OAuth apps"),
            PromptCase(id: "HW-007", prompt: "fresh competitor notes for private chat apps"),
            PromptCase(id: "HW-008", prompt: "live token price for Canton Network"),
            PromptCase(id: "HW-009", prompt: "up to date comparison of Vision Pro and Quest 3"),
            PromptCase(id: "HW-010", prompt: "state of Apple Intelligence as of June 2026"),
            PromptCase(id: "HW-011", prompt: "news about NEAR AI this morning"),
            PromptCase(id: "HW-012", prompt: "web search for current AuthSession bugs"),
            PromptCase(id: "HW-013", prompt: "search the web for Xcode 17 test issues"),
            PromptCase(id: "HW-014", prompt: "deep search current App Intents examples"),
            PromptCase(id: "HW-015", prompt: "deep research competitor privacy claims"),
            PromptCase(id: "HW-016", prompt: "research the latest iOS simulator failures"),
            PromptCase(id: "HW-017", prompt: "look up the current Rolex GMT price"),
            PromptCase(id: "HW-018", prompt: "investigate current billing outage reports"),
            PromptCase(id: "HW-019", prompt: "answer from sources about current cloud model pricing"),
            PromptCase(id: "HW-020", prompt: "source-backed comparison of Claude and Gemini today"),
            PromptCase(id: "HW-021", prompt: "browse for the newest SwiftData migration guide"),
            PromptCase(id: "HW-022", prompt: "cite sources for today's crypto market cap"),
            PromptCase(id: "HW-023", prompt: "give citations for recent NEAR grants"),
            PromptCase(id: "HW-024", prompt: "include source links for current App Store rules"),
            PromptCase(id: "HW-025", prompt: "what is the price of a Tesla Model Y"),
            PromptCase(id: "HW-026", prompt: "compare Apple Watch Ultra and Oura Ring prices"),
            PromptCase(id: "HW-027", prompt: "how much is the Vision Pro worth today"),
            PromptCase(id: "HW-028", prompt: "quote for BTC and TSLA"),
            PromptCase(id: "HW-029", prompt: "current exchange rate for EUR to USD"),
            PromptCase(id: "HW-030", prompt: "floor price for Pudgy Penguins"),
            PromptCase(id: "HW-031", prompt: "what are NVIDIA shares trading at"),
            PromptCase(id: "HW-032", prompt: "monitor live SEC crypto enforcement updates")
        ]
        for testCase in liveWebTrue {
            record(testCase.id)
            XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb(testCase.prompt), testCase.id)
        }

        let liveWebFalse: [PromptCase] = [
            PromptCase(id: "HW-033", prompt: "write a poem about focus"),
            PromptCase(id: "HW-034", prompt: "explain price elasticity without examples"),
            PromptCase(id: "HW-035", prompt: "draft a calmer sign-in microcopy variant"),
            PromptCase(id: "HW-036", prompt: "summarize the pasted paragraph"),
            PromptCase(id: "HW-037", prompt: "turn this local note into bullets"),
            PromptCase(id: "HW-038", prompt: "make the tone less defensive"),
            PromptCase(id: "HW-039", prompt: "write a fictional product review"),
            PromptCase(id: "HW-040", prompt: "brainstorm onboarding labels"),
            PromptCase(id: "HW-041", prompt: "explain what a proof report means"),
            PromptCase(id: "HW-042", prompt: "compose a release note from this diff summary"),
            PromptCase(id: "HW-043", prompt: "rewrite this error message in plain English"),
            PromptCase(id: "HW-044", prompt: "what time is it in our roadmap"),
            PromptCase(id: "HW-045", prompt: "forecast product adoption from the pasted table"),
            PromptCase(id: "HW-046", prompt: "tell me why this screen feels busy"),
            PromptCase(id: "HW-047", prompt: "draft a response to a hostile reviewer"),
            PromptCase(id: "HW-048", prompt: "classify these local support tickets"),
            PromptCase(id: "HW-049", prompt: "make a checklist from this meeting note"),
            PromptCase(id: "HW-050", prompt: "explain rate limiting conceptually")
        ]
        for testCase in liveWebFalse {
            record(testCase.id)
            XCTAssertFalse(RoutePlanner.promptNeedsLiveWeb(testCase.prompt), testCase.id)
        }

        let privacyOverrides: [PrivacyCase] = [
            PrivacyCase(id: "HW-051", prompt: "latest FDA recalls, no web, only this file", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-052", prompt: "Use only this spreadsheet and do not browse", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-053", prompt: "No internet: turn the attached file into actions", hasAttachments: true, expectsFileOnly: false),
            PrivacyCase(id: "HW-054", prompt: "Do not go online; use only the attached file", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-055", prompt: "Do not look up current FDA recalls; use this file only", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-056", prompt: "without web, answer from the selected project", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-057", prompt: "no browsing, summarize this pasted text", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-058", prompt: "do not search the web, critique this copy", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-059", prompt: "offline only: rewrite the release note", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-060", prompt: "don't use web; compare these two pasted answers", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-061", prompt: "only the attached file should be used", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-062", prompt: "from this file only, extract risks", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-063", prompt: "attached file only: write test notes", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-064", prompt: "use only attached docs and no internet", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-065", prompt: "only this workbook; do not browse", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-066", prompt: "only this sheet, no cloud research", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-067", prompt: "do not use web, use the conversation only", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-068", prompt: "don't look up anything; use the pasted notes", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-069", prompt: "no web sources; summarize local context", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-070", prompt: "do not browse or cite external pages", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-071", prompt: "use only this attached project export", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-072", prompt: "file only, produce a hostile review checklist", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-073", prompt: "from the attached file only, find contradictions", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-074", prompt: "no internet and no browsing; answer locally", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-153", prompt: "dont browse, use the attached doc only", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-154", prompt: "dont search the web; summarize this note", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-155", prompt: "dont use web for this product review", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-156", prompt: "dont go online, only these files", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-157", prompt: "dont look up fresh facts; answer from the pasted note", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-158", prompt: "no live web, use the PDF only", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-159", prompt: "without live web, use these files only", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-160", prompt: "without internet, critique this copied thread", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-161", prompt: "no online lookups; use the conversation only", hasAttachments: false, expectsFileOnly: false),
            PrivacyCase(id: "HW-162", prompt: "attachments only: extract the decisions", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-163", prompt: "these files only; do not browse", hasAttachments: true, expectsFileOnly: true),
            PrivacyCase(id: "HW-164", prompt: "pdf only, no live web, list the risks", hasAttachments: true, expectsFileOnly: true)
        ]
        for testCase in privacyOverrides {
            record(testCase.id)
            let override = RoutePlanner.promptSourcePrivacyOverride(for: testCase.prompt, hasAttachments: testCase.hasAttachments)
            XCTAssertTrue(override.blocksWeb, testCase.id)
            XCTAssertEqual(override.prefersFileOnly, testCase.expectsFileOnly, testCase.id)
            XCTAssertFalse(RoutePlanner.promptNeedsLiveWeb(testCase.prompt), testCase.id)
        }

        let privateRoutePrompts: [PromptCase] = [
            PromptCase(id: "HW-075", prompt: "keep it private; inspect the repo and run tests"),
            PromptCase(id: "HW-076", prompt: "private only: git status and summarize risks"),
            PromptCase(id: "HW-077", prompt: "stay private while reviewing the repository"),
            PromptCase(id: "HW-078", prompt: "do not use cloud; audit the repo"),
            PromptCase(id: "HW-079", prompt: "don't use cloud for this code review"),
            PromptCase(id: "HW-080", prompt: "no cloud, run the tests in theory only"),
            PromptCase(id: "HW-081", prompt: "no hosted; inspect the SwiftUI code"),
            PromptCase(id: "HW-082", prompt: "do not use hosted; fix the repo"),
            PromptCase(id: "HW-083", prompt: "don't send this to hosted; review the repo"),
            PromptCase(id: "HW-084", prompt: "do not send this to cloud; audit the codebase"),
            PromptCase(id: "HW-085", prompt: "on device only, debug the project plan"),
            PromptCase(id: "HW-086", prompt: "local only, review package.json"),
            PromptCase(id: "HW-087", prompt: "keep this private and do not send to hosted"),
            PromptCase(id: "HW-088", prompt: "do not send this to hosted or cloud; run tests"),
            PromptCase(id: "HW-089", prompt: "keep this private; no hosted workstation"),
            PromptCase(id: "HW-090", prompt: "private only, no cloud, no hosted, inspect the repo"),
            PromptCase(id: "HW-165", prompt: "private route only, review this SwiftUI diff"),
            PromptCase(id: "HW-166", prompt: "NEAR Private only for this account note"),
            PromptCase(id: "HW-167", prompt: "use NEAR Private, not the cloud model"),
            PromptCase(id: "HW-168", prompt: "dont use cloud for these files"),
            PromptCase(id: "HW-169", prompt: "dont send to cloud; audit the code"),
            PromptCase(id: "HW-170", prompt: "do not send to NEAR AI Cloud"),
            PromptCase(id: "HW-171", prompt: "don't send to NEAR AI Cloud; summarize this"),
            PromptCase(id: "HW-172", prompt: "no cloud model should touch this"),
            PromptCase(id: "HW-173", prompt: "no NEAR AI Cloud, keep the private route"),
            PromptCase(id: "HW-174", prompt: "never cloud; review the repository"),
            PromptCase(id: "HW-175", prompt: "not hosted and not cloud for this draft"),
            PromptCase(id: "HW-176", prompt: "stay on NEAR Private while checking the tests")
        ]
        for testCase in privateRoutePrompts {
            record(testCase.id)
            XCTAssertTrue(RoutePlanner.promptSourcePrivacyOverride(for: testCase.prompt).requiresPrivateRoute, testCase.id)
            XCTAssertEqual(
                RoutePlanner.modelAfterHostedAutoRoute(
                    selectedModelID: ChatStore.defaultModelID,
                    text: testCase.prompt,
                    hostedIronclawAvailable: true
                ),
                ChatStore.defaultModelID,
                testCase.id
            )
        }

        let remoteWorkstationTrue: [PromptCase] = [
            PromptCase(id: "HW-091", prompt: "use IronClaw to inspect the repo"),
            PromptCase(id: "HW-092", prompt: "ask IronClaw to run tests"),
            PromptCase(id: "HW-093", prompt: "hosted IronClaw should fix the repo"),
            PromptCase(id: "HW-094", prompt: "IronClaw agent: git status and test"),
            PromptCase(id: "HW-095", prompt: "coding agent, patch the SwiftUI code"),
            PromptCase(id: "HW-096", prompt: "software agent, implement the bug fix"),
            PromptCase(id: "HW-097", prompt: "remote workstation, run xcodebuild"),
            PromptCase(id: "HW-098", prompt: "hosted workstation, inspect package.json"),
            PromptCase(id: "HW-099", prompt: "Agent Mission: audit the repo"),
            PromptCase(id: "HW-100", prompt: "Phone Agent: review the codebase"),
            PromptCase(id: "HW-101", prompt: "run tests for this Xcode project"),
            PromptCase(id: "HW-102", prompt: "git status then summarize changes"),
            PromptCase(id: "HW-103", prompt: "make changes to the repository"),
            PromptCase(id: "HW-104", prompt: "fix the repo and push"),
            PromptCase(id: "HW-105", prompt: "review the repo for regressions"),
            PromptCase(id: "HW-106", prompt: "audit the repo before release"),
            PromptCase(id: "HW-107", prompt: "clone and inspect this GitHub project"),
            PromptCase(id: "HW-108", prompt: "research-to-code this issue"),
            PromptCase(id: "HW-109", prompt: "write software for this feature"),
            PromptCase(id: "HW-110", prompt: "build software from this spec"),
            PromptCase(id: "HW-111", prompt: "debug the Swift package"),
            PromptCase(id: "HW-112", prompt: "open a PR with the fix")
        ]
        for testCase in remoteWorkstationTrue {
            record(testCase.id)
            XCTAssertTrue(RoutePlanner.promptNeedsRemoteWorkstation(testCase.prompt), testCase.id)
            XCTAssertEqual(
                RoutePlanner.modelAfterHostedAutoRoute(
                    selectedModelID: ChatStore.defaultModelID,
                    text: testCase.prompt,
                    hostedIronclawAvailable: true
                ),
                ModelOption.ironclawModelID,
                testCase.id
            )
        }

        let remoteWorkstationFalse: [PromptCase] = [
            PromptCase(id: "HW-113", prompt: "do not run tests; tell me how to test this repo"),
            PromptCase(id: "HW-114", prompt: "don't run tools; review the repo conceptually"),
            PromptCase(id: "HW-115", prompt: "dont execute shell commands for this codebase"),
            PromptCase(id: "HW-116", prompt: "without using tools, explain the Xcode failure"),
            PromptCase(id: "HW-117", prompt: "without running xcodebuild, give me a plan"),
            PromptCase(id: "HW-118", prompt: "no tool use; inspect the pasted git diff"),
            PromptCase(id: "HW-119", prompt: "no tools, summarize this repository description"),
            PromptCase(id: "HW-120", prompt: "no shell; explain how to debug the tests"),
            PromptCase(id: "HW-121", prompt: "no terminal, make a plan for this repo"),
            PromptCase(id: "HW-122", prompt: "do not modify files, review the code"),
            PromptCase(id: "HW-123", prompt: "don't edit the repo; just tell me risks"),
            PromptCase(id: "HW-124", prompt: "do not make changes; walk me through the fix"),
            PromptCase(id: "HW-125", prompt: "just tell me how to run this Xcode project"),
            PromptCase(id: "HW-126", prompt: "explain how to test the Swift code"),
            PromptCase(id: "HW-127", prompt: "give me instructions for checking the repo"),
            PromptCase(id: "HW-128", prompt: "make a plan for the code review")
        ]
        for testCase in remoteWorkstationFalse {
            record(testCase.id)
            XCTAssertFalse(RoutePlanner.promptNeedsRemoteWorkstation(testCase.prompt), testCase.id)
            XCTAssertEqual(
                RoutePlanner.modelAfterHostedAutoRoute(
                    selectedModelID: ChatStore.defaultModelID,
                    text: testCase.prompt,
                    hostedIronclawAvailable: true
                ),
                ChatStore.defaultModelID,
                testCase.id
            )
        }

        let councilTrue: [PromptCase] = [
            PromptCase(id: "HW-129", prompt: "ask multiple models and synthesize consensus"),
            PromptCase(id: "HW-130", prompt: "run multiple models on this answer"),
            PromptCase(id: "HW-131", prompt: "use an LLM Council for this decision"),
            PromptCase(id: "HW-132", prompt: "compare model answers"),
            PromptCase(id: "HW-133", prompt: "give me second opinions from models"),
            PromptCase(id: "HW-134", prompt: "model consensus on this plan"),
            PromptCase(id: "HW-135", prompt: "red team these model responses"),
            PromptCase(id: "HW-136", prompt: "debate these answers across models"),
            PromptCase(id: "HW-137", prompt: "cross-check the responses"),
            PromptCase(id: "HW-138", prompt: "several models should evaluate the prompt"),
            PromptCase(id: "HW-139", prompt: "ask different models for independent takes"),
            PromptCase(id: "HW-140", prompt: "all the models should vote"),
            PromptCase(id: "HW-177", prompt: "use council for this decision"),
            PromptCase(id: "HW-178", prompt: "using council, review the launch plan"),
            PromptCase(id: "HW-179", prompt: "use the council and synthesize the result"),
            PromptCase(id: "HW-180", prompt: "ask the council whether this is shippable"),
            PromptCase(id: "HW-181", prompt: "run the council on this failure mode"),
            PromptCase(id: "HW-182", prompt: "council mode for this release call"),
            PromptCase(id: "HW-183", prompt: "council review of the onboarding flow"),
            PromptCase(id: "HW-184", prompt: "council answer with independent votes")
        ]
        for testCase in councilTrue {
            record(testCase.id)
            XCTAssertTrue(RoutePlanner.promptRequestsCouncil(testCase.prompt), testCase.id)
        }

        let councilFalse: [PromptCase] = [
            PromptCase(id: "HW-141", prompt: "compare these two product screenshots"),
            PromptCase(id: "HW-142", prompt: "contrast the two pricing plans"),
            PromptCase(id: "HW-143", prompt: "red team my launch checklist"),
            PromptCase(id: "HW-144", prompt: "sanity check this paragraph"),
            PromptCase(id: "HW-145", prompt: "give another perspective on my copy"),
            PromptCase(id: "HW-146", prompt: "summarize this source in one paragraph"),
            PromptCase(id: "HW-147", prompt: "debate the tradeoffs in plain English"),
            PromptCase(id: "HW-148", prompt: "compare survey rows in this pasted export"),
            PromptCase(id: "HW-149", prompt: "contrast route labels without changing models"),
            PromptCase(id: "HW-150", prompt: "audit this proof report copy"),
            PromptCase(id: "HW-151", prompt: "review the onboarding copy"),
            PromptCase(id: "HW-152", prompt: "explain the model picker")
        ]
        for testCase in councilFalse {
            record(testCase.id)
            XCTAssertFalse(RoutePlanner.promptRequestsCouncil(testCase.prompt), testCase.id)
        }

        XCTAssertGreaterThanOrEqual(executedCaseIDs.count, 170)
    }

    @MainActor
    func testHostileReviewProductCopyAndRecoveryMatrix() {
        let errorCases: [(id: String, raw: String, expected: String)] = [
            ("HC-001", "Failed to check rate limit.", "Could not verify account usage"),
            ("HC-002", "Access denied", "Access denied by the NEAR Private API"),
            ("HC-003", "HTTP 402 - Payment Required", "Payment or credits required"),
            ("HC-004", "Hosted IronClaw chat route needs a valid IronClaw token", "Agent token is missing or invalid"),
            ("HC-005", "not authenticated", "Sign in to start chatting"),
            ("HC-006", "unauthorized", "Sign in to start chatting")
        ]
        for testCase in errorCases {
            let message = MessageRepository.displayFailureMessage(testCase.raw)
            XCTAssertTrue(message.contains(testCase.expected), testCase.id)
        }

        let stagedPromptCases: [(id: String, prefix: String, draft: String, expected: String)] = [
            ("HC-007", "Plan the next Agent task: ", "run a hostile review", "Plan the next Agent task: run a hostile review"),
            ("HC-008", "Research this with sources: ", "Research this with sources: OAuth failures", "Research this with sources: OAuth failures"),
            ("HC-009", "", "keep my draft", "keep my draft"),
            ("HC-010", "Audit this: ", "", "Audit this:")
        ]
        for testCase in stagedPromptCases {
            XCTAssertEqual(
                EmptyChatStarterCoordinator.stagedPrompt(testCase.prefix, existingDraft: testCase.draft),
                testCase.expected,
                testCase.id
            )
        }

        let store = SecurityStore(attestationAPI: PrivateChatAPI(configuration: .production))
        let agentCopy = store.currentAttestationStatus(
            selectedModelID: ModelOption.ironclawMobileModelID,
            selectedRouteKind: .ironclawMobile,
            isCouncilModeEnabled: false,
            activeCouncilHasExternalRoutes: false
        ).userFacingCopy()
        XCTAssertEqual(agentCopy.badge, "Outside proof", "HC-011")

        let cloudCopy = store.currentAttestationStatus(
            selectedModelID: ModelOption.nearCloudModelID(for: "provider/current"),
            selectedRouteKind: .nearCloud,
            isCouncilModeEnabled: false,
            activeCouncilHasExternalRoutes: false
        ).userFacingCopy()
        XCTAssertEqual(cloudCopy.badge, "Privacy proxy", "HC-012")

        let cloudIssue = RoutePlanner.routeReadinessIssue(
            selectedModelID: ModelOption.nearCloudModelID(for: "provider/current"),
            requestedCouncilModelIDs: [],
            isCouncilRequested: false,
            nearCloudKeyConfigured: false,
            hostedIronclawEndpointUsable: true
        )
        XCTAssertEqual(cloudIssue?.recoveryAction, .addNearCloudKey, "HC-013")
        XCTAssertTrue(cloudIssue?.message.contains("draft") == true, "HC-014")

        let hostedIssue = RoutePlanner.routeReadinessIssue(
            selectedModelID: ModelOption.ironclawModelID,
            requestedCouncilModelIDs: [],
            isCouncilRequested: false,
            nearCloudKeyConfigured: true,
            hostedIronclawEndpointUsable: false,
            hostedIronclawEndpointMessage: "Add a Hosted IronClaw URL."
        )
        XCTAssertEqual(hostedIssue?.recoveryAction, .configureIronClawEndpoint, "HC-015")
        XCTAssertTrue(hostedIssue?.message.contains("draft") == true, "HC-016")
    }
}
