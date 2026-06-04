import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testHomeSearchConversationGroupsCollapseToChatsSection() {
        let conversations = [
            ConversationSummary(
                id: "conv-1",
                createdAt: 1_700_000_000,
                metadata: ConversationMetadata(title: "Launch summary", pinnedAt: nil, archivedAt: nil, importedAt: nil, rootResponseID: nil)
            ),
            ConversationSummary(
                id: "conv-2",
                createdAt: 1_699_000_000,
                metadata: ConversationMetadata(title: "Risk follow-up", pinnedAt: nil, archivedAt: nil, importedAt: nil, rootResponseID: nil)
            )
        ]

        let groups = HomeSearchIndex.conversationGroups(
            searchQuery: "launch",
            conversations: conversations,
            now: Date(timeIntervalSince1970: 1_700_050_000),
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(groups.map(\.title), ["Chats"])
        XCTAssertEqual(groups.first?.conversations.map(\.id), ["conv-1", "conv-2"])
    }

    func testHomeConversationGroupsKeepPinnedAndDateBucketsWithoutSearch() {
        let now = Date(timeIntervalSince1970: 1_700_100_000)
        let calendar = Calendar(identifier: .gregorian)
        let startOfToday = calendar.startOfDay(for: now).timeIntervalSince1970
        let yesterday = startOfToday - 3_600
        let earlier = startOfToday - 200_000

        let conversations = [
            ConversationSummary(
                id: "conv-pinned",
                createdAt: startOfToday + 60,
                metadata: ConversationMetadata(title: "Pinned chat", pinnedAt: "2026-05-25T00:00:00Z", archivedAt: nil, importedAt: nil, rootResponseID: nil)
            ),
            ConversationSummary(
                id: "conv-today",
                createdAt: startOfToday + 120,
                metadata: ConversationMetadata(title: "Today chat", pinnedAt: nil, archivedAt: nil, importedAt: nil, rootResponseID: nil)
            ),
            ConversationSummary(
                id: "conv-yesterday",
                createdAt: yesterday,
                metadata: ConversationMetadata(title: "Yesterday chat", pinnedAt: nil, archivedAt: nil, importedAt: nil, rootResponseID: nil)
            ),
            ConversationSummary(
                id: "conv-earlier",
                createdAt: earlier,
                metadata: ConversationMetadata(title: "Earlier chat", pinnedAt: nil, archivedAt: nil, importedAt: nil, rootResponseID: nil)
            )
        ]

        let groups = HomeSearchIndex.conversationGroups(
            searchQuery: "",
            conversations: conversations,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(groups.map(\.title), ["Pinned", "Today", "Yesterday", "Earlier"])
        XCTAssertEqual(groups[0].conversations.map(\.id), ["conv-pinned"])
        XCTAssertEqual(groups[1].conversations.map(\.id), ["conv-today"])
        XCTAssertEqual(groups[2].conversations.map(\.id), ["conv-yesterday"])
        XCTAssertEqual(groups[3].conversations.map(\.id), ["conv-earlier"])
    }

    func testHomeInboxSectionPlanKeepsEmptyStatesScopedToSelectedFilter() {
        let activeSearch = HomeInboxSectionPlan(
            selectedFilter: .all,
            searchQuery: "missing",
            activeConversationCount: 0,
            activeProjectCount: 0,
            projectContextMatchCount: 0,
            sharedWithMeCount: 2,
            archivedConversationCount: 1,
            archivedProjectCount: 0
        )

        XCTAssertTrue(activeSearch.showsActiveSetupEmptyState)
        XCTAssertTrue(activeSearch.showsActiveSearchEmptyState)
        XCTAssertFalse(activeSearch.showsSharedEmptyState)
        XCTAssertFalse(activeSearch.showsArchivedEmptyState)

        let sharedSearch = HomeInboxSectionPlan(
            selectedFilter: .shared,
            searchQuery: "missing",
            activeConversationCount: 3,
            activeProjectCount: 2,
            projectContextMatchCount: 1,
            sharedWithMeCount: 0,
            archivedConversationCount: 1,
            archivedProjectCount: 1
        )

        XCTAssertTrue(sharedSearch.showsSharedEmptyState)
        XCTAssertFalse(sharedSearch.showsActiveSearchEmptyState)
        XCTAssertFalse(sharedSearch.showsArchivedEmptyState)

        let archivedSearch = HomeInboxSectionPlan(
            selectedFilter: .archived,
            searchQuery: "missing",
            activeConversationCount: 3,
            activeProjectCount: 2,
            projectContextMatchCount: 1,
            sharedWithMeCount: 1,
            archivedConversationCount: 0,
            archivedProjectCount: 0
        )

        XCTAssertTrue(archivedSearch.showsArchivedEmptyState)
        XCTAssertFalse(archivedSearch.showsSharedEmptyState)
        XCTAssertFalse(archivedSearch.showsActiveSearchEmptyState)
    }

    @MainActor
    func testHomeStoreOwnsSearchFilterAndPendingLaunchState() {
        let store = HomeStore()
        let suggestion = EmptyChatStarterSuggestion(
            title: "Draft trackers",
            symbolName: "calendar.badge.clock",
            prompt: "Turn this into recurring trackers: "
        )

        store.searchText = "  rolex tracker  "
        XCTAssertEqual(store.searchQuery, "rolex tracker")

        store.toggleSearch()
        XCTAssertTrue(store.isSearchVisible)
        XCTAssertEqual(store.searchText, "  rolex tracker  ")

        store.toggleSearch()
        XCTAssertFalse(store.isSearchVisible)
        XCTAssertEqual(store.searchText, "")

        store.selectHomeFilter(.shared)
        XCTAssertEqual(store.selectedHomeFilter, .shared)

        store.toggleLaunchSuggestion(suggestion)
        XCTAssertEqual(store.selectedHomeLaunchSuggestionID, suggestion.id)
        store.toggleLaunchSuggestion(suggestion)
        XCTAssertNil(store.selectedHomeLaunchSuggestionID)

        store.queuePendingLaunch(
            suggestion: suggestion,
            draft: "morning dose plan",
            followUp: .project
        )
        XCTAssertEqual(store.pendingHomeLaunchSuggestion?.id, suggestion.id)
        XCTAssertEqual(store.pendingHomeLaunchDraft, "morning dose plan")
        XCTAssertEqual(store.pendingHomeLaunchFollowUp, .project)

        store.clearPendingLaunch()
        XCTAssertNil(store.pendingHomeLaunchSuggestion)
        XCTAssertEqual(store.pendingHomeLaunchDraft, "")
        XCTAssertNil(store.pendingHomeLaunchFollowUp)
    }

    func testPersonalizedStarterRequiresFinanceContext() {
        // Coin keyword without finance context (ambiguous "near") → no starter.
        XCTAssertNil(QuickIntentParser.personalizedStarter(fromMemory: ["I live near Toronto"]))
        // With finance context → starter.
        XCTAssertEqual(
            QuickIntentParser.personalizedStarter(fromMemory: ["I hold some near"])?.prompt,
            "What's the NEAR price?"
        )
    }

    func testEmptyChatStarterStagesPromptWithSeparatorAndWithoutDuplicatePrefix() {
        XCTAssertEqual(
            EmptyChatStarterCoordinator.stagedPrompt(
                "Research this with sources: ",
                existingDraft: "token liquidity"
            ),
            "Research this with sources: token liquidity"
        )
        XCTAssertEqual(
            EmptyChatStarterCoordinator.stagedPrompt(
                "Research this with sources: ",
                existingDraft: "Research this with sources: token liquidity"
            ),
            "Research this with sources: token liquidity"
        )
    }

    func testHomeStagedPromptPreservesExistingLaunchDraft() {
        let stagedPrompt = HomeStagedPrompt(prompt: "Plan the next Agent task: ")

        XCTAssertEqual(
            stagedPrompt.resolvedPrompt(existingDraft: "run a hostile review against the chat route"),
            "Plan the next Agent task: run a hostile review against the chat route"
        )
        XCTAssertEqual(
            stagedPrompt.resolvedPrompt(existingDraft: "Plan the next Agent task: run a hostile review"),
            "Plan the next Agent task: run a hostile review"
        )
    }

    func testPersonalizedStarterFromMemory() {
        let bitcoin = QuickIntentParser.personalizedStarter(fromMemory: ["I hold a lot of bitcoin", "I live in Denver"])
        XCTAssertEqual(bitcoin?.symbol, "chart.line.uptrend.xyaxis")
        XCTAssertEqual(bitcoin?.prompt, "What's the BTC price?")
        // Nothing trackable → no personalized starter (defaults are used).
        XCTAssertNil(QuickIntentParser.personalizedStarter(fromMemory: ["My favorite color is teal"]))
        XCTAssertNil(QuickIntentParser.personalizedStarter(fromMemory: []))
    }

    @MainActor
    func testEmptyChatStarterCoordinatorStagesExistingDraftIntoQuickStart() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.draft = "Review the Q3 launch checklist."
        let suggestion = EmptyChatStarterSuggestion(
            title: "Draft trackers",
            symbolName: "calendar.badge.clock",
            prompt: "Turn this into recurring trackers, reminders, and calendar drafts. Include cadence, date, time, timezone, attendees, missing_fields, confidence, and exact commands. Preview before creating anything: "
        )

        let shouldFocusComposer = EmptyChatStarterCoordinator.apply(suggestion, to: store)

        XCTAssertTrue(shouldFocusComposer)
        XCTAssertTrue(store.draft.hasPrefix("Turn this into recurring trackers"))
        XCTAssertTrue(store.draft.hasSuffix("Review the Q3 launch checklist."))
    }
}
