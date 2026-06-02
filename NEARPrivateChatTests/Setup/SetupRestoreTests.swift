import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testSetupRestorePlannerFlagsContextDriftIncludingWebDefaults() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research]
        profile.wantsWeb = true
        profile.contextStyle = .project

        let plan = AppSetupPlan(profile: profile, readiness: .optimistic)
        let runtime = SetupRuntimeSnapshot(
            modelRoute: plan.modelRoute,
            focusMode: plan.focusMode,
            webSearchEnabled: false,
            researchModeEnabled: true,
            selectedProjectName: plan.starterProjectName
        )

        let restoreState = SetupRestorePlanner.evaluate(profile: profile, plan: plan, runtime: runtime)

        XCTAssertTrue(restoreState.needsRestore)
        XCTAssertEqual(
            restoreState.summaryText,
            "Context defaults changed. Restore saved setup to recover your saved web, focus, and research defaults."
        )
        XCTAssertEqual(
            restoreState.differences,
            [SetupRestoreDifference(title: "Web", savedValue: "On", currentValue: "Off")]
        )
    }

    func testSetupRestorePlannerFlagsPrivateModelSelectionDrift() {
        let expectedPrivateModelID = "zai-org/GLM-5.1-FP8"
        let runtimePrivateModelID = "moonshotai/kimi-k2.6"
        let plan = AppSetupPlan(
            profile: .defaults,
            readiness: .optimistic,
            routeDefaults: SetupRouteDefaults(
                privateModelID: expectedPrivateModelID,
                councilModelIDs: [],
                ironclawMobileModelID: ModelOption.ironclawMobileModelID
            )
        )
        let runtime = SetupRuntimeSnapshot(
            modelRoute: plan.modelRoute,
            focusMode: plan.focusMode,
            webSearchEnabled: false,
            researchModeEnabled: false,
            selectedProjectName: plan.starterProjectName,
            selectedModelID: runtimePrivateModelID
        )

        let restoreState = SetupRestorePlanner.evaluate(profile: .defaults, plan: plan, runtime: runtime)

        XCTAssertTrue(restoreState.needsRestore)
        XCTAssertEqual(
            restoreState.summaryText,
            "Current private model changed. Restore saved setup to recover your preferred starter route."
        )
        XCTAssertEqual(
            restoreState.differences,
            [SetupRestoreDifference(title: "Model", savedValue: "GLM 5.1", currentValue: "Kimi K2.6")]
        )
    }

    func testSetupRestorePlannerStaysAlignedWhenRuntimeMatchesSavedSetup() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]
        profile.contextStyle = .project
        profile.wantsIronclaw = true

        let plan = AppSetupPlan(profile: profile, readiness: .optimistic)
        let runtime = SetupRuntimeSnapshot(
            modelRoute: plan.modelRoute,
            focusMode: plan.focusMode,
            webSearchEnabled: profile.wantsWeb,
            researchModeEnabled: false,
            selectedProjectName: plan.starterProjectName
        )

        let restoreState = SetupRestorePlanner.evaluate(profile: profile, plan: plan, runtime: runtime)

        XCTAssertFalse(restoreState.needsRestore)
        XCTAssertEqual(
            restoreState.summaryText,
            "Your saved setup is ready to reopen with the same route and focus defaults."
        )
        XCTAssertTrue(restoreState.differences.isEmpty)
    }

    func testSetupRestorePlannerUsesStarterPromptSummaryWhenGoalExists() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]
        profile.contextStyle = .project
        profile.goalText = "Review the repo and plan the first safe patch."

        let plan = AppSetupPlan(profile: profile, readiness: .optimistic)
        let runtime = SetupRuntimeSnapshot(
            modelRoute: plan.modelRoute,
            focusMode: plan.focusMode,
            webSearchEnabled: profile.wantsWeb,
            researchModeEnabled: false,
            selectedProjectName: plan.starterProjectName
        )

        let restoreState = SetupRestorePlanner.evaluate(profile: profile, plan: plan, runtime: runtime)

        XCTAssertFalse(restoreState.needsRestore)
        XCTAssertEqual(
            restoreState.summaryText,
            "Your saved setup is ready to reopen with the same route, focus, and starter prompt."
        )
        XCTAssertTrue(restoreState.differences.isEmpty)
    }


    @MainActor
    func testApplyingSetupRestoresSavedPrivateModel() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.selectModel("zai-org/GLM-5.1-FP8")

        var profile = UserSetupProfile.defaults
        profile.routeDefaults = SetupRouteDefaults(
            privateModelID: "moonshotai/kimi-k2.6",
            councilModelIDs: [],
            ironclawMobileModelID: ModelOption.ironclawMobileModelID
        )

        store.applySetupProfile(profile)

        XCTAssertEqual(store.selectedModel, "moonshotai/kimi-k2.6")
    }

    func testUserSetupExperienceModeDefaultsAndRoundTrips() throws {
        XCTAssertEqual(UserSetupProfile.defaults.experienceMode, .beginner)

        let legacyPayload = Data("""
        {
          "useCase": "research",
          "useCases": ["teamProjects", "research"],
          "goalText": "  Build a private research workspace.  ",
          "contextStyle": "project",
          "wantsWeb": true,
          "wantsIronclaw": false,
          "wantsCouncil": true
        }
        """.utf8)
        let legacy = try JSONDecoder().decode(UserSetupProfile.self, from: legacyPayload)

        XCTAssertEqual(legacy.experienceMode, .beginner)
        XCTAssertEqual(legacy.normalizedForDefaults.goalText, "Build a private research workspace.")
        XCTAssertEqual(legacy.useCases, [.research, .teamProjects])
        XCTAssertEqual(legacy.useCase, .research)

        var power = legacy.normalizedForDefaults
        power.experienceMode = .power
        let encoded = try JSONEncoder().encode(power)
        let decoded = try JSONDecoder().decode(UserSetupProfile.self, from: encoded)

        XCTAssertEqual(decoded.experienceMode, .power)
        XCTAssertEqual(decoded, power)
        XCTAssertTrue(String(data: encoded, encoding: .utf8)?.contains(#""experienceMode":"power""#) == true)
    }
}
