import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testStarterPresetQuickStartProfileKeepsSamplePromptOutOfSavedGoal() {
        let profile = UserSetupStarterPreset.researchBrief.quickStartProfile

        XCTAssertEqual(profile.useCases, [.research])
        XCTAssertEqual(profile.goalText, "")
        XCTAssertTrue(profile.wantsWeb)
        XCTAssertTrue(profile.wantsCouncil)
        XCTAssertEqual(profile.experienceMode, .power)
        // The staged first-run draft comes from the use-case starter; the point
        // is the sample prompt never leaks into the persisted goalText (above).
        XCTAssertEqual(profile.firstRunDraft, UserSetupUseCase.research.starterPrompt)
    }

    func testStarterPresetsPrefillExampleGoalAndKeepCTAStateDerived() {
        for preset in UserSetupStarterPreset.allCases {
            var profile = UserSetupProfile.defaults
            profile.applyStarterPreset(preset)

            let plan = AppSetupPlan(profile: profile, readiness: .optimistic)

            XCTAssertEqual(profile.goalText, preset.setupExampleGoalText)
            XCTAssertNotEqual(profile.goalText, preset.prompt)
            XCTAssertEqual(profile.useCases, [preset.useCase])
            XCTAssertEqual(profile.wantsWeb, preset.wantsWeb)
            XCTAssertEqual(profile.wantsIronclaw, preset.wantsIronclaw)
            XCTAssertEqual(profile.wantsCouncil, preset.wantsCouncil)
            XCTAssertEqual(plan.expectedFirstAction, "Start from your goal")
            XCTAssertEqual(plan.goalText, preset.setupExampleGoalText)
            XCTAssertNotNil(plan.firstRunDraft)
        }
    }

    func testSetupRouteDefaultResolverPreservesFallbacksAndFiltersUnsafeCouncilRoutes() {
        let defaults = SetupRouteDefaultResolver.currentDefaults(
            selectedModelID: ModelOption.ironclawModelID,
            isCouncilModeEnabled: false,
            councilModelIDs: [
                " zai-org/GLM-5.1-FP8 ",
                ModelOption.ironclawModelID,
                "ZAI-ORG/glm-5.1-fp8",
                ModelOption.ironclawMobileModelID,
                "Qwen/Qwen3.6-35B-A3B-FP8",
                "anthropic/claude-sonnet-4-6"
            ],
            agentModelIDs: [ModelOption.ironclawMobileModelID],
            preferredAvailableModelID: "zai-org/GLM-5.1-FP8",
            defaultModelID: ModelCatalogStore.defaultModelID,
            maxCouncilModels: 3
        )

        XCTAssertEqual(defaults.privateModelID, "zai-org/GLM-5.1-FP8")
        XCTAssertEqual(
            defaults.councilModelIDs,
            ["zai-org/GLM-5.1-FP8", "Qwen/Qwen3.6-35B-A3B-FP8", "anthropic/claude-sonnet-4-6"]
        )
        XCTAssertEqual(defaults.ironclawMobileModelID, ModelOption.ironclawMobileModelID)
    }

    func testSetupRouteDefaultResolverRejectsNonPrivateStoredDefault() {
        let resolved = SetupRouteDefaultResolver.resolvedDefaults(
            stored: SetupRouteDefaults(
                privateModelID: ModelOption.nearCloudModelID(for: "anthropic/claude-sonnet-4-6"),
                councilModelIDs: [],
                ironclawMobileModelID: ModelOption.ironclawMobileModelID
            ),
            fallback: SetupRouteDefaults(
                privateModelID: "zai-org/GLM-5.1-FP8",
                councilModelIDs: ["zai-org/GLM-5.1-FP8"],
                ironclawMobileModelID: nil
            ),
            preferredAvailableModelID: "Qwen/Qwen3.6-35B-A3B-FP8",
            agentModelIDs: [],
            defaultModelID: ModelCatalogStore.defaultModelID,
            maxCouncilModels: 3
        )

        XCTAssertEqual(resolved.privateModelID, "zai-org/GLM-5.1-FP8")
        XCTAssertEqual(resolved.councilModelIDs, ["zai-org/GLM-5.1-FP8"])
        XCTAssertNil(resolved.ironclawMobileModelID)
    }
}
