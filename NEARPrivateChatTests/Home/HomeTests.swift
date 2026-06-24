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

    func testHomeInboxSectionPlanHidesEmptyLibraryShortcuts() {
        let empty = HomeInboxSectionPlan(
            selectedFilter: .all,
            searchQuery: "",
            activeConversationCount: 0,
            activeProjectCount: 0,
            projectContextMatchCount: 0,
            sharedWithMeCount: 0,
            archivedConversationCount: 0,
            archivedProjectCount: 0
        )

        XCTAssertFalse(empty.showsLibraryShortcuts)
        XCTAssertFalse(empty.showsSharedLibraryShortcut)
        XCTAssertFalse(empty.showsArchivedLibraryShortcut)

        let sharedOnly = HomeInboxSectionPlan(
            selectedFilter: .all,
            searchQuery: "",
            activeConversationCount: 0,
            activeProjectCount: 0,
            projectContextMatchCount: 0,
            sharedWithMeCount: 1,
            archivedConversationCount: 0,
            archivedProjectCount: 0
        )

        XCTAssertTrue(sharedOnly.showsLibraryShortcuts)
        XCTAssertTrue(sharedOnly.showsSharedLibraryShortcut)
        XCTAssertFalse(sharedOnly.showsArchivedLibraryShortcut)

        let archivedOnly = HomeInboxSectionPlan(
            selectedFilter: .all,
            searchQuery: "",
            activeConversationCount: 0,
            activeProjectCount: 0,
            projectContextMatchCount: 0,
            sharedWithMeCount: 0,
            archivedConversationCount: 1,
            archivedProjectCount: 1
        )

        XCTAssertTrue(archivedOnly.showsLibraryShortcuts)
        XCTAssertFalse(archivedOnly.showsSharedLibraryShortcut)
        XCTAssertTrue(archivedOnly.showsArchivedLibraryShortcut)
        XCTAssertEqual(archivedOnly.archivedItemCount, 2)
    }

    func testEmptyHomeFeedDraftsStayGenericNotCannedDemoSubjects() {
        let briefing = HomeEmptyFeedDraftPlanner.draft(for: .briefings)
        XCTAssertEqual(briefing.banner, "Briefing draft ready.")
        XCTAssertTrue(briefing.prompt.localizedCaseInsensitiveContains("topic, project, file, or search"))
        XCTAssertTrue(briefing.prompt.localizedCaseInsensitiveContains("current sources"))
        XCTAssertFalse(briefing.prompt.localizedCaseInsensitiveContains("AI news"))
        XCTAssertFalse(briefing.prompt.localizedCaseInsensitiveContains("weather"))

        let watcher = HomeEmptyFeedDraftPlanner.draft(for: .watchers)
        XCTAssertEqual(watcher.banner, "Watcher draft ready.")
        XCTAssertTrue(watcher.prompt.localizedCaseInsensitiveContains("product price"))
        XCTAssertTrue(watcher.prompt.localizedCaseInsensitiveContains("release date"))
        XCTAssertTrue(watcher.prompt.localizedCaseInsensitiveContains("regulation"))
        XCTAssertFalse(watcher.prompt.localizedCaseInsensitiveContains("Rolex"))
        XCTAssertFalse(watcher.prompt.contains("ETH"))
    }

    func testHomeClassifiesModelRoutedAlertsAsWatchers() {
        let percentAlert = Briefing(
            title: "NEAR move alert",
            prompt: "Using live market data, alert when NEAR moves 5%+ in 24h.",
            schedule: .daily(hour: 8, minute: 0),
            kind: .customPrompt
        )
        XCTAssertTrue(percentAlert.isCustomPromptWatcherLike)
        XCTAssertTrue(percentAlert.isWatcherLike)

        let dailyDigest = Briefing(
            title: "AI news digest",
            prompt: "Summarize the top AI news every morning.",
            schedule: .daily(hour: 8, minute: 0),
            kind: .customPrompt
        )
        XCTAssertFalse(dailyDigest.isCustomPromptWatcherLike)
        XCTAssertFalse(dailyDigest.isWatcherLike)
    }

    func testHomeBriefingFeedPresentationShowsNewWatcherAsScheduledNotAttention() {
        let watcher = Briefing(
            title: "Apple Vision Pro 2 release date, preorder timing",
            prompt: "Track Apple Vision Pro 2 release date, preorder timing, and price rumors with current sources; alert me if the date or price changes.",
            schedule: .weekly(weekday: 3, hour: 18, minute: 0),
            createdAt: Date(timeIntervalSince1970: 1_781_280_000),
            kind: .customPrompt
        )

        let presentation = HomeBriefingFeedPresentation(
            briefing: watcher,
            now: Date(timeIntervalSince1970: 1_781_280_300)
        )

        XCTAssertEqual(presentation.categoryText, "Watcher")
        XCTAssertEqual(presentation.scheduleSummaryText, "Tue · 6:00PM")
        XCTAssertEqual(presentation.metaText, "Watcher · Tue · 6:00PM")
        XCTAssertNil(presentation.statusKind)
        XCTAssertFalse(presentation.shouldShowStatusPill)
        XCTAssertNil(presentation.scheduleAccessoryText)
        XCTAssertEqual(presentation.detailText, "Queued for first run. It will return a live chart, source trail, and follow-up.")
        XCTAssertEqual(presentation.pendingPromiseText, "Chart + sources")
        XCTAssertEqual(presentation.pendingPromiseChipText, "Chart")
        XCTAssertEqual(presentation.pendingPromiseSymbolName, "chart.line.uptrend.xyaxis")
        XCTAssertFalse(presentation.detailText.localizedCaseInsensitiveContains("Last run didn't start"))
        XCTAssertFalse(presentation.detailText.localizedCaseInsensitiveContains("Needs attention"))
        XCTAssertFalse(presentation.detailText.localizedCaseInsensitiveContains("Using web search"))
        XCTAssertFalse(presentation.detailText.localizedCaseInsensitiveContains("No delivery yet"))
    }

    func testHomeBriefingFeedPresentationShowsPendingBriefingAsSourcedDelivery() {
        let briefing = Briefing(
            title: "Daily AI product release digest",
            prompt: "Summarize major AI product launches each morning with current sources.",
            schedule: .daily(hour: 8, minute: 0),
            createdAt: Date(timeIntervalSince1970: 1_781_280_000),
            kind: .dailyNews
        )

        let presentation = HomeBriefingFeedPresentation(
            briefing: briefing,
            now: Date(timeIntervalSince1970: 1_781_280_300)
        )

        XCTAssertEqual(presentation.categoryText, "Briefing")
        XCTAssertTrue(presentation.isPending)
        XCTAssertEqual(presentation.detailText, "Queued for first run. It will return a sourced stream, summary, and follow-up.")
        XCTAssertEqual(presentation.pendingPromiseText, "Summary + sources")
        XCTAssertEqual(presentation.pendingPromiseChipText, "Summary")
        XCTAssertEqual(presentation.pendingPromiseSymbolName, "link")
        XCTAssertFalse(presentation.detailText.localizedCaseInsensitiveContains("No delivery yet"))
    }

    func testHomeBriefingFeedPresentationCompactsMarkdownResultForCardPreview() {
        let watcher = Briefing(
            title: "Rolex GMT-Master II Pepsi market prices Toronto",
            prompt: "Track current Rolex GMT-Master II Pepsi prices in Toronto.",
            schedule: .weekly(weekday: 3, hour: 18, minute: 0),
            lastRunAt: Date(timeIntervalSince1970: 1_781_280_120),
            latestResult: MessageWidget(
                kind: .chart,
                title: "Rolex market",
                chart: WidgetChart(
                    label: "Rolex GMT-Master II",
                    value: "$22,500",
                    delta: "+12%",
                    trend: .up,
                    caption: "**USD ~$22,500 / CAD ~C$30,800** — as of June 2026 (Toronto / ET). The steel Rolex GMT-Master II Pepsi Ref. 126710BLRO is trading around **$22,500 USD** on the secondary market after a supply shock."
                )
            ),
            kind: .customPrompt
        )

        let presentation = HomeBriefingFeedPresentation(briefing: watcher)

        XCTAssertTrue(presentation.detailText.contains("USD ~$22,500 / CAD ~C$30,800"))
        XCTAssertFalse(presentation.detailText.contains("**"))
        XCTAssertLessThanOrEqual(presentation.detailText.count, 140)
    }

    func testHomeConversationPreviewMapsPrivateTransportFailure() {
        let raw = "OpenAI API error: API error: error sending request for url (https://cloud-api.near.ai/v1/responses)"

        let preview = HomeConversationPreviewFormatter.preview(
            cachedPreview: raw,
            title: "Private route smoke test"
        )

        XCTAssertEqual(preview, "Can't reach the private backend right now — retry in a moment.")
        XCTAssertFalse(preview.localizedCaseInsensitiveContains("OpenAI API error"))
        XCTAssertFalse(preview.localizedCaseInsensitiveContains("cloud-api.near.ai"))
    }

    func testHomeBriefingFeedPresentationCarriesPrivateRouteFailureReason() {
        let failureText = "Private route is rate-limited for this session. Wait for the cooldown, or use the privacy proxy only for this turn. If it keeps failing after cooldown, sign out and back in."
        let watcher = Briefing(
            title: "Apple Vision Pro 2 release date, preorder timing",
            prompt: "Track Apple Vision Pro 2 release date, preorder timing, and price rumors with current sources.",
            schedule: .weekly(weekday: 3, hour: 18, minute: 0),
            createdAt: Date(timeIntervalSince1970: 1_781_280_000),
            kind: .customPrompt,
            lastFailureAt: Date(timeIntervalSince1970: 1_781_280_120),
            lastFailureMessage: failureText
        )

        let presentation = HomeBriefingFeedPresentation(
            briefing: watcher,
            now: Date(timeIntervalSince1970: 1_781_280_300)
        )

        XCTAssertEqual(presentation.metaText, "Watcher · Tue · 6:00PM")
        XCTAssertEqual(presentation.statusKind, .attention)
        XCTAssertTrue(presentation.shouldShowStatusPill)
        XCTAssertEqual(presentation.statusText, "Needs attention")
        XCTAssertNil(presentation.scheduleAccessoryText)
        XCTAssertEqual(presentation.detailText, failureText)
    }

    func testHomeBriefingFeedPresentationMapsSignInFailureToRecoveryCopy() {
        let watcher = Briefing(
            title: "Research brief",
            prompt: "Research saved topic.",
            schedule: .daily(hour: 8, minute: 0),
            lastFailureAt: Date(timeIntervalSince1970: 1_781_280_120),
            lastFailureMessage: "Could not start a private conversation for this run. Check your connection or sign in again, then run it now."
        )

        let presentation = HomeBriefingFeedPresentation(briefing: watcher)

        XCTAssertEqual(presentation.statusKind, .attention)
        XCTAssertEqual(
            presentation.detailText,
            "The plan wasn't signed in when the brief was due. Re-run now, or check the plan's sign-in to resume the schedule."
        )
    }

    func testHomeBriefingFeedPresentationMapsRawBackendFailure() {
        let rawFailure = "OpenAI API error: API error: error sending request for url (https://cloud-api.near.ai/v1/responses)"
        let watcher = Briefing(
            title: "Private route smoke test",
            prompt: "Check whether private routing works.",
            schedule: .daily(hour: 8, minute: 0),
            lastFailureAt: Date(timeIntervalSince1970: 1_781_280_120),
            lastFailureMessage: rawFailure
        )

        let presentation = HomeBriefingFeedPresentation(briefing: watcher)

        XCTAssertEqual(presentation.statusKind, .attention)
        XCTAssertEqual(presentation.detailText, "Can't reach the private backend right now — retry in a moment.")
        XCTAssertFalse(presentation.detailText.contains("OpenAI API error"))
        XCTAssertFalse(presentation.detailText.contains("cloud-api.near.ai"))
    }

    func testHomeFeedScopesKeepBriefingsAndWatchersSeparate() {
        let watcher = Briefing(
            title: "Rolex GMT-Master II",
            prompt: "Using web search, find the latest price of a Rolex GMT-Master II.",
            schedule: .daily(hour: 8, minute: 0),
            kind: .customPrompt
        )
        let briefing = Briefing(
            title: "AI news digest",
            prompt: "Summarize the top AI news with sources.",
            schedule: .daily(hour: 8, minute: 0),
            kind: .customPrompt
        )

        XCTAssertEqual(
            HomeFeedPlanner.visibleBriefings([watcher, briefing], scope: .briefings).map(\.title),
            ["AI news digest"]
        )
        XCTAssertEqual(
            HomeFeedPlanner.visibleBriefings([watcher, briefing], scope: .watchers).map(\.title),
            ["Rolex GMT-Master II"]
        )

        let counts = HomeFeedPlanner.scopeCounts(briefings: [watcher, briefing], visibleConversationCount: 3)
        XCTAssertEqual(counts[.briefings], 1)
        XCTAssertEqual(counts[.watchers], 1)
        XCTAssertEqual(counts[.chats], 3)
        XCTAssertEqual(counts[.all], 5)
    }

    func testHomeFeedScopeVisibleLabelsStayCompact() {
        XCTAssertEqual(HomeFeedScope.all.title, "All")
        XCTAssertEqual(HomeFeedScope.briefings.title, "Briefings")
        XCTAssertEqual(HomeFeedScope.watchers.title, "Watchers")
        XCTAssertEqual(HomeFeedScope.chats.title, "Chats")

        XCTAssertEqual(HomeFeedScope.all.compactTitle, "All")
        XCTAssertEqual(HomeFeedScope.briefings.compactTitle, "Briefs")
        XCTAssertEqual(HomeFeedScope.watchers.compactTitle, "Watch")
        XCTAssertEqual(HomeFeedScope.chats.compactTitle, "Chats")
    }

    func testHomeStreamsCopySummarizesRealSurfaceState() {
        XCTAssertEqual(
            HomeStreamsCopy.subtitle(for: [
                .all: 17,
                .briefings: 2,
                .watchers: 8,
                .chats: 7
            ]),
            "2 briefings, 8 watchers, and 7 chats ready to continue."
        )
        XCTAssertEqual(
            HomeStreamsCopy.subtitle(for: [.all: 0, .briefings: 0, .watchers: 0, .chats: 0]),
            "Ask privately, then turn useful work into streams."
        )
        XCTAssertEqual(HomeStreamsCopy.liveCountText(for: [.all: 17]), "17 items")
        XCTAssertEqual(HomeStreamsCopy.liveCountText(for: [:]), "Ready")
    }

    func testHomeConversationPreviewFormatterUsesCacheOrTitleFallback() {
        XCTAssertEqual(
            HomeConversationPreviewFormatter.preview(
                cachedPreview: "  Cached answer\nwith useful detail.  ",
                title: "Ignored title"
            ),
            "Cached answer with useful detail."
        )

        XCTAssertEqual(
            HomeConversationPreviewFormatter.preview(
                cachedPreview: "## Direct answer\nThe best answer is: not over, but closer to an off-ramp.",
                title: "Ignored title"
            ),
            "The best answer is: not over, but closer to an off-ramp."
        )

        let currentNewsPreview = HomeConversationPreviewFormatter.preview(
            cachedPreview: """
            Today's News Briefing — June 12, 2026

            ## 1. SpaceX IPO: Largest in History

            **Confirmed:** SpaceX went public today.
            """,
            title: "Ignored title"
        )
        XCTAssertTrue(currentNewsPreview.contains("SpaceX IPO"))
        XCTAssertTrue(currentNewsPreview.contains("Confirmed:"))
        XCTAssertFalse(currentNewsPreview.contains("##"))
        XCTAssertFalse(currentNewsPreview.contains("**"))

        let collapsedMarkdownPreview = HomeConversationPreviewFormatter.preview(
            cachedPreview: "Today's News Briefing — June 12, 2026 ## 1. SpaceX IPO: Largest in History **Confirmed:** - SpaceX went public today.",
            title: "Ignored title"
        )
        XCTAssertTrue(collapsedMarkdownPreview.contains("Confirmed: SpaceX went public"))
        XCTAssertFalse(collapsedMarkdownPreview.contains("##"))
        XCTAssertFalse(collapsedMarkdownPreview.contains("**"))
        XCTAssertFalse(collapsedMarkdownPreview.contains(": -"))

        let liveNewsPreview = HomeConversationPreviewFormatter.preview(
            cachedPreview: """
            Today's Top Stories — June 12, 2026
            ---
            🚀 SpaceX IPO — Record-Setting Debut Today
            **SpaceX began trading on Nasdaq today (June 12)
            """,
            title: "Ignored title"
        )
        XCTAssertTrue(liveNewsPreview.contains("SpaceX IPO"))
        XCTAssertTrue(liveNewsPreview.contains("SpaceX began trading"))
        XCTAssertFalse(liveNewsPreview.contains("---"))
        XCTAssertFalse(liveNewsPreview.contains("🚀"))
        XCTAssertFalse(liveNewsPreview.contains("**"))
        XCTAssertFalse(liveNewsPreview.contains("*"))

        XCTAssertEqual(
            HomeConversationPreviewFormatter.preview(
                cachedPreview: "Short answer: it looks closer to ending, but I would not call it over yet.",
                title: "Ignored title"
            ),
            "It looks closer to ending, but I would not call it over yet."
        )

        XCTAssertEqual(
            HomeConversationPreviewFormatter.preview(
                cachedPreview: "Private route is rate-limited for this session. Wait for the cooldown, or use the privacy proxy only for this turn. If it keeps failing after cooldown, sign out and back in.",
                title: "Ignored title"
            ),
            "Private route limited. Retry private or add Cloud key."
        )

        XCTAssertEqual(
            HomeConversationPreviewFormatter.preview(
                cachedPreview: nil,
                title: "Reply in one short sentence: private route health check."
            ),
            "Asked: Reply in one short sentence: private route health check."
        )

        XCTAssertEqual(
            HomeConversationPreviewFormatter.displayTitle("Rolex GMT-Master II . Use web search, lead with the current market price and as-of date."),
            "Rolex GMT-Master II"
        )

        XCTAssertEqual(
            HomeConversationPreviewFormatter.displayTitle("Nintendo Switch 2 OLED release date, preorder timing and tell me if it changes"),
            "Nintendo Switch 2 OLED release date"
        )

        XCTAssertEqual(
            HomeConversationPreviewFormatter.displayTitle("What is news today? Include SpaceX IPO and Iran war updates."),
            "Today's news brief"
        )

        XCTAssertEqual(
            HomeConversationPreviewFormatter.preview(
                cachedPreview: nil,
                title: "Rolex GMT-Master II . Use web search, lead with the current market price and as-of date."
            ),
            "Asked: Rolex GMT-Master II"
        )

        XCTAssertEqual(
            HomeConversationPreviewFormatter.preview(cachedPreview: "  ", title: "New conversation"),
            "Open chat to continue."
        )
    }

    func testHomeConversationPreviewFormatterDetectsSourceCuePastCompactPreviewLimit() {
        let cached = """
        Today's Top Stories — June 12, 2026

        SpaceX began trading on Nasdaq today after a record-setting debut. The Iran peace-talk story remains unsettled. Apple and OpenAI both shipped AI updates.

        Sources: Reuters · AP News · MacRumors
        """

        let preview = HomeConversationPreviewFormatter.preview(
            cachedPreview: cached,
            title: "What is news today? Check current sources."
        )
        XCTAssertFalse(preview.localizedCaseInsensitiveContains("Sources:"))
        XCTAssertTrue(
            HomeConversationPreviewFormatter.hasSourceCue(
                cachedPreview: cached,
                title: "What is news today? Check current sources."
            )
        )
    }

    func testHomeFeedPlannerDeduplicatesRecentConversationTitlesForDefaultFeed() {
        let first = ConversationSummary(
            id: "conv-1",
            createdAt: 10,
            metadata: ConversationMetadata(title: "Private route health check")
        )
        let duplicate = ConversationSummary(
            id: "conv-2",
            createdAt: 9,
            metadata: ConversationMetadata(title: " private route health check ")
        )
        let other = ConversationSummary(
            id: "conv-3",
            createdAt: 8,
            metadata: ConversationMetadata(title: "Iran briefing")
        )
        let actionSuffixDuplicate = ConversationSummary(
            id: "conv-4",
            createdAt: 7,
            metadata: ConversationMetadata(title: "Iran briefing updates and tell me if it changes")
        )

        XCTAssertEqual(
            HomeFeedPlanner.uniqueRecentConversations([first, duplicate, other, actionSuffixDuplicate], limit: 3).map(\.id),
            ["conv-1", "conv-3"]
        )
    }

    func testHomeFeedPlannerHidesChatsThatDuplicateVisibleLiveItemsInAllStream() {
        let watcher = Briefing(
            title: "Rolex GMT-Master II",
            prompt: "Using web search, find the latest price of a Rolex GMT-Master II.",
            schedule: .daily(hour: 8, minute: 0),
            kind: .customPrompt
        )
        let duplicateChat = ConversationSummary(
            id: "conv-rolex",
            createdAt: 10,
            metadata: ConversationMetadata(title: "Rolex GMT-Master II . Use web search, lead with the current market price and as-of date.")
        )
        let distinctChat = ConversationSummary(
            id: "conv-iran",
            createdAt: 9,
            metadata: ConversationMetadata(title: "Iran war status today")
        )

        XCTAssertEqual(
            HomeFeedPlanner.uniqueRecentConversations(
                [duplicateChat, distinctChat],
                limit: 3,
                excludingBriefings: [watcher]
            ).map(\.id),
            ["conv-iran"]
        )
    }

    func testHomeFeedPlannerDeduplicatesBriefingsBeforeDefaultFeedLimit() {
        let now = Date(timeIntervalSince1970: 1_782_777_600)
        let duplicateOld = Briefing(
            title: "Apple Vision Pro 2 release date",
            prompt: "Watch for release-date changes.",
            schedule: .weekdays(hour: 7, minute: 0),
            createdAt: now.addingTimeInterval(-300),
            kind: .customPrompt,
            lastFailureAt: now.addingTimeInterval(-120)
        )
        let duplicateNew = Briefing(
            title: "Apple Vision Pro 2 release date updates and tell me if preorder timing changes",
            prompt: "Watch for release-date changes.",
            schedule: .weekdays(hour: 7, minute: 0),
            createdAt: now.addingTimeInterval(-60),
            kind: .customPrompt,
            lastFailureAt: now.addingTimeInterval(-30)
        )
        let digest = Briefing(
            title: "AI product digest",
            prompt: "Summarize product releases.",
            schedule: .daily(hour: 8, minute: 0),
            createdAt: now.addingTimeInterval(-240),
            latestResult: MessageWidget(kind: .generic, title: "3 product launches"),
            kind: .customPrompt
        )

        let visible = HomeFeedPlanner.visibleBriefings(
            [duplicateOld, digest, duplicateNew],
            scope: .all,
            allLimit: 2
        )

        XCTAssertEqual(visible.map(\.title), ["AI product digest", "Apple Vision Pro 2 release date updates and tell me if preorder timing changes"])
    }

    func testHomeFeedPlannerLimitsRepeatedAttentionCardsInDefaultAllStream() {
        let now = Date(timeIntervalSince1970: 1_782_777_600)
        let failedNintendo = Briefing(
            title: "Nintendo Switch 2 OLED release date, preorder timing",
            prompt: "Track release date and preorder timing.",
            schedule: .weekly(weekday: 6, hour: 9, minute: 0),
            createdAt: now.addingTimeInterval(-300),
            kind: .customPrompt,
            lastFailureAt: now.addingTimeInterval(-120),
            lastFailureMessage: "Private route is rate-limited for this session."
        )
        let failedApple = Briefing(
            title: "Apple Vision Pro 2 release date, preorder timing",
            prompt: "Track release date and preorder timing.",
            schedule: .weekly(weekday: 3, hour: 18, minute: 0),
            createdAt: now.addingTimeInterval(-240),
            kind: .customPrompt,
            lastFailureAt: now.addingTimeInterval(-60),
            lastFailureMessage: "Private route is rate-limited for this session."
        )
        let scheduledSony = Briefing(
            title: "Sony A7 VI release date tracker",
            prompt: "Track Sony A7 VI release date, preorder timing, and launch price.",
            schedule: .weekly(weekday: 7, hour: 9, minute: 0),
            createdAt: now.addingTimeInterval(-30),
            kind: .customPrompt
        )
        let digest = Briefing(
            title: "AI news digest",
            prompt: "Summarize AI product releases every morning.",
            schedule: .daily(hour: 8, minute: 0),
            createdAt: now.addingTimeInterval(-90),
            latestResult: MessageWidget(kind: .newsBrief, newsBrief: WidgetNewsBrief(stories: [
                WidgetNewsStory(title: "Three product launches")
            ])),
            kind: .customPrompt
        )

        let allVisible = HomeFeedPlanner.visibleBriefings(
            [failedNintendo, failedApple, scheduledSony, digest],
            scope: .all,
            allLimit: 3
        )
        XCTAssertEqual(allVisible.map(\.title), [
            "AI news digest",
            "Sony A7 VI release date tracker",
            "Apple Vision Pro 2 release date, preorder timing"
        ])

        let watcherVisible = HomeFeedPlanner.visibleBriefings(
            [failedNintendo, failedApple, scheduledSony, digest],
            scope: .watchers,
            scopedLimit: 8
        )
        XCTAssertEqual(watcherVisible.map(\.title), [
            "Sony A7 VI release date tracker",
            "Apple Vision Pro 2 release date, preorder timing",
            "Nintendo Switch 2 OLED release date, preorder timing"
        ])
    }

    func testHomeFeedPlannerReservesDefaultAllSlotForRecentChats() {
        XCTAssertEqual(
            HomeFeedPlanner.defaultAllBriefingLimit(totalCardLimit: 2, hasRecentConversations: true),
            1
        )
        XCTAssertEqual(
            HomeFeedPlanner.defaultAllBriefingLimit(totalCardLimit: 2, hasRecentConversations: false),
            2
        )
        XCTAssertEqual(
            HomeFeedPlanner.defaultAllBriefingLimit(totalCardLimit: 0, hasRecentConversations: true),
            0
        )

        let now = Date(timeIntervalSince1970: 1_782_777_600)
        let failedWatcher = Briefing(
            title: "Nintendo Switch 2 OLED release date",
            prompt: "Track release date.",
            schedule: .weekly(weekday: 6, hour: 9, minute: 0),
            createdAt: now.addingTimeInterval(-300),
            kind: .customPrompt,
            lastFailureAt: now.addingTimeInterval(-120),
            lastFailureMessage: "Private route is rate-limited for this session."
        )
        let digest = Briefing(
            title: "AI news digest",
            prompt: "Summarize product releases.",
            schedule: .daily(hour: 8, minute: 0),
            createdAt: now.addingTimeInterval(-240),
            latestResult: MessageWidget(kind: .newsBrief, newsBrief: WidgetNewsBrief(stories: [
                WidgetNewsStory(title: "Three product launches")
            ])),
            kind: .customPrompt
        )

        let reservedVisible = HomeFeedPlanner.visibleBriefings(
            [failedWatcher, digest],
            scope: .all,
            allLimit: HomeFeedPlanner.defaultAllBriefingLimit(totalCardLimit: 2, hasRecentConversations: true)
        )
        XCTAssertEqual(reservedVisible.map(\.title), ["AI news digest"])
    }

    func testWatchersScopeKeepsHealthyAndScheduledItemsAheadOfStaleFailures() {
        let now = Date(timeIntervalSince1970: 1_782_777_600)
        let failedNintendo = Briefing(
            title: "Nintendo Switch 2 OLED release date, preorder timing",
            prompt: "Track release date and preorder timing.",
            schedule: .weekly(weekday: 6, hour: 9, minute: 0),
            createdAt: now.addingTimeInterval(-300),
            kind: .customPrompt,
            lastFailureAt: now.addingTimeInterval(-120),
            lastFailureMessage: "Private route is rate-limited for this session."
        )
        let deliveredRolex = Briefing(
            title: "Rolex GMT-Master II",
            prompt: "Using web search, find the latest Rolex GMT-Master II market price.",
            schedule: .daily(hour: 8, minute: 0),
            createdAt: now.addingTimeInterval(-600),
            lastRunAt: now.addingTimeInterval(-60),
            latestResult: MessageWidget(
                kind: .chart,
                chart: WidgetChart(label: "Secondary market", value: "~$20,200")
            ),
            kind: .customPrompt
        )
        let scheduledSony = Briefing(
            title: "Sony A7 VI release date tracker",
            prompt: "Track Sony A7 VI release date, preorder timing, and launch price.",
            schedule: .weekly(weekday: 7, hour: 9, minute: 0),
            createdAt: now.addingTimeInterval(-30),
            kind: .customPrompt
        )

        let visible = HomeFeedPlanner.visibleBriefings(
            [failedNintendo, deliveredRolex, scheduledSony],
            scope: .watchers,
            scopedLimit: 8
        )

        XCTAssertEqual(visible.map(\.title), [
            "Rolex GMT-Master II",
            "Sony A7 VI release date tracker",
            "Nintendo Switch 2 OLED release date, preorder timing"
        ])
    }

    func testHomeFeedPlannerShowsOnlyOneAttentionCardWhenAllDefaultItemsFailed() {
        let now = Date(timeIntervalSince1970: 1_782_777_600)
        let failedNintendo = Briefing(
            title: "Nintendo Switch 2 OLED release date, preorder timing",
            prompt: "Track release date and preorder timing.",
            schedule: .weekly(weekday: 6, hour: 9, minute: 0),
            createdAt: now.addingTimeInterval(-300),
            kind: .customPrompt,
            lastFailureAt: now.addingTimeInterval(-120),
            lastFailureMessage: "Private route is rate-limited for this session."
        )
        let failedApple = Briefing(
            title: "Apple Vision Pro 2 release date, preorder timing",
            prompt: "Track release date and preorder timing.",
            schedule: .weekly(weekday: 3, hour: 18, minute: 0),
            createdAt: now.addingTimeInterval(-240),
            kind: .customPrompt,
            lastFailureAt: now.addingTimeInterval(-60),
            lastFailureMessage: "Private route is rate-limited for this session."
        )

        let allVisible = HomeFeedPlanner.visibleBriefings(
            [failedNintendo, failedApple],
            scope: .all,
            allLimit: 3
        )

        XCTAssertEqual(allVisible.map(\.title), [
            "Apple Vision Pro 2 release date, preorder timing"
        ])
    }

    func testHomeFeedPlannerLimitsRecoveryChatsInDefaultAllStream() {
        let releaseGap = ConversationSummary(
            id: "conv-release-gap",
            createdAt: 30,
            metadata: ConversationMetadata(title: "Nintendo Switch 2 OLED release date, preorder timing")
        )
        let sourcedNews = ConversationSummary(
            id: "conv-news",
            createdAt: 20,
            metadata: ConversationMetadata(title: "What is news today? Include SpaceX IPO and Iran updates.")
        )
        let servicesDraft = ConversationSummary(
            id: "conv-services",
            createdAt: 10,
            metadata: ConversationMetadata(title: "Draft a services agreement from this PDF template")
        )
        let secondReleaseGap = ConversationSummary(
            id: "conv-release-gap-2",
            createdAt: 9,
            metadata: ConversationMetadata(title: "Apple Vision Pro 2 release date, preorder timing")
        )
        let previews = [
            "conv-release-gap": "Asked: Nintendo Switch 2 OLED release date, preorder timing",
            "conv-news": "SpaceX IPO and Iran updates with sources.",
            "conv-services": "Draft agreement outline ready.",
            "conv-release-gap-2": "Asked: Apple Vision Pro 2 release date, preorder timing"
        ]
        let hasSources: Set<String> = ["conv-news"]

        let visible = HomeFeedPlanner.uniqueRecentConversations(
            [releaseGap, sourcedNews, servicesDraft, secondReleaseGap],
            limit: 3,
            isRecoveryCandidate: { conversation in
                HomeConversationRecoveryPolicy.isRecovery(
                    title: conversation.title,
                    preview: previews[conversation.id] ?? "",
                    hasSourceCue: hasSources.contains(conversation.id)
                )
            }
        )

        XCTAssertEqual(visible.map(\.id), [
            "conv-news",
            "conv-services",
            "conv-release-gap"
        ])
    }

    func testHomeFeedPlannerShowsOnlyOneRecoveryChatWhenAllDefaultChatsNeedRecovery() {
        let releaseGap = ConversationSummary(
            id: "conv-release-gap",
            createdAt: 30,
            metadata: ConversationMetadata(title: "Nintendo Switch 2 OLED release date, preorder timing")
        )
        let privateFailure = ConversationSummary(
            id: "conv-private-failure",
            createdAt: 20,
            metadata: ConversationMetadata(title: "Private route health check")
        )

        let visible = HomeFeedPlanner.uniqueRecentConversations(
            [releaseGap, privateFailure],
            limit: 3,
            isRecoveryCandidate: { conversation in
                let preview = conversation.id == "conv-private-failure"
                    ? "Private route limited. Retry private or add Cloud key."
                    : "Asked: Nintendo Switch 2 OLED release date, preorder timing"
                return HomeConversationRecoveryPolicy.isRecovery(
                    title: conversation.title,
                    preview: preview,
                    hasSourceCue: false
                )
            }
        )

        XCTAssertEqual(visible.map(\.id), ["conv-release-gap"])
    }

    func testBriefingPresentationTextCleansStoredTrackerTitleAndPromptScaffold() {
        let briefing = Briefing(
            title: "Sony A7 VI release date, preorder timing, and la",
            prompt: "Using web search, find the latest Sony A7 VI release date, preorder timing, and launch price with current sources and report it concisely. Lead with the current number/price (with its currency) and the as-of date, then one short line of context. If it's a price or numeric value, present it as a metric or chart widget. Return a concise update with what changed, why it matters, any calendar-worthy or follow-up actions, and the next useful action.",
            schedule: .weekly(weekday: 7, hour: 9, minute: 0),
            kind: .customPrompt
        )

        XCTAssertEqual(
            BriefingPresentationText.displayTitle(briefing.title),
            "Sony A7 VI release date, preorder timing"
        )
        let about = BriefingPresentationText.conciseAboutText(for: briefing)
        XCTAssertEqual(
            about,
            "Tracks the latest Sony A7 VI release date, preorder timing, and launch price. Uses current sources and saves each run here."
        )
        XCTAssertFalse(about.localizedCaseInsensitiveContains("metric or chart widget"))
        XCTAssertFalse(about.localizedCaseInsensitiveContains("Return a concise update"))
    }

    @MainActor
    func testHomeStoreOwnsSearchFilterAndPendingLaunchState() {
        let store = HomeStore()
        let suggestion = EmptyChatStarterSuggestion(
            title: "Research",
            symbolName: "doc.text.magnifyingglass",
            prompt: "Research this with sources and cite what matters: ",
            action: .research
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

    func testHomeComposerRouteBadgeVisibleTextDisclosesPrivateRoute() {
        XCTAssertEqual(
            HomeComposerRouteBadgeText.visibleText(routeTitle: "Private route", routeDetail: "GLM 5.1"),
            "Private · GLM 5.1"
        )
        XCTAssertEqual(
            HomeComposerRouteBadgeText.visibleText(routeTitle: "Private route", routeDetail: "GLM 5.1 · Web"),
            "Private + Web · GLM 5.1"
        )
        XCTAssertEqual(
            HomeComposerRouteBadgeText.visibleText(routeTitle: "Council", routeDetail: "3 models"),
            "3 models"
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
            title: "Summarize",
            symbolName: "text.alignleft",
            prompt: "Summarize this clearly: "
        )

        let shouldFocusComposer = EmptyChatStarterCoordinator.apply(suggestion, to: store)

        XCTAssertTrue(shouldFocusComposer)
        XCTAssertTrue(store.draft.hasPrefix("Summarize this clearly:"))
        XCTAssertTrue(store.draft.hasSuffix("Review the Q3 launch checklist."))
    }

    @MainActor
    func testNewChatResetsToSimplePrivateRouteDefaults() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.selectedModel = "Qwen/Qwen3.5-122B-A10B"
        store.councilModelIDs = [
            "Qwen/Qwen3.5-122B-A10B",
            "Qwen/Qwen3.6-35B-A3B-FP8"
        ]
        store.sourceMode = .web
        store.researchModeEnabled = true

        store.startNewConversation()

        XCTAssertEqual(store.selectedModel, ModelOption.nearPrivateDefaultModelID)
        XCTAssertEqual(store.councilModelIDs, [ModelOption.nearPrivateDefaultModelID])
        XCTAssertFalse(store.isCouncilModeEnabled)
        XCTAssertEqual(store.sourceMode, .auto)
        XCTAssertFalse(store.researchModeEnabled)
    }
}
