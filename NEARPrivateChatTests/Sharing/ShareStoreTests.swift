import XCTest
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    @MainActor
    func testShareStoreSuiteGrantValidateRevokeAndReload() async throws {
        let conversation = ConversationSummary(
            id: "conv-share-suite",
            createdAt: 1_700_000_000,
            metadata: ConversationMetadata(title: "Share suite")
        )
        let shareAPI = ShareStoreSuiteAPI()
        let store = ShareStore(
            service: SharingService(
                shareAPI: shareAPI,
                conversationAPI: ShareStoreSuiteConversationAPI()
            )
        )
        var banners: [String] = []
        store.bannerHandler = { banners.append($0) }

        await store.grantDirectShare(
            rawRecipients: "ava@example.com, ava@example.com, near.near",
            permission: "write",
            conversation: conversation
        )
        XCTAssertEqual(shareAPI.createdDirectShares.count, 1)
        XCTAssertEqual(shareAPI.createdDirectShares[0].conversationID, conversation.id)
        XCTAssertEqual(shareAPI.createdDirectShares[0].recipients.map(\.value), ["ava@example.com", "near.near"])
        XCTAssertEqual(shareAPI.createdDirectShares[0].permission, "write")
        XCTAssertEqual(banners.last, "Access granted to 2 people.")

        let publicURL = await store.enablePublicShare(for: conversation)
        XCTAssertEqual(publicURL?.absoluteString, "https://private.near.ai/c/conv-share-suite")
        let publicShare = try XCTUnwrap(store.shareInfo?.shares.first)
        XCTAssertEqual(publicShare.shareType, "public")
        XCTAssertEqual(banners.last, "Public link enabled.")

        let reloadedStore = ShareStore(
            service: SharingService(
                shareAPI: shareAPI,
                conversationAPI: ShareStoreSuiteConversationAPI()
            )
        )
        await reloadedStore.loadShares(for: conversation)
        XCTAssertEqual(reloadedStore.shareInfo?.shares.map(\.id), [publicShare.id])
        XCTAssertEqual(reloadedStore.shareInfo?.shares.first?.publicToken, conversation.id)

        await store.removeConversationShare(publicShare, conversation: conversation)
        XCTAssertEqual(shareAPI.deletedConversationShares.map(\.shareID), [publicShare.id])
        XCTAssertTrue(store.shareInfo?.shares.isEmpty == true)
        XCTAssertEqual(banners.last, "Access removed.")

        store.clearConversationShareInfo()
        XCTAssertNil(store.shareInfo)
        await store.loadShares(for: conversation)
        XCTAssertTrue(store.shareInfo?.shares.isEmpty == true)
    }

    func testShareStoreSuiteRejectsUnsafeConversationLinks() {
        XCTAssertEqual(ShareStore.conversationID(from: "https://private.near.ai/c/conv-safe_123"), "conv-safe_123")
        XCTAssertNil(ShareStore.conversationID(from: "https://evil.example/c/conv-safe_123"))
        XCTAssertNil(ShareStore.conversationID(from: "https://private.near.ai/c/..%2Fusers%2Fme"))
        XCTAssertNil(ShareStore.conversationID(from: "private.near.ai"))
    }

    @MainActor
    func testShareStoreSuiteLoadsSharedPreviewAndFetchesWriteAccess() async throws {
        let shareAPI = ShareStoreSuiteAPI()
        let conversationAPI = ShareStoreSuiteConversationAPI()
        conversationAPI.readableConversation = ConversationSummary(
            id: "conv-preview-suite",
            createdAt: 1_700_000_000,
            metadata: ConversationMetadata(title: "Preview suite")
        )
        conversationAPI.readableItems = try ShareStoreSuiteConversationAPI.itemsResponseJSON("""
        {
          "data": [
            {
              "type": "message",
              "id": "item-user",
              "response_id": "resp-user",
              "role": "user",
              "content": "Summarize this shared draft.",
              "created_at": 1700000000
            },
            {
              "type": "message",
              "id": "item-assistant",
              "response_id": "resp-assistant",
              "role": "assistant",
              "content": "Shared preview sentinel.",
              "created_at": 1700000001
            }
          ],
          "first_id": null,
          "has_more": false,
          "last_id": null
        }
        """)
        shareAPI.conversationShares["conv-preview-suite"] = ConversationSharesListResponse(
            isOwner: false,
            canShare: false,
            canWrite: true,
            shares: [],
            owner: nil
        )
        let store = ShareStore(
            service: SharingService(
                shareAPI: shareAPI,
                conversationAPI: conversationAPI
            )
        )

        await store.openSharedConversation(from: "https://private.near.ai/c/conv-preview-suite")

        XCTAssertEqual(store.sharedPreview?.conversation.id, "conv-preview-suite")
        XCTAssertEqual(store.sharedPreview?.source, "https://private.near.ai/c/conv-preview-suite")
        XCTAssertTrue(store.sharedPreview?.canWrite == true)
        XCTAssertEqual(store.sharedPreview?.messages.map(\.text), ["Summarize this shared draft.", "Shared preview sentinel."])
        XCTAssertEqual(conversationAPI.fetchedReadableConversationIDs, ["conv-preview-suite"])
        XCTAssertEqual(conversationAPI.fetchedReadableItemIDs, ["conv-preview-suite"])
    }
}

private final class ShareStoreSuiteAPI: ShareAPI {
    struct DirectShareCall {
        let conversationID: String
        let recipients: [ShareInviteRecipient]
        let permission: String
    }

    var conversationShares: [String: ConversationSharesListResponse] = [:]
    var createdDirectShares: [DirectShareCall] = []
    var deletedConversationShares: [(conversationID: String, shareID: String)] = []

    func fetchConversationShares(_ conversationID: String) async throws -> ConversationSharesListResponse {
        conversationShares[conversationID] ?? ConversationSharesListResponse(
            isOwner: true,
            canShare: true,
            canWrite: true,
            shares: [],
            owner: nil
        )
    }

    func fetchSharedWithMe() async throws -> [SharedConversationInfo] {
        []
    }

    func createPublicShare(_ conversationID: String) async throws -> [ConversationShareInfo] {
        let share = ConversationShareInfo(
            id: "share-public",
            conversationID: conversationID,
            permission: "read",
            shareType: "public",
            recipient: nil,
            groupID: nil,
            orgEmailPattern: nil,
            publicToken: conversationID,
            createdAt: nil,
            updatedAt: nil
        )
        conversationShares[conversationID] = ConversationSharesListResponse(
            isOwner: true,
            canShare: true,
            canWrite: true,
            shares: [share],
            owner: nil
        )
        return [share]
    }

    func createDirectShare(
        _ conversationID: String,
        recipients: [ShareInviteRecipient],
        permission: String
    ) async throws -> [ConversationShareInfo] {
        createdDirectShares.append(
            DirectShareCall(conversationID: conversationID, recipients: recipients, permission: permission)
        )
        return []
    }

    func createOrganizationShare(
        _ conversationID: String,
        emailPattern: String,
        permission: String
    ) async throws -> [ConversationShareInfo] {
        []
    }

    func createGroupShare(_ conversationID: String, groupID: String, permission: String) async throws -> [ConversationShareInfo] {
        []
    }

    func fetchShareGroups() async throws -> [ShareGroupInfo] {
        []
    }

    func createShareGroup(name: String, members: [ShareInviteRecipient]) async throws -> ShareGroupInfo {
        ShareGroupInfo(id: "group-created", name: name, members: members, createdAt: nil, updatedAt: nil)
    }

    func updateShareGroup(_ groupID: String, name: String, members: [ShareInviteRecipient]) async throws -> ShareGroupInfo {
        ShareGroupInfo(id: groupID, name: name, members: members, createdAt: nil, updatedAt: nil)
    }

    func deleteShareGroup(_ groupID: String) async throws {}

    func deleteConversationShare(_ conversationID: String, shareID: String) async throws {
        deletedConversationShares.append((conversationID, shareID))
        if let info = conversationShares[conversationID] {
            conversationShares[conversationID] = ConversationSharesListResponse(
                isOwner: info.isOwner,
                canShare: info.canShare,
                canWrite: info.canWrite,
                shares: info.shares.filter { $0.id != shareID },
                owner: info.owner
            )
        }
    }
}

private final class ShareStoreSuiteConversationAPI: ConversationAPI {
    var readableConversation = ConversationSummary(id: "readable", createdAt: nil, metadata: ConversationMetadata(title: "Readable"))
    var readableItems = ConversationItemsResponse(data: [], firstID: nil, hasMore: false, lastID: nil)
    var fetchedReadableConversationIDs: [String] = []
    var fetchedReadableItemIDs: [String] = []

    func fetchConversations() async throws -> [ConversationSummary] { [] }
    func createConversation(title: String) async throws -> ConversationSummary {
        ConversationSummary(id: "created", createdAt: nil, metadata: ConversationMetadata(title: title))
    }
    func createConversation(title: String, metadata: [String: String]) async throws -> ConversationSummary {
        ConversationSummary(id: "created", createdAt: nil, metadata: ConversationMetadata(title: title))
    }
    func addItemsToConversation(_ conversationID: String, items: [ConversationImportItem]) async throws {}
    func updateConversationTitle(_ conversationID: String, title: String) async throws {}
    func fetchConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse { ConversationItemsResponse(data: [], firstID: nil, hasMore: false, lastID: nil) }
    func fetchReadableConversation(_ conversationID: String) async throws -> ConversationSummary {
        fetchedReadableConversationIDs.append(conversationID)
        return readableConversation
    }
    func fetchReadableConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse {
        fetchedReadableItemIDs.append(conversationID)
        return readableItems
    }
    func deleteConversation(_ conversationID: String) async throws {}
    func cloneConversation(_ conversationID: String) async throws -> ConversationSummary {
        ConversationSummary(id: conversationID, createdAt: nil, metadata: ConversationMetadata(title: "Clone"))
    }
    func archiveConversation(_ conversationID: String) async throws {}
    func unarchiveConversation(_ conversationID: String) async throws {}
    func pinConversation(_ conversationID: String) async throws {}
    func unpinConversation(_ conversationID: String) async throws {}

    static func itemsResponseJSON(_ json: String) throws -> ConversationItemsResponse {
        try JSONDecoder().decode(ConversationItemsResponse.self, from: Data(json.utf8))
    }
}
