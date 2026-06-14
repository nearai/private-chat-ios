import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testProjectPersistenceStoresProjectsSortedAndSelectedProjectScoped() throws {
        let defaults = try makeIsolatedDefaults()
        let accountID = "project-cache-\(UUID().uuidString)"
        let persistence = ProjectPersistence(accountID: accountID, defaults: defaults)
        defer {
            FileCache(accountID: accountID, defaults: defaults).remove(
                filename: ProjectPersistence.cacheFilename,
                legacyDefaultsKey: ProjectPersistence.legacyDefaultsKey
            )
            defaults.removeObject(forKey: persistence.selectedProjectDefaultsKey())
        }

        let older = ChatProject(
            id: "project-older",
            name: "Older",
            createdAt: Date(timeIntervalSince1970: 10),
            conversationIDs: []
        )
        let newer = ChatProject(
            id: "project-newer",
            name: "Newer",
            createdAt: Date(timeIntervalSince1970: 20),
            conversationIDs: []
        )

        XCTAssertTrue(persistence.saveProjects([older, newer]))
        persistence.saveSelectedProjectID(older.id)

        XCTAssertEqual(persistence.loadProjects().map(\.id), [newer.id, older.id])
        XCTAssertEqual(persistence.loadSelectedProjectID(), older.id)

        let other = ProjectPersistence(accountID: "project-cache-other-\(UUID().uuidString)", defaults: defaults)
        XCTAssertNil(other.loadSelectedProjectID())
    }

    @MainActor
    func testProjectStorePersistsProjectsAndSelectedProjectThroughProjectPersistence() throws {
        let defaults = try makeIsolatedDefaults()
        let accountID = "project-store-\(UUID().uuidString)"
        let persistence = ProjectPersistence(accountID: accountID, defaults: defaults)
        defer {
            FileCache(accountID: accountID, defaults: defaults).remove(
                filename: ProjectPersistence.cacheFilename,
                legacyDefaultsKey: ProjectPersistence.legacyDefaultsKey
            )
            defaults.removeObject(forKey: persistence.selectedProjectDefaultsKey())
        }

        let store = ProjectStore(persistence: persistence)
        let project = try XCTUnwrap(store.createProject(named: " Launch Room "))

        let restored = ProjectStore(persistence: persistence)
        restored.loadPersistedState()

        XCTAssertEqual(restored.projects.map(\.id), [project.id])
        XCTAssertEqual(restored.selectedProjectID, project.id)
        XCTAssertEqual(restored.selectedProject?.name, "Launch Room")
    }

    @MainActor
    func testProjectStoreNormalizesAndDeduplicatesProjectLinks() throws {
        let store = ProjectStore()
        store.createProject(named: "Sources")

        let first = try XCTUnwrap(store.addSelectedProjectLink(title: "NEAR", url: "near.ai/docs"))
        let duplicate = store.addSelectedProjectLink(title: "NEAR duplicate", url: "https://near.ai/docs")

        XCTAssertEqual(first.urlString, "https://near.ai/docs")
        XCTAssertNil(duplicate)
        XCTAssertEqual(store.selectedProjectLinks.map(\.urlString), ["https://near.ai/docs"])
    }

    @MainActor
    func testProjectStoreEnforcesNoteLimitAndClipsLongNotes() throws {
        let store = ProjectStore()
        store.createProject(named: "Notes")

        for index in 0..<ProjectService.maxNotes {
            store.addSelectedProjectNote(title: "Note \(index)", text: "Body \(index)")
        }

        XCTAssertEqual(store.selectedProjectNotes.count, ProjectService.maxNotes)
        XCTAssertNil(store.addSelectedProjectNote(title: "Too much", text: "Overflow"))

        let longText = String(repeating: "x", count: ProjectService.maxNoteTextCharacters + 20)
        let service = ProjectService()
        let result = service.makeNote(title: "", text: longText, isLocalOnly: false, existingNotes: [])

        let clipped = try XCTUnwrap(result.note)
        XCTAssertEqual(clipped.text.count, ProjectService.maxNoteTextCharacters + 3)
        XCTAssertTrue(clipped.text.hasSuffix("..."))
    }

    @MainActor
    func testProjectStoreArchiveClearsSelectedProjectAndHidesArchivedProject() throws {
        let store = ProjectStore()
        let project = try XCTUnwrap(store.createProject(named: "Archive Me"))

        store.archiveProject(project)

        XCTAssertNil(store.selectedProjectID)
        XCTAssertNil(store.selectedProject)
        XCTAssertTrue(store.visibleProjects.isEmpty)
        XCTAssertEqual(store.archivedProjects.map(\.id), [project.id])
    }

    @MainActor
    func testProjectStoreSetupSeedRefreshesManagedNotesWithoutDroppingUserNotes() throws {
        let store = ProjectStore()
        let project = try XCTUnwrap(store.createProject(named: "Setup"))
        store.addSelectedProjectNote(title: "User decision", text: "Keep this.")

        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]
        profile.contextStyle = .project
        profile.goalText = "Review the repo."
        let plan = AppSetupPlan(profile: profile.normalizedForDefaults, readiness: .optimistic)

        store.seedSetupMetadata(projectID: project.id, profile: profile.normalizedForDefaults, plan: plan)

        XCTAssertEqual(Array(store.selectedProjectNotes.prefix(3).map(\.title)), ["Setup guide", "Starter prompts", "Agent skills"])
        XCTAssertTrue(store.selectedProjectNotes.contains { $0.title == "User decision" && $0.text == "Keep this." })
        XCTAssertEqual(store.selectedProject?.projectIconName, ProjectIcon.agent.symbolName)
    }

    @MainActor
    func testProjectStorePromptContextAndAgentToolRoutingUseProjectOwner() throws {
        let store = ProjectStore()
        store.createProject(named: "Agent Room")

        let local = ProjectNote(title: "Private table", text: "Only on device", isLocalOnly: true)
        let shared = ProjectNote(title: "Decision", text: "Can route")
        XCTAssertEqual(ProjectService.projectNotesForPrompt([shared, local], allowLocalOnly: false), [shared])
        XCTAssertEqual(ProjectService.projectNotesForPrompt([shared, local], allowLocalOnly: true), [shared, local])

        let linkResult = store.addSourceLinkToSelectedProject(title: "Source", url: "near.ai")
        XCTAssertEqual(linkResult.status, .completed)
        XCTAssertEqual(store.selectedProjectLinks.map(\.urlString), ["https://near.ai"])

        let instructionsResult = store.setSelectedProjectInstructionsForTool(" Use this project context. ")
        XCTAssertEqual(instructionsResult.status, .completed)
        XCTAssertEqual(store.selectedProjectInstructions, "Use this project context.")

        let memoryResult = store.updateSelectedProjectMemoryForTool("Remember this.", append: false)
        XCTAssertEqual(memoryResult.status, .completed)
        XCTAssertEqual(store.selectedProjectMemorySummary, "Remember this.")

        let fileResult = store.addPromptFilesToSelectedProject(
            [ChatAttachment(id: "file-1", name: "brief.pdf", kind: "file", bytes: 128)],
            maxAttachments: 12
        )
        XCTAssertEqual(fileResult.status, .completed)
        XCTAssertEqual(store.selectedProjectAttachments.map(\.id), ["file-1"])
    }

    func testHomeSearchContextMatchesSurfaceExplicitProjectHits() {
        let project = ChatProject(
            id: "project-1",
            name: "Launch Room",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            conversationIDs: [],
            attachments: [
                ChatAttachment(id: "file-1", name: "launch-brief.pdf", kind: "file", bytes: 2_048)
            ],
            instructions: "Use the launch checklist and summarize risks clearly.",
            memorySummary: "Remember the launch owner requested an executive summary.",
            links: [
                ProjectLink(id: "link-1", title: "Launch plan", urlString: "https://near.ai/launch-plan")
            ],
            notes: [
                ProjectNote(id: "note-1", title: "Risk note", text: "Flag launch blockers before signoff.")
            ]
        )

        let fileMatches = HomeSearchIndex.projectContextMatches(query: "brief", projects: [project])
        XCTAssertEqual(fileMatches.map(\.kind), [.file])
        XCTAssertEqual(fileMatches.map(\.title), ["launch-brief.pdf"])

        let linkMatches = HomeSearchIndex.projectContextMatches(query: "launch-plan", projects: [project])
        XCTAssertEqual(linkMatches.map(\.kind), [.link])
        XCTAssertEqual(linkMatches.first?.detail, "near.ai")

        let noteMatches = HomeSearchIndex.projectContextMatches(query: "blockers", projects: [project])
        XCTAssertEqual(noteMatches.map(\.kind), [.note])
        XCTAssertEqual(noteMatches.first?.title, "Risk note")

        let instructionMatches = HomeSearchIndex.projectContextMatches(query: "checklist", projects: [project])
        XCTAssertEqual(instructionMatches.map(\.kind), [.instructions])
        XCTAssertEqual(instructionMatches.first?.title, "Project instructions")

        let memoryMatches = HomeSearchIndex.projectContextMatches(query: "executive summary", projects: [project])
        XCTAssertEqual(memoryMatches.map(\.kind), [.memory])
        XCTAssertEqual(memoryMatches.first?.title, "Memory summary")
    }

    func testHomeOrchestrationPlannerPromotesOnlySelectedProjectContext() {
        let selected = ChatProject(
            id: "project-selected",
            name: "Private Chat iOS",
            createdAt: Date(timeIntervalSince1970: 1_700_100_000),
            conversationIDs: [],
            instructions: "Ship the agentic workboard.",
            iconName: ProjectIcon.agent.symbolName
        )
        let other = ChatProject(
            id: "project-other",
            name: "Other",
            createdAt: Date(timeIntervalSince1970: 1_700_200_000),
            conversationIDs: []
        )

        let plan = HomeOrchestrationPlanner.make(
            briefings: [],
            projects: [other, selected],
            conversations: [],
            selectedProjectID: selected.id,
            isStreaming: false,
            routeLabel: "IronClaw",
            isCouncilModeEnabled: false,
            defaultCouncilModelCount: 0,
            councilModelNames: [],
            hostedAgentAvailable: true,
            mobileAgentAvailable: false
        )

        let projectItem = plan.liveItems.first(where: { $0.kind == .project })
        XCTAssertEqual(projectItem?.id, "project-\(selected.id)")
        XCTAssertEqual(projectItem?.title, "Private Chat iOS")
        XCTAssertEqual(projectItem?.action, .openProject(selected.id))
        XCTAssertFalse(plan.liveItems.contains { $0.id == "agent-builder" })
        XCTAssertTrue(plan.commands.isEmpty)
    }

    func testProjectIdentityDefaultsAndEncoding() throws {
        let legacyPayload = Data("""
        {
          "id": "project-1",
          "name": "Legacy",
          "createdAt": 123,
          "conversationIDs": [],
          "attachments": [],
          "instructions": "",
          "memorySummary": "",
          "links": [],
          "notes": []
        }
        """.utf8)

        let legacyProject = try JSONDecoder().decode(ChatProject.self, from: legacyPayload)
        XCTAssertEqual(legacyProject.projectIconName, ProjectIcon.folder.symbolName)
        XCTAssertEqual(legacyProject.projectPalette, .sky)

        let project = ChatProject(
            id: "project-2",
            name: "Agent Build",
            createdAt: Date(timeIntervalSince1970: 123),
            conversationIDs: [],
            iconName: ProjectIcon.agent.symbolName,
            paletteName: ProjectPalette.mint.rawValue
        )
        let encoded = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(ChatProject.self, from: encoded)

        XCTAssertEqual(decoded.projectIconName, ProjectIcon.agent.symbolName)
        XCTAssertEqual(decoded.projectPalette, .mint)
        XCTAssertFalse(decoded.isArchived)
    }

    func testProjectWorkspaceStarterPresetUsesProjectFirstDefaults() {
        let profile = UserSetupStarterPreset.projectWorkspace.quickStartProfile

        XCTAssertEqual(profile.useCases, [.teamProjects])
        XCTAssertEqual(profile.contextStyle, .project)
        XCTAssertEqual(profile.goalText, "")
        XCTAssertFalse(profile.wantsWeb)
        XCTAssertFalse(profile.wantsCouncil)
        XCTAssertFalse(profile.wantsIronclaw)
        XCTAssertEqual(profile.experienceMode, .beginner)
        XCTAssertEqual(profile.firstRunDraft, UserSetupUseCase.teamProjects.starterPrompt)
    }

    func testSetupGoalCreatesFirstRunDraftAndProjectInstructions() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research]
        profile.contextStyle = .project
        profile.goalText = "  Map the strongest privacy proof workflow.  "

        let normalized = profile.normalizedForDefaults
        let plan = AppSetupPlan(profile: normalized, readiness: .optimistic)

        XCTAssertEqual(normalized.firstRunDraft, "Write a sourced brief for this goal: Map the strongest privacy proof workflow.")
        XCTAssertTrue(normalized.setupProjectInstructions.contains("Setup goal: Map the strongest privacy proof workflow."))
        XCTAssertEqual(plan.firstRunDraft, normalized.firstRunDraft)
        XCTAssertEqual(plan.expectedFirstAction, "Start from your goal")
    }

    func testSetupProjectInstructionsCombineMultipleUseCases() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research, .teamProjects]
        profile.contextStyle = .project
        profile.goalText = "Keep project context tidy for a cited brief."

        let instructions = profile.normalizedForDefaults.setupProjectInstructions

        XCTAssertTrue(instructions.contains("This Project was configured for: Research with sources, Work in a Project."))
        XCTAssertTrue(instructions.contains("Research with sources: Prioritize dated sources, citations, contradictions, and a concise recommendation. Save strong outputs as Project notes."))
        XCTAssertTrue(instructions.contains("Work in a Project: Use Project files, saved links, notes, and outputs before broad web. Keep context tidy; ask only when a missing source blocks progress."))
        XCTAssertTrue(instructions.contains("Setup goal: Keep project context tidy for a cited brief."))
    }

    func testSetupLaunchCardMetadataFallsBackToRouteFocusAndProject() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .teamProjects
        profile.useCases = [.teamProjects]
        profile.contextStyle = .project

        let plan = AppSetupPlan(profile: profile, readiness: .optimistic)

        XCTAssertEqual(plan.launchCardMetadata, ["Private model", "Project", "Project Hub"])
        XCTAssertEqual(plan.launchCardSubtitle, "Ready now: Private model · Project · Project Hub")
    }


    @MainActor
    func testApplyingSetupSeedsStarterPromptAndSkillNotesInProject() throws {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))

        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]
        profile.contextStyle = .project
        profile.goalText = "Review the repo and plan the first safe patch."

        store.applySetupProfile(profile)

        let notes = store.selectedProjectNotes
        XCTAssertEqual(Array(notes.prefix(3).map(\.title)), ["Setup guide", "Starter prompts", "Agent skills"])

        let promptNote = try XCTUnwrap(notes.first(where: { $0.title == "Starter prompts" }))
        XCTAssertTrue(promptNote.text.contains("Plan repo task"))
        XCTAssertTrue(promptNote.text.contains("Plan the first repo task for this goal: Review the repo and plan the first safe patch."))

        let skillsNote = try XCTUnwrap(notes.first(where: { $0.title == "Agent skills" }))
        XCTAssertTrue(skillsNote.text.contains("Project Setup: Turn a repo or new idea into a tracked Project."))
        XCTAssertTrue(skillsNote.text.contains("Plan Mode: Break work into concrete, verifiable next steps."))
    }


    @MainActor
    func testSavingAssistantOutputWithoutProjectOpensProjectSavePrompt() throws {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.selectedProjectID = nil
        let message = makeMessage(
            id: "assistant-note-1",
            role: .assistant,
            text: "Decision: ship the project save prompt.",
            createdAt: Date()
        )

        store.saveMessageAsProjectNote(message)

        XCTAssertEqual(store.pendingProjectNoteSaveMessage?.id, "assistant-note-1")
        XCTAssertEqual(store.bannerMessage, "Create or choose a project to save this output.")
        XCTAssertTrue(store.projects.isEmpty)
    }


    @MainActor
    func testCreateProjectAndSaveMessageAsNotePersistsTheOutput() throws {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        let message = makeMessage(
            id: "assistant-note-2",
            role: .assistant,
            text: "Action: create the briefing builder.",
            createdAt: Date()
        )
        store.saveMessageAsProjectNote(message)

        store.createProjectAndSaveMessageAsNote(
            message,
            named: "Briefing Builder",
            instructions: "Keep saved outputs actionable."
        )

        let project = try XCTUnwrap(store.selectedProject)
        XCTAssertEqual(project.name, "Briefing Builder")
        XCTAssertEqual(project.instructions, "Keep saved outputs actionable.")
        XCTAssertNil(store.pendingProjectNoteSaveMessage)
        XCTAssertEqual(store.selectedProjectNotes.first?.sourceMessageID, "assistant-note-2")
        XCTAssertTrue(store.selectedProjectNotes.first?.text.contains("briefing builder") == true)
    }


    @MainActor
    func testVisibleSaveActionPromptsEvenWhenProjectIsSelected() throws {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.createProject(named: "Existing Workspace")
        let message = makeMessage(
            id: "assistant-note-3",
            role: .assistant,
            text: "Decision: make saving explicit.",
            createdAt: Date()
        )

        store.requestProjectNoteSave(for: message)

        XCTAssertEqual(store.pendingProjectNoteSaveMessage?.id, "assistant-note-3")
        XCTAssertTrue(store.selectedProjectNotes.isEmpty)
    }


    @MainActor
    func testProjectNoteManagementUpdatesAndDeletesSelectedNote() throws {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.createProject(named: "Notes")

        store.addSelectedProjectNote(
            title: " Draft decision ",
            text: " Keep this on device. ",
            isLocalOnly: true
        )

        let original = try XCTUnwrap(store.selectedProjectNotes.first)
        XCTAssertTrue(original.isLocalOnly)
        XCTAssertEqual(original.projectContextStatusTitle, "Local-only")

        store.updateSelectedProjectNote(
            original,
            title: " Edited decision ",
            text: " Share this with selected Project routes. ",
            isLocalOnly: false
        )

        let updated = try XCTUnwrap(store.selectedProjectNotes.first)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.title, "Edited decision")
        XCTAssertEqual(updated.text, "Share this with selected Project routes.")
        XCTAssertFalse(updated.isLocalOnly)
        XCTAssertEqual(updated.projectContextStatusTitle, "Can route")
        XCTAssertEqual(store.bannerMessage, "Project note updated.")

        store.deleteProjectNote(updated)

        XCTAssertTrue(store.selectedProjectNotes.isEmpty)
        XCTAssertEqual(store.bannerMessage, "Project note removed.")
    }


    @MainActor
    func testHostedHandoffFingerprintChangesWhenProjectNoteTextChanges() throws {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.ironclawSettings = IronclawSettings(
            isEnabled: true,
            baseURL: "https://agent.example.com",
            threadID: ""
        )
        store.createProject(named: "Hosted Handoff")
        store.addSelectedProjectNote(title: "Decision", text: "Use focused tests first.")
        store.selectModel(ModelOption.ironclawModelID)
        store.draft = "Run the repo test plan."

        store.sendDraft()
        let firstFingerprint = try XCTUnwrap(store.pendingHostedHandoffPreflight?.fingerprint)
        let note = try XCTUnwrap(store.selectedProjectNotes.first)

        store.updateSelectedProjectNote(note, title: "Decision", text: "Run UI screenshots before tests.", isLocalOnly: false)
        store.sendDraft()

        XCTAssertNotEqual(store.pendingHostedHandoffPreflight?.fingerprint, firstFingerprint)
    }

    func testIronclawSkillMissionPromptUsesProjectContextWhenBlank() throws {
        let skill = try XCTUnwrap(IronclawSkillCatalog.all.first(where: { $0.id == "coding" }))

        let prompt = skill.missionPrompt(projectName: "NEAR Private Chat")

        XCTAssertTrue(prompt.contains("Use the NEAR Private Chat project context when it helps."))
        XCTAssertTrue(prompt.contains("Inspect this code task."))
        XCTAssertTrue(prompt.contains("make the smallest useful patch"))
    }


    @MainActor
    func testEmptyChatStarterPrepareProjectRequestsPickerWhenNoProjectIsSelected() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        let suggestion = EmptyChatStarterSuggestion(
            title: "Use files",
            symbolName: "paperclip",
            prompt: "Use the attached files to answer: ",
            action: .project
        )
        var openedProjectPicker = false

        let ready = EmptyChatStarterCoordinator.prepare(
            suggestion,
            to: store,
            onOpenProject: { openedProjectPicker = true }
        )

        XCTAssertFalse(ready)
        XCTAssertTrue(openedProjectPicker)
        XCTAssertEqual(store.sourceMode, .files)
    }


    @MainActor
    func testEmptyChatStarterPrepareProjectUsesProjectContextWhenAvailable() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.createProject(named: "Launch")
        let suggestion = EmptyChatStarterSuggestion(
            title: "Use files",
            symbolName: "paperclip",
            prompt: "Use the attached files to answer: ",
            action: .project
        )

        let ready = EmptyChatStarterCoordinator.prepare(suggestion, to: store)

        XCTAssertTrue(ready)
        XCTAssertEqual(store.selectedProject?.name, "Launch")
        XCTAssertEqual(store.sourceMode, .all)
    }

    func testProjectNotesForPromptFiltersLocalOnlyRows() {
        let normal = ProjectNote(title: "Decision", text: "Ship the parser.")
        let local = ProjectNote(title: "Table rows: supplements.csv", text: "Private rows", isLocalOnly: true)

        XCTAssertEqual(ProjectService.projectNotesForPrompt([normal, local], allowLocalOnly: false), [normal])
        XCTAssertEqual(ProjectService.projectNotesForPrompt([normal, local], allowLocalOnly: true), [normal, local])
    }

    func testProjectActionPromptFactoryFindActionsRequestsStructuredActionPlan() {
        let prompt = ProjectActionPromptFactory.prompt(for: .findActions, projectName: "Client Ops")

        XCTAssertTrue(prompt.contains("Client Ops"))
        XCTAssertTrue(prompt.contains("structured fields"))
        XCTAssertTrue(prompt.contains("missing_fields"))
        XCTAssertTrue(prompt.contains("near-widget action_plan"))
    }

    func testBriefingThreadReplyContextPrefersWidgetNote() {
        // The follow-up the model answers is grounded in the delivery's result.
        let widget = MessageWidget(kind: .generic, title: "Global politics", note: "Top 5 developments: Iran, Lebanon, EU sanctions")
        let delivery = BriefingDelivery(dayLabel: "Today", time: "9:00am", title: "briefing", widget: widget)
        XCTAssertTrue(ThreadedBriefingView.replyContext(for: delivery).contains("Top 5 developments"))
        // Falls back to text fields when there's no widget.
        let textOnly = BriefingDelivery(dayLabel: "Today", time: "9:00am", title: "briefing", headline: "Markets up", summary: "S&P +1%")
        let ctx = ThreadedBriefingView.replyContext(for: textOnly)
        XCTAssertTrue(ctx.contains("Markets up") && ctx.contains("S&P +1%"))
    }


    @MainActor
    func testEmptyChatStarterCoordinatorProjectActionOpensPickerWhenNoProjectIsSelected() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        var didOpenProjectPicker = false
        let suggestion = EmptyChatStarterSuggestion(
            title: "Use files",
            symbolName: "paperclip",
            prompt: "Use the attached files to answer: ",
            action: .project
        )

        let shouldFocusComposer = EmptyChatStarterCoordinator.apply(
            suggestion,
            to: store,
            onOpenProject: {
                didOpenProjectPicker = true
            }
        )

        XCTAssertFalse(shouldFocusComposer)
        XCTAssertTrue(didOpenProjectPicker)
        XCTAssertEqual(store.sourceMode, .files)
    }
}
