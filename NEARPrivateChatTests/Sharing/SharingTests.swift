import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testAppDeepLinkDraftIsCappedBeforeConfirmation() throws {
        var components = URLComponents(string: "nearprivatechat://agent")!
        components.queryItems = [
            URLQueryItem(name: "prompt", value: String(repeating: "a", count: AppDeepLinkAction.maxDraftCharacters + 500))
        ]

        let action = try XCTUnwrap(AppDeepLinkAction.parse(components.url!))

        XCTAssertEqual(action.draft?.count, AppDeepLinkAction.maxDraftCharacters)
    }

    func testSharedConversationPresentationUsesReadableSourceLabels() {
        XCTAssertEqual(
            SharedConversationPresentation.sourceBadgeTitle(for: SharedConversationPresentation.accountShareLabel),
            "NEAR account"
        )
        XCTAssertEqual(
            SharedConversationPresentation.sourceDescription(for: SharedConversationPresentation.accountShareLabel),
            SharedConversationPresentation.accountShareLabel
        )
        XCTAssertEqual(
            SharedConversationPresentation.sourceBadgeTitle(for: "https://www.private.near.ai/c/conv-shared"),
            "private.near.ai"
        )
        XCTAssertEqual(
            SharedConversationPresentation.sourceDescription(for: "conv_shared_123"),
            "Opened from a conversation ID"
        )
    }

    func testSharedConversationInfoExposesReadableAccessAndSourceCopy() throws {
        let payload = Data("""
        {
          "conversation_id": "conv-shared",
          "permission": "read",
          "title": "Launch sync",
          "created_at": 1700000000
        }
        """.utf8)

        let item = try JSONDecoder().decode(SharedConversationInfo.self, from: payload)

        XCTAssertEqual(item.accessBadgeTitle, "Read-only")
        XCTAssertEqual(item.sourceLabel, SharedConversationPresentation.accountShareLabel)
        XCTAssertFalse(item.canWrite)
    }

    @MainActor
    func testShareStoreRefreshSharedWithMeSortsNewestFirst() async throws {
        let shareAPI = ShareAPIFake()
        shareAPI.sharedWithMeResult = [
            SharedConversationInfo(conversationID: "conv-old", permission: "read", title: "Old", createdAt: 10, error: nil),
            SharedConversationInfo(conversationID: "conv-new", permission: "write", title: "New", createdAt: 20, error: nil)
        ]
        let store = makeShareStore(shareAPI: shareAPI)

        await store.refreshSharedWithMe()

        XCTAssertEqual(store.sharedWithMe.map(\.conversationID), ["conv-new", "conv-old"])
        XCTAssertFalse(store.isLoadingSharedWithMe)
    }

    @MainActor
    func testShareStoreShareGroupsUpsertDeleteAndSort() async throws {
        let shareAPI = ShareAPIFake()
        shareAPI.shareGroupsResult = [
            shareGroup(id: "z", name: "Zeta"),
            shareGroup(id: "a", name: "Alpha")
        ]
        shareAPI.createGroupResult = shareGroup(id: "m", name: "Middle")
        shareAPI.updateGroupResult = shareGroup(id: "z", name: "Beta")
        let store = makeShareStore(shareAPI: shareAPI)

        await store.refreshShareGroups()
        XCTAssertEqual(store.shareGroups.map(\.name), ["Alpha", "Zeta"])

        await store.createShareGroup(name: "Middle", rawMembers: "middle@example.com")
        XCTAssertEqual(store.shareGroups.map(\.name), ["Alpha", "Middle", "Zeta"])

        await store.updateShareGroup(shareGroup(id: "z", name: "Zeta"), name: "Beta", rawMembers: "beta@example.com")
        XCTAssertEqual(store.shareGroups.map(\.name), ["Alpha", "Beta", "Middle"])

        await store.deleteShareGroup(shareGroup(id: "a", name: "Alpha"))
        XCTAssertEqual(store.shareGroups.map(\.name), ["Beta", "Middle"])
        XCTAssertEqual(shareAPI.deletedGroupIDs, ["a"])
    }

    @MainActor
    func testShareStorePublicEnableDisableReloadsShareInfo() async throws {
        let shareAPI = ShareAPIFake()
        let conversation = conversationSummary(id: "conv-public")
        shareAPI.conversationShares[conversation.id] = shareInfo(conversationID: conversation.id, shares: [])
        let store = makeShareStore(shareAPI: shareAPI)

        let url = await store.enablePublicShare(for: conversation)

        XCTAssertEqual(url?.absoluteString, "https://private.near.ai/c/conv-public")
        XCTAssertEqual(shareAPI.createPublicShareConversationIDs, ["conv-public"])
        XCTAssertNotNil(store.shareInfo?.publicShare)

        await store.disablePublicShare(for: conversation)

        XCTAssertEqual(shareAPI.deletedConversationShares.map(\.conversationID), ["conv-public"])
        XCTAssertNil(store.shareInfo?.publicShare)
    }

    @MainActor
    func testShareStoreDirectRecipientParsingDedupsAndRecordsGrant() async throws {
        let shareAPI = ShareAPIFake()
        let conversation = conversationSummary(id: "conv-direct")
        shareAPI.conversationShares[conversation.id] = shareInfo(conversationID: conversation.id, shares: [])
        let store = makeShareStore(shareAPI: shareAPI)

        let recipients = ShareStore.shareInviteRecipients(
            from: "Alice@Example.com, alice@example.com; bob.near\nbad url"
        )
        XCTAssertEqual(recipients.map(\.kind), ["email", "near_account"])
        XCTAssertEqual(recipients.map(\.value), ["alice@example.com", "bob.near"])

        await store.grantDirectShare(
            rawRecipients: "Alice@Example.com, alice@example.com; bob.near",
            permission: "WRITE",
            conversation: conversation
        )

        XCTAssertEqual(shareAPI.createdDirectShares.count, 1)
        XCTAssertEqual(shareAPI.createdDirectShares[0].permission, "write")
        XCTAssertEqual(shareAPI.createdDirectShares[0].recipients.map(\.value), ["alice@example.com", "bob.near"])
    }

    @MainActor
    func testShareStoreOrganizationPatternNormalizationAndInvalidMembers() async throws {
        let shareAPI = ShareAPIFake()
        let conversation = conversationSummary(id: "conv-org")
        shareAPI.conversationShares[conversation.id] = shareInfo(conversationID: conversation.id, shares: [])
        let banners = BannerCapture()
        let store = makeShareStore(shareAPI: shareAPI, banners: banners)

        XCTAssertEqual(ShareStore.normalizedOrganizationEmailPattern("NEAR.ORG"), "*@near.org")
        XCTAssertEqual(ShareStore.normalizedOrganizationEmailPattern("*@Example.COM"), "*@example.com")
        XCTAssertNil(ShareStore.normalizedOrganizationEmailPattern("not a domain"))

        await store.grantOrganizationShare(emailPattern: "NEAR.ORG", permission: "read", conversation: conversation)
        XCTAssertEqual(shareAPI.createdOrganizationShares.map(\.emailPattern), ["*@near.org"])

        await store.createShareGroup(name: "Invalid", rawMembers: "not valid::::")
        XCTAssertEqual(banners.messages.last, "Add at least one group member.")
        XCTAssertEqual(shareAPI.createdGroupNames, [])
    }

    @MainActor
    func testShareStoreSharedPreviewParsesKnownAndFetchedCanWrite() async throws {
        let shareAPI = ShareAPIFake()
        let conversationAPI = ConversationAPIFake()
        conversationAPI.readableConversation = conversationSummary(id: "conv-preview")
        conversationAPI.readableItems = ConversationItemsResponse(data: [], firstID: nil, hasMore: false, lastID: nil)
        shareAPI.conversationShares["conv-preview"] = shareInfo(
            conversationID: "conv-preview",
            canWrite: true,
            shares: []
        )
        let store = makeShareStore(shareAPI: shareAPI, conversationAPI: conversationAPI)

        await store.openSharedConversation(from: "https://private.near.ai/c/conv-preview")
        XCTAssertEqual(store.sharedPreview?.conversation.id, "conv-preview")
        XCTAssertTrue(store.sharedPreview?.canWrite == true)

        await store.openSharedConversation(
            from: "conv-preview",
            knownCanWrite: false,
            sourceLabel: SharedConversationPresentation.accountShareLabel
        )
        XCTAssertFalse(store.sharedPreview?.canWrite == true)
        XCTAssertEqual(store.sharedPreview?.source, SharedConversationPresentation.accountShareLabel)
    }

    func testProjectWorkspaceStarterPresetPreviewUsesProjectWorkspaceMessaging() {
        let routeDefaults = SetupRouteDefaults(
            privateModelID: "private-model",
            councilModelIDs: ["council-a", "council-b"],
            ironclawMobileModelID: ModelOption.ironclawMobileModelID
        )

        let plan = UserSetupStarterPreset.projectWorkspace.previewPlan(
            readiness: .optimistic,
            routeDefaults: routeDefaults
        )

        XCTAssertEqual(plan.modelRoute, .privateModel)
        XCTAssertEqual(plan.expectedFirstAction, "Create a Project")
        XCTAssertEqual(plan.focusMode, .all)
        XCTAssertEqual(plan.starterProjectName, "Project Hub")
        XCTAssertEqual(plan.expectedRouteModelIDs, ["private-model"])
        XCTAssertEqual(plan.firstRunDraft, UserSetupUseCase.teamProjects.starterPrompt)
    }

    func testAppSetupPlanExposesStarterWorkspaceAndPromptPreview() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]
        profile.contextStyle = .project
        profile.goalText = "Review the repo and plan the first safe patch."

        let plan = AppSetupPlan(profile: profile, readiness: .optimistic)

        XCTAssertEqual(plan.starterWorkspaceSeeds.map(\.title), ["Project", "Repo plan", "Setup guide", "Goal"])
        XCTAssertEqual(plan.starterWorkspaceSeeds.first?.detail, "Build Project opens as the active project for your first chats.")
        XCTAssertEqual(
            plan.starterWorkspaceSeeds.dropFirst().first?.detail,
            "Starter prompts ask for a safe patch plan and focused verification before code changes."
        )
        XCTAssertEqual(
            plan.starterSkillSuggestions.map(\.id),
            ["project-setup", "plan-mode", "developer-setup", "coding"]
        )
        XCTAssertEqual(plan.starterPromptSuggestions.map(\.title), ["Plan repo task", "Safe patch", "Repo checklist"])
        XCTAssertEqual(plan.starterPromptSuggestions.first?.prompt, "Plan the first repo task for this goal: Review the repo and plan the first safe patch.")
    }


    @MainActor
    func testProjectContextRoutePreviewOmitsLocalOnlyNotesForHostedIronclaw() throws {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.createProject(named: "Hosted IronClaw")
        store.sourceMode = .all
        store.webSearchEnabled = false
        store.selectedModel = ModelOption.ironclawModelID

        store.addSelectedProjectNote(title: "Decision", text: "Can route to Hosted IronClaw.")
        store.addSelectedProjectNote(title: "Private row", text: "Keep this local.", isLocalOnly: true)

        let preview = try XCTUnwrap(store.projectContextRoutePreview)

        XCTAssertTrue(preview.title.contains("Next answer can use"))
        XCTAssertTrue(preview.title.contains("1 note"))
        XCTAssertFalse(preview.title.contains("2 notes"))
        XCTAssertEqual(preview.detail, "Local-only notes stay on phone for Hosted IronClaw.")
        XCTAssertTrue(preview.usesAttentionStyle)
    }

    func testIronclawApprovalPreviewRedactsSecretsAndDisablesDangerousAlways() {
        let gate = IronclawPendingGate(
            requestID: "gate-1",
            threadID: "thread-1",
            gateName: "approval",
            toolName: "shell",
            description: "Run command",
            parameters: #"{"command":"curl -H 'Authorization: Bearer abcdefghijklmnopqrstuvwxyz' https://example.com?token=secretvalue","api_key":"sk-1234567890abcdef"}"#,
            allowsAlways: true
        )

        XCTAssertEqual(gate.locallyAllowsAlways, false)
        XCTAssertTrue(gate.parameterPreview?.contains("[redacted]") == true)
        XCTAssertFalse(gate.parameterPreview?.contains("abcdefghijklmnopqrstuvwxyz") == true)
        XCTAssertFalse(gate.parameterPreview?.contains("sk-1234567890abcdef") == true)
    }

    func testProjectNoteDecodesLegacyNotesAsShareable() throws {
        let data = Data("""
        {
          "id": "note-1",
          "title": "Legacy",
          "text": "Existing note",
          "createdAt": 0
        }
        """.utf8)

        let note = try JSONDecoder().decode(ProjectNote.self, from: data)

        XCTAssertFalse(note.isLocalOnly)
    }

    func testProjectActionPromptFactoryStagesGenericTrackerPreview() {
        let prompt = ProjectActionPromptFactory.prompt(for: .makeTracker, projectName: "Supplements")

        XCTAssertTrue(prompt.contains("Supplements"))
        XCTAssertTrue(prompt.contains("scheduled briefings"))
        XCTAssertTrue(prompt.contains("calendar invites"))
        XCTAssertTrue(prompt.contains("Do not create anything until I confirm"))
        XCTAssertTrue(prompt.contains("near-widget action_plan"))
        XCTAssertTrue(prompt.contains("missing_fields"))
    }

    @MainActor
    func testConsumePendingSharedItemStagesDraftOnce() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-share-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // The extension's write helper persists the shared text/URL.
        XCTAssertTrue(
            PendingShareStore.write(PendingSharedItem(text: "https://near.org"), to: fileURL)
        )

        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        let consumed = await store.consumePendingSharedItem(fileURL: fileURL)
        XCTAssertTrue(consumed)
        XCTAssertEqual(store.draft, "https://near.org")

        // Consumed: the file is gone and a second call is a no-op.
        XCTAssertNil(PendingShareStore.read(from: fileURL))
        let secondConsume = await store.consumePendingSharedItem(fileURL: fileURL)
        XCTAssertFalse(secondConsume)
    }

    @MainActor
    func testConsumePendingSharedItemIgnoresEmptyText() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-share-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        PendingShareStore.write(PendingSharedItem(text: "   \n  "), to: fileURL)
        XCTAssertNil(PendingShareStore.read(from: fileURL))

        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        let consumed = await store.consumePendingSharedItem(fileURL: fileURL)
        XCTAssertFalse(consumed)
        XCTAssertEqual(store.draft, "")
    }
}

@MainActor
private func makeShareStore(
    shareAPI: ShareAPIFake,
    conversationAPI: ConversationAPIFake = ConversationAPIFake(),
    banners: BannerCapture
) -> ShareStore {
    let store = ShareStore(service: SharingService(shareAPI: shareAPI, conversationAPI: conversationAPI))
    store.bannerHandler = { message in
        banners.messages.append(message)
    }
    return store
}

@MainActor
private func makeShareStore(
    shareAPI: ShareAPIFake,
    conversationAPI: ConversationAPIFake = ConversationAPIFake()
) -> ShareStore {
    makeShareStore(shareAPI: shareAPI, conversationAPI: conversationAPI, banners: BannerCapture())
}

@MainActor
private final class BannerCapture {
    var messages: [String] = []
}

private func conversationSummary(id: String) -> ConversationSummary {
    ConversationSummary(
        id: id,
        createdAt: 1_700_000_000,
        metadata: ConversationMetadata(title: id, pinnedAt: nil, archivedAt: nil, importedAt: nil, rootResponseID: nil)
    )
}

private func shareInfo(
    conversationID: String,
    canWrite: Bool = false,
    shares: [ConversationShareInfo]
) -> ConversationSharesListResponse {
    ConversationSharesListResponse(
        isOwner: true,
        canShare: true,
        canWrite: canWrite,
        shares: shares,
        owner: nil
    )
}

private func publicShare(conversationID: String) -> ConversationShareInfo {
    ConversationShareInfo(
        id: "public-\(conversationID)",
        conversationID: conversationID,
        permission: "read",
        shareType: "public",
        recipient: nil,
        groupID: nil,
        orgEmailPattern: nil,
        publicToken: "token-\(conversationID)",
        createdAt: nil,
        updatedAt: nil
    )
}

private func shareGroup(id: String, name: String) -> ShareGroupInfo {
    ShareGroupInfo(
        id: id,
        name: name,
        members: [ShareInviteRecipient(kind: "email", value: "\(id)@example.com")],
        createdAt: nil,
        updatedAt: nil
    )
}

private final class ShareAPIFake: ShareAPI {
    struct DirectShareCall {
        let conversationID: String
        let recipients: [ShareInviteRecipient]
        let permission: String
    }

    struct OrganizationShareCall {
        let conversationID: String
        let emailPattern: String
        let permission: String
    }

    var conversationShares: [String: ConversationSharesListResponse] = [:]
    var sharedWithMeResult: [SharedConversationInfo] = []
    var shareGroupsResult: [ShareGroupInfo] = []
    var createGroupResult: ShareGroupInfo?
    var updateGroupResult: ShareGroupInfo?
    var createPublicShareConversationIDs: [String] = []
    var createdDirectShares: [DirectShareCall] = []
    var createdOrganizationShares: [OrganizationShareCall] = []
    var createdGroupNames: [String] = []
    var deletedGroupIDs: [String] = []
    var deletedConversationShares: [(conversationID: String, shareID: String)] = []

    func fetchConversationShares(_ conversationID: String) async throws -> ConversationSharesListResponse {
        conversationShares[conversationID] ?? shareInfo(conversationID: conversationID, shares: [])
    }

    func fetchSharedWithMe() async throws -> [SharedConversationInfo] {
        sharedWithMeResult
    }

    func createPublicShare(_ conversationID: String) async throws -> [ConversationShareInfo] {
        createPublicShareConversationIDs.append(conversationID)
        let share = publicShare(conversationID: conversationID)
        conversationShares[conversationID] = shareInfo(conversationID: conversationID, shares: [share])
        return [share]
    }

    func createDirectShare(_ conversationID: String, recipients: [ShareInviteRecipient], permission: String) async throws -> [ConversationShareInfo] {
        createdDirectShares.append(DirectShareCall(conversationID: conversationID, recipients: recipients, permission: permission))
        return []
    }

    func createOrganizationShare(_ conversationID: String, emailPattern: String, permission: String) async throws -> [ConversationShareInfo] {
        createdOrganizationShares.append(OrganizationShareCall(conversationID: conversationID, emailPattern: emailPattern, permission: permission))
        return []
    }

    func createGroupShare(_ conversationID: String, groupID: String, permission: String) async throws -> [ConversationShareInfo] {
        []
    }

    func fetchShareGroups() async throws -> [ShareGroupInfo] {
        shareGroupsResult
    }

    func createShareGroup(name: String, members: [ShareInviteRecipient]) async throws -> ShareGroupInfo {
        createdGroupNames.append(name)
        return createGroupResult ?? ShareGroupInfo(id: UUID().uuidString, name: name, members: members, createdAt: nil, updatedAt: nil)
    }

    func updateShareGroup(_ groupID: String, name: String, members: [ShareInviteRecipient]) async throws -> ShareGroupInfo {
        updateGroupResult ?? ShareGroupInfo(id: groupID, name: name, members: members, createdAt: nil, updatedAt: nil)
    }

    func deleteShareGroup(_ groupID: String) async throws {
        deletedGroupIDs.append(groupID)
    }

    func deleteConversationShare(_ conversationID: String, shareID: String) async throws {
        deletedConversationShares.append((conversationID, shareID))
        if var info = conversationShares[conversationID] {
            let remainingShares = info.shares.filter { $0.id != shareID }
            info = ConversationSharesListResponse(
                isOwner: info.isOwner,
                canShare: info.canShare,
                canWrite: info.canWrite,
                shares: remainingShares,
                owner: info.owner
            )
            conversationShares[conversationID] = info
        }
    }
}

private final class ConversationAPIFake: ConversationAPI {
    var readableConversation = conversationSummary(id: "conv-readable")
    var readableItems = ConversationItemsResponse(data: [], firstID: nil, hasMore: false, lastID: nil)

    func fetchConversations() async throws -> [ConversationSummary] { [] }
    func createConversation(title: String) async throws -> ConversationSummary { conversationSummary(id: "created") }
    func createConversation(title: String, metadata: [String: String]) async throws -> ConversationSummary { conversationSummary(id: "created") }
    func addItemsToConversation(_ conversationID: String, items: [ConversationImportItem]) async throws {}
    func updateConversationTitle(_ conversationID: String, title: String) async throws {}
    func fetchConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse { readableItems }
    func fetchReadableConversation(_ conversationID: String) async throws -> ConversationSummary { readableConversation }
    func fetchReadableConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse { readableItems }
    func deleteConversation(_ conversationID: String) async throws {}
    func cloneConversation(_ conversationID: String) async throws -> ConversationSummary { readableConversation }
    func archiveConversation(_ conversationID: String) async throws {}
    func unarchiveConversation(_ conversationID: String) async throws {}
    func pinConversation(_ conversationID: String) async throws {}
    func unpinConversation(_ conversationID: String) async throws {}
}
