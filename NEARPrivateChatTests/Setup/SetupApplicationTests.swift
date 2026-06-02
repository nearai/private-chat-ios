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
}
