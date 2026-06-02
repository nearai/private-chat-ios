import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testUserSetupLaunchCardPendingCanBeCleared() throws {
        let defaults = try makeIsolatedDefaults()
        let accountID = "user:launch-card"

        UserSetupStorage.save(.defaults, for: accountID, defaults: defaults)
        XCTAssertTrue(UserSetupStorage.hasPendingLaunchCard(for: accountID, defaults: defaults))

        UserSetupStorage.clearPendingLaunchCard(for: accountID, defaults: defaults)

        XCTAssertFalse(UserSetupStorage.hasPendingLaunchCard(for: accountID, defaults: defaults))
    }

    @MainActor
    func testSetupStoreMirrorsPersistedProfileState() throws {
        let defaults = try makeIsolatedDefaults()
        let accountID = "user:setup-store"
        let store = SetupStore(defaults: defaults)
        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research]
        profile.wantsWeb = true

        XCTAssertTrue(store.needsFirstRunSetup(for: accountID))

        store.save(profile, for: accountID)

        XCTAssertEqual(store.profile, profile.normalizedForDefaults)
        XCTAssertTrue(store.isCompleted)
        XCTAssertTrue(store.hasPendingLaunchCard)

        store.clearPendingLaunchCard(for: accountID)

        XCTAssertEqual(store.profile, profile.normalizedForDefaults)
        XCTAssertTrue(store.isCompleted)
        XCTAssertFalse(store.hasPendingLaunchCard)
        XCTAssertFalse(store.needsFirstRunSetup(for: accountID))
    }

    func testUserSetupSaveWithoutPendingLaunchCardSuppressesHomeResumeCard() throws {
        let defaults = try makeIsolatedDefaults()
        let accountID = "user:applied-setup"

        UserSetupStorage.saveWithoutPendingLaunchCard(.defaults, for: accountID, defaults: defaults)

        XCTAssertTrue(UserSetupStorage.isCompleted(for: accountID, defaults: defaults))
        XCTAssertFalse(UserSetupStorage.hasPendingLaunchCard(for: accountID, defaults: defaults))
    }

    func testUserSetupPresentationProfileUsesDefaultsUntilSetupCompletes() throws {
        let defaults = try makeIsolatedDefaults()
        let accountID = "user:setup-presentation"
        var current = UserSetupProfile.defaults
        current.useCase = .research
        current.useCases = [.research]
        current.wantsCouncil = true

        let initial = UserSetupStorage.presentationProfile(
            for: accountID,
            currentDefaults: current,
            defaults: defaults
        )

        XCTAssertEqual(initial, .defaults)

        UserSetupStorage.saveWithoutPendingLaunchCard(current, for: accountID, defaults: defaults)

        let afterCompletion = UserSetupStorage.presentationProfile(
            for: accountID,
            currentDefaults: .defaults,
            defaults: defaults
        )

        XCTAssertEqual(afterCompletion, current.normalizedForDefaults)
    }

    func testUserSetupCompleteFirstRunPrivateChatPersistsSimpleDefaults() throws {
        let defaults = try makeIsolatedDefaults()
        let accountID = "user:first-run-private-chat"

        let profile = UserSetupStorage.completeFirstRunPrivateChat(for: accountID, defaults: defaults)

        XCTAssertEqual(profile, .defaults)
        XCTAssertEqual(UserSetupStorage.load(for: accountID, defaults: defaults), .defaults)
        XCTAssertTrue(UserSetupStorage.isCompleted(for: accountID, defaults: defaults))
        XCTAssertFalse(UserSetupStorage.hasPendingLaunchCard(for: accountID, defaults: defaults))
        XCTAssertFalse(UserSetupStorage.needsFirstRunSetup(for: accountID, defaults: defaults))
    }

    func testUserSetupCompleteFirstRunQuickStartPersistsPresetDefaults() throws {
        let defaults = try makeIsolatedDefaults()
        let accountID = "user:first-run-quick-start"

        let profile = UserSetupStorage.completeFirstRunQuickStart(
            for: accountID,
            preset: .agentMission,
            defaults: defaults
        )

        XCTAssertEqual(profile, UserSetupStarterPreset.agentMission.quickStartProfile)
        XCTAssertEqual(
            UserSetupStorage.load(for: accountID, defaults: defaults),
            UserSetupStarterPreset.agentMission.quickStartProfile
        )
        XCTAssertEqual(UserSetupStorage.load(for: accountID, defaults: defaults)?.goalText, "")
        XCTAssertTrue(UserSetupStorage.isCompleted(for: accountID, defaults: defaults))
        XCTAssertFalse(UserSetupStorage.hasPendingLaunchCard(for: accountID, defaults: defaults))
        XCTAssertFalse(UserSetupStorage.needsFirstRunSetup(for: accountID, defaults: defaults))
    }

    func testUserSetupNormalizationPreservesExplicitDefaults() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research]
        profile.goalText = "  Compare private AI routes for an investor memo.  "
        profile.contextStyle = .simple
        profile.wantsWeb = false
        profile.wantsIronclaw = false
        profile.wantsCouncil = false

        let normalized = profile.normalizedForDefaults

        XCTAssertEqual(normalized.useCase, .research)
        XCTAssertEqual(normalized.useCases, [.research])
        XCTAssertEqual(normalized.goalText, "Compare private AI routes for an investor memo.")
        XCTAssertEqual(normalized.contextStyle, .simple)
        XCTAssertFalse(normalized.wantsWeb)
        XCTAssertFalse(normalized.wantsIronclaw)
        XCTAssertFalse(normalized.wantsCouncil)
    }

    func testUserSetupUseCaseToggleKeepsOrderedMultiSelection() {
        var profile = UserSetupProfile.defaults

        profile.toggleUseCase(.teamProjects)
        profile.toggleUseCase(.research)
        XCTAssertEqual(profile.useCases, [.privateChat, .research, .teamProjects])
        XCTAssertEqual(profile.useCase, .research)

        profile.toggleUseCase(.privateChat)
        XCTAssertEqual(profile.useCases, [.research, .teamProjects])
        XCTAssertEqual(profile.useCase, .research)

        profile.toggleUseCase(.research)
        profile.toggleUseCase(.teamProjects)
        XCTAssertEqual(profile.useCases, [.teamProjects])
        XCTAssertEqual(profile.useCase, .teamProjects)

        profile.toggleUseCase(.teamProjects)
        XCTAssertEqual(profile.useCases, [.teamProjects])
    }

    func testResearchUseCaseSelectionDefaultsToCurrentSourcesUnlessEdited() {
        var profile = UserSetupProfile.defaults
        profile.toggleUseCase(.research)

        profile.applyUseCaseSelectionDefaults(
            editedWeb: false,
            editedIronclaw: false,
            editedCouncil: false,
            editedContextStyle: false
        )

        XCTAssertEqual(profile.useCase, .research)
        XCTAssertEqual(profile.contextStyle, .project)
        XCTAssertTrue(profile.wantsWeb)

        profile.wantsWeb = false
        profile.applyUseCaseSelectionDefaults(
            editedWeb: true,
            editedIronclaw: false,
            editedCouncil: false,
            editedContextStyle: false
        )

        XCTAssertFalse(profile.wantsWeb)
    }

    func testSetupLaunchCardUsesGoalAsSubtitleWhenPresent() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research]
        profile.contextStyle = .project
        profile.goalText = "Map the strongest privacy proof workflow."

        let plan = AppSetupPlan(profile: profile, readiness: .optimistic)

        XCTAssertEqual(plan.launchCardTitle, "Start from your goal")
        XCTAssertEqual(plan.launchCardSubtitle, "Map the strongest privacy proof workflow.")
    }

    func testSetupGoalDrivesEmptyStateSubtitleAndPrompts() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research]
        profile.goalText = "Map the strongest privacy proof workflow."

        let normalized = profile.normalizedForDefaults
        let suggestions = normalized.emptyStatePromptSuggestions

        XCTAssertEqual(normalized.emptyStateSubtitle, "Goal ready: Map the strongest privacy proof workflow.")
        XCTAssertEqual(suggestions.map(\.title), ["Start brief", "Find sources", "Recommend next step"])
        XCTAssertEqual(suggestions.first?.prompt, "Write a sourced brief for this goal: Map the strongest privacy proof workflow.")
    }

    func testSetupUseCaseProvidesFallbackStarterDraftAndEmptyStatePromptsWithoutGoal() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]

        let normalized = profile.normalizedForDefaults
        let suggestions = normalized.emptyStatePromptSuggestions

        XCTAssertEqual(normalized.firstRunDraft, "Plan the first repo task: what to inspect, what to change, and which focused tests should run.")
        XCTAssertEqual(normalized.emptyStateSubtitle, "Start with a safe repo plan, then verify the patch or test pass.")
        XCTAssertEqual(suggestions.map(\.title), ["Repo plan", "Review repo", "Focused tests"])
        XCTAssertEqual(suggestions.first?.prompt, "Plan the first repo task: what to inspect, what to change, and which focused tests should run.")
    }

    func testMultiTrackSetupBuildsCombinedStarterDraftAndSuggestionsForGoal() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research, .teamProjects]
        profile.contextStyle = .project
        profile.goalText = "Map the strongest privacy proof workflow."

        let normalized = profile.normalizedForDefaults
        let suggestions = normalized.emptyStatePromptSuggestions
        let plan = AppSetupPlan(profile: normalized, readiness: .optimistic)

        XCTAssertEqual(
            normalized.firstRunDraft,
            "Write a sourced brief for this goal using project files, links, notes, and memory: Map the strongest privacy proof workflow."
        )
        XCTAssertEqual(suggestions.map(\.title), ["Start goal", "Start brief", "Organize project"])
        XCTAssertEqual(
            suggestions.first?.prompt,
            "Write a sourced brief for this goal using project files, links, notes, and memory: Map the strongest privacy proof workflow."
        )
        XCTAssertEqual(plan.firstRunDraft, normalized.firstRunDraft)
        XCTAssertEqual(
            plan.starterSkillSuggestions.map(\.id),
            ["llm-council", "plan-mode", "decision-capture", "new-project"]
        )
        XCTAssertEqual(plan.starterPromptSuggestions.map(\.title), ["Start goal", "Start brief", "Organize project"])
    }

    func testMultiTrackSetupUsesCombinedPromptWithoutGoal() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents, .research, .teamProjects]
        profile.contextStyle = .project

        let normalized = profile.normalizedForDefaults
        let suggestions = normalized.emptyStatePromptSuggestions

        XCTAssertEqual(
            normalized.firstRunDraft,
            "Plan the first repo task using project files, links, notes, and memory, with current sources and citations."
        )
        XCTAssertEqual(suggestions.map(\.title), ["Start plan", "Repo plan", "Research brief"])
        XCTAssertEqual(
            suggestions.first?.prompt,
            "Plan the first repo task using project files, links, notes, and memory, with current sources and citations."
        )
    }

    func testSetupNonPrivateTracksExposeStarterDraftWithoutGoal() {
        var researchProfile = UserSetupProfile.defaults
        researchProfile.useCase = .research
        researchProfile.useCases = [.research]

        var projectProfile = UserSetupProfile.defaults
        projectProfile.useCase = .teamProjects
        projectProfile.useCases = [.teamProjects]
        projectProfile.contextStyle = .project

        XCTAssertEqual(
            researchProfile.normalizedForDefaults.firstRunDraft,
            "Write a sourced brief on the latest AI developments, with dates, citations, and a short recommendation."
        )
        XCTAssertEqual(
            projectProfile.normalizedForDefaults.firstRunDraft,
            "Set up this Project: what files, links, instructions, and first chat to add?"
        )
    }

    func testSetupCTAIsDerivedFromSinglePlanState() {
        let cases: [(UserSetupUseCase, Bool, Bool, String)] = [
            (.privateChat, false, false, "Ask a private question"),
            (.research, false, false, "Start a research brief"),
            (.buildAgents, true, false, "Plan a build task"),
            (.teamProjects, false, false, "Create a Project")
        ]

        for wantsWeb in [false, true] {
            for (useCase, wantsIronclaw, wantsCouncil, expectedCTA) in cases {
                var profile = UserSetupProfile.defaults
                profile.useCase = useCase
                profile.useCases = [useCase]
                profile.wantsWeb = wantsWeb
                profile.wantsIronclaw = wantsIronclaw
                profile.wantsCouncil = wantsCouncil

                let plan = AppSetupPlan(profile: profile, readiness: .optimistic)

                XCTAssertEqual(plan.expectedFirstAction, expectedCTA)
            }
        }
    }


    @MainActor
    func testApplyingSetupWithoutGoalKeepsExistingDraft() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.draft = "Keep this draft."

        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]
        profile.contextStyle = .project

        store.applySetupProfile(profile)

        XCTAssertEqual(store.draft, "Keep this draft.")
    }


    @MainActor
    func testApplyingSetupWithoutGoalSeedsStarterDraftWhenComposerIsEmpty() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))

        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]
        profile.contextStyle = .project

        store.applySetupProfile(profile)

        XCTAssertEqual(store.draft, "Plan the first repo task: what to inspect, what to change, and which focused tests should run.")
    }


    @MainActor
    func testApplyingSetupWithGoalSeedsStarterDraft() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.draft = "Old draft"

        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research]
        profile.contextStyle = .project
        profile.goalText = "Map the strongest privacy proof workflow."

        store.applySetupProfile(profile)

        XCTAssertEqual(store.draft, "Write a sourced brief for this goal: Map the strongest privacy proof workflow.")
    }


    @MainActor
    func testApplyingSetupRerunRefreshesSetupGuideWithoutDuplicatingIt() throws {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))

        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]
        profile.contextStyle = .project
        profile.goalText = "Audit the onboarding build path."

        store.applySetupProfile(profile)

        let firstGuide = try XCTUnwrap(store.selectedProjectNotes.first(where: { $0.title == "Setup guide" }))
        let firstPromptNote = try XCTUnwrap(store.selectedProjectNotes.first(where: { $0.title == "Starter prompts" }))
        let firstSkillsNote = try XCTUnwrap(store.selectedProjectNotes.first(where: { $0.title == "Agent skills" }))
        XCTAssertTrue(firstGuide.text.contains("Audit the onboarding build path."))
        XCTAssertTrue(firstPromptNote.text.contains("Audit the onboarding build path."))
        XCTAssertTrue(firstSkillsNote.text.contains("Project Setup: Turn a repo or new idea into a tracked Project."))

        store.updateSelectedProjectInstructions("Keep these custom instructions.")
        store.saveMessageAsProjectNote(makeMessage(id: "setup-note-1", role: .assistant, text: "Remember to keep the first-run notes visible.", createdAt: Date()))

        profile.goalText = "Plan the first simulator-safe patch."
        store.applySetupProfile(profile)

        let setupGuides = store.selectedProjectNotes.filter { $0.title == "Setup guide" }
        let starterPromptNotes = store.selectedProjectNotes.filter { $0.title == "Starter prompts" }
        let skillNotes = store.selectedProjectNotes.filter { $0.title == "Agent skills" }
        XCTAssertEqual(setupGuides.count, 1)
        XCTAssertEqual(starterPromptNotes.count, 1)
        XCTAssertEqual(skillNotes.count, 1)
        XCTAssertTrue(setupGuides[0].text.contains("Plan the first simulator-safe patch."))
        XCTAssertFalse(setupGuides[0].text.contains("Audit the onboarding build path."))
        XCTAssertTrue(starterPromptNotes[0].text.contains("Plan the first simulator-safe patch."))
        XCTAssertFalse(starterPromptNotes[0].text.contains("Audit the onboarding build path."))
        XCTAssertTrue(skillNotes[0].text.contains("Project Setup: Turn a repo or new idea into a tracked Project."))
        XCTAssertEqual(store.selectedProjectInstructions, "Keep these custom instructions.")
        XCTAssertTrue(store.selectedProjectNotes.contains(where: {
            $0.title != "Setup guide" && $0.text.contains("Remember to keep the first-run notes visible.")
        }))
    }

    func testAppSetupPlanIDAndSummaryTrackExperienceMode() {
        var profile = UserSetupProfile.defaults
        profile.useCases = [.research, .teamProjects]
        profile.useCase = .research
        profile.contextStyle = .project
        profile.wantsCouncil = true

        var powerProfile = profile
        powerProfile.experienceMode = .power

        let beginnerPlan = AppSetupPlan(profile: profile, readiness: .optimistic)
        let powerPlan = AppSetupPlan(profile: powerProfile, readiness: .optimistic)

        XCTAssertNotEqual(beginnerPlan.id, powerPlan.id)
        XCTAssertTrue(beginnerPlan.id.contains("beginner"))
        XCTAssertTrue(powerPlan.id.contains("power"))
        XCTAssertEqual(beginnerPlan.experienceSummary, "Beginner mode starts simple; power routes stay available later.")
        XCTAssertEqual(powerPlan.experienceSummary, "Power mode keeps advanced routes visible.")
        XCTAssertEqual(powerPlan.modelRoute, .council)
    }

    func testMemoryStorePersistsDedupesAndBuildsContext() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-\(UUID().uuidString).json")
        let store = MemoryStore(fileURL: tempFile)
        XCTAssertNotNil(store.add("I prefer concise answers"))
        XCTAssertNotNil(store.add("My wife's surname is Dangwal"))
        XCTAssertNil(store.add("hi")) // too short

        // Case-insensitive de-dupe: no new item, count stays at 2.
        XCTAssertNotNil(store.add("i prefer concise answers"))
        XCTAssertEqual(store.items.count, 2)

        let block = try XCTUnwrap(store.contextBlock())
        XCTAssertTrue(block.contains("Dangwal"))

        // Reloads from disk.
        let reloaded = MemoryStore(fileURL: tempFile)
        XCTAssertEqual(reloaded.items.count, 2)
        XCTAssertTrue(reloaded.items.contains { $0.text == "My wife's surname is Dangwal" })

        // Targeted forget removes the matching fact only.
        XCTAssertEqual(reloaded.remove(matching: "concise answers"), 1)
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.remove(matching: "nonexistent"), 0)

        reloaded.clear()
        XCTAssertTrue(reloaded.items.isEmpty)
        XCTAssertNil(reloaded.contextBlock())

        try? FileManager.default.removeItem(at: tempFile)
    }

    func testHostileResearchAndAutomationPromptsDoNotCollapseIntoDefaults() throws {
        XCTAssertNil(QuickIntentParser.parse("Deep research Canton Network tokenomics, SEC filings, and exchange liquidity; make a tracker only if a listing changes; otherwise list sources."))
        XCTAssertTrue(RoutePlanner.promptNeedsLiveWeb("Deep research Canton Network tokenomics, SEC filings, and exchange liquidity; list dated sources and next actions."))

        guard case let .createTracker(papers) = QuickIntentParser.parse("scan arXiv for new papers about TEE attestation every weekday at 7am") else {
            return XCTFail("Expected recurring research scan to become a custom tracker.")
        }
        XCTAssertEqual(papers.kind, .customPrompt)
        XCTAssertEqual(papers.schedule, .weekdays(hour: 7, minute: 0))
        XCTAssertTrue(try XCTUnwrap(papers.prompt).lowercased().contains("tee attestation"))

        guard case let .createTracker(policy) = QuickIntentParser.parse("monitor Apple App Store policy changes monthly with citations and calendar-worthy follow-ups") else {
            return XCTFail("Expected policy monitoring to become a custom monthly tracker.")
        }
        XCTAssertEqual(policy.kind, .customPrompt)
        XCTAssertEqual(policy.schedule, .monthly(day: 1, hour: 8, minute: 0))
        XCTAssertTrue(try XCTUnwrap(policy.prompt).lowercased().contains("app store policy changes"))

        XCTAssertNil(
            QuickIntentParser.parse("check Canton token liquidity every 30 minutes"),
            "Unsupported minute cadences must not default to a daily tracker."
        )
        XCTAssertNil(
            QuickIntentParser.parse("create a quarterly briefing on private company valuations"),
            "Unsupported quarterly cadence must not default to a daily tracker."
        )
        guard case let .createTracker(secFilings) = QuickIntentParser.parse("scan SEC filings every business day at 7am") else {
            return XCTFail("Expected business-day monitoring to become a weekday tracker.")
        }
        XCTAssertEqual(secFilings.schedule, .weekdays(hour: 7, minute: 0))

        XCTAssertNil(QuickIntentParser.parse("create calendar invites from this supplement sheet only after I approve exact times"))
        let supplementPrompt = ActionSurfacePlanner.augmentedPrompt(
            text: "Create calendar invites from this supplement sheet only after I approve exact times.",
            attachmentNames: ["AV- Blueprxnt Client Master Sheet (1).xlsx"]
        )
        XCTAssertTrue(supplementPrompt.contains("missing_fields"))
        XCTAssertTrue(supplementPrompt.contains("Do not invent concrete times"))
        XCTAssertTrue(supplementPrompt.contains("show a preview first"))

        XCTAssertNil(QuickIntentParser.parse("put Netflix and Disney on my movie watchlist tonight"))
        guard case let .createTracker(financeWatchlist) = QuickIntentParser.parse("track Netflix and Disney stocks every morning") else {
            return XCTFail("Expected finance watchlist for explicit stocks.")
        }
        XCTAssertEqual(financeWatchlist.kind, .watchlist)
        XCTAssertEqual(financeWatchlist.subject, "stock:NFLX|stock:DIS")

        XCTAssertNil(QuickIntentParser.parse("what's the ETH price, no web"))
        XCTAssertNil(QuickIntentParser.parse("weather in Tokyo, no internet"))
        XCTAssertNil(QuickIntentParser.parse("research FDA supplement recalls every morning without web"))

        guard case let .createTracker(routine) = QuickIntentParser.parse("remind me to take magnesium every morning at 8am no web") else {
            return XCTFail("Non-network recurring reminders should still work with a no-web instruction.")
        }
        XCTAssertEqual(routine.title, "take magnesium")

        let pureResearch = "Research Canton Network tokenomics with dated sources and summarize risks."
        XCTAssertEqual(
            ActionSurfacePlanner.augmentedPrompt(text: pureResearch, attachmentNames: []),
            pureResearch
        )
    }

    func testBriefingPersistsPinAndSnooze() throws {
        var briefing = Briefing(title: "X", prompt: "p", schedule: .daily(hour: 8, minute: 0), kind: .cryptoPrice, accountID: "near")
        briefing.isPinned = true
        briefing.snoozedUntil = Date().addingTimeInterval(3600)
        let data = try JSONEncoder().encode(briefing)
        let decoded = try JSONDecoder().decode(Briefing.self, from: data)
        XCTAssertTrue(decoded.isPinned)
        XCTAssertNotNil(decoded.snoozedUntil)
    }
}
