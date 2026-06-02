import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testSoulPromptComposerParsesSectionsWithoutChatStore() {
        let profile = SoulPromptComposer.Profile.parse("""
        # soul.md

        ## Identity
        Call me Riley.

        ## Intent
        Draft product briefs.

        ## Voice & Format
        Be direct.
        """)

        XCTAssertEqual(profile.identity, "Call me Riley.")
        XCTAssertEqual(profile.intent, "Draft product briefs.")
        XCTAssertEqual(profile.voiceAndFormat, "Be direct.")

        let externalPrompt = SoulPromptComposer.promptBlock(profile: profile, route: .nearCloud)
        XCTAssertFalse(externalPrompt.contains("Riley"))
        XCTAssertTrue(externalPrompt.contains("Draft product briefs."))
        XCTAssertTrue(externalPrompt.contains("Be direct."))
    }
}
