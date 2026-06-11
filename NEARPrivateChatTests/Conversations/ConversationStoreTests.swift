import XCTest
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    @MainActor
    func testConversationStoreSuiteRefreshSelectMutateAndDeleteWithoutForceUnwraps() async throws {
        let first = ConversationSummary(
            id: "conv-first",
            createdAt: 1_700_000_000,
            metadata: ConversationMetadata(title: "First")
        )
        let second = ConversationSummary(
            id: "conv-second",
            createdAt: 1_700_000_100,
            metadata: ConversationMetadata(title: "Second")
        )
        let api = ConversationStoreSuiteAPI()
        api.fetchResult = .success([first, second])
        let store = ConversationStore(repository: ConversationRepository(api: api))
        var observedIDs: [[String]] = []
        store.conversationsDidChange = { observedIDs.append($0.map(\.id)) }

        await store.refreshConversations()
        XCTAssertEqual(store.conversations.map(\.id), ["conv-first", "conv-second"])
        XCTAssertEqual(store.openConversation(byID: "conv-second")?.title, "Second")

        guard let selected = store.openConversation(byID: "conv-first") else {
            return XCTFail("Expected refreshed conversation to be selectable.")
        }
        store.selectConversation(selected)
        try await store.renameConversation(selected, title: "Renamed")
        XCTAssertEqual(store.selectedConversation?.title, "Renamed")
        XCTAssertEqual(api.updatedTitles.map(\.title), ["Renamed"])

        let shouldPin = try await store.togglePinConversation(selected)
        XCTAssertTrue(shouldPin)
        XCTAssertTrue(store.selectedConversation?.isPinned == true)
        XCTAssertEqual(api.pinnedConversationIDs, ["conv-first"])

        try await store.archiveConversation(selected)
        XCTAssertTrue(store.selectedConversation?.isArchived == true)
        XCTAssertEqual(store.archivedConversations.map(\.id), ["conv-first"])
        XCTAssertEqual(api.archivedConversationIDs, ["conv-first"])

        try await store.deleteConversation(selected)
        XCTAssertNil(store.selectedConversation)
        XCTAssertEqual(store.conversations.map(\.id), ["conv-second"])
        XCTAssertEqual(api.deletedConversationIDs, ["conv-first"])
        XCTAssertEqual(observedIDs.last, ["conv-second"])
    }
}

private final class ConversationStoreSuiteAPI: ConversationAPI {
    enum ErrorStub: Error {
        case failure
    }

    var fetchResult: Result<[ConversationSummary], Error> = .success([])
    var createdConversation = ConversationSummary(
        id: "conv-created",
        createdAt: 1_700_000_200,
        metadata: ConversationMetadata(title: "Created")
    )
    var clonedConversation = ConversationSummary(
        id: "conv-cloned",
        createdAt: 1_700_000_300,
        metadata: ConversationMetadata(title: "Cloned")
    )
    var updatedTitles: [(conversationID: String, title: String)] = []
    var deletedConversationIDs: [String] = []
    var archivedConversationIDs: [String] = []
    var unarchivedConversationIDs: [String] = []
    var pinnedConversationIDs: [String] = []
    var unpinnedConversationIDs: [String] = []

    func fetchConversations() async throws -> [ConversationSummary] {
        try fetchResult.get()
    }

    func createConversation(title: String) async throws -> ConversationSummary {
        createdConversation
    }

    func createConversation(title: String, metadata: [String: String]) async throws -> ConversationSummary {
        createdConversation
    }

    func addItemsToConversation(_ conversationID: String, items: [ConversationImportItem]) async throws {}

    func updateConversationTitle(_ conversationID: String, title: String) async throws {
        updatedTitles.append((conversationID, title))
    }

    func fetchConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse {
        ConversationItemsResponse(data: [], firstID: nil, hasMore: false, lastID: nil)
    }

    func fetchReadableConversation(_ conversationID: String) async throws -> ConversationSummary {
        ConversationSummary(
            id: conversationID,
            createdAt: 1_700_000_000,
            metadata: ConversationMetadata(title: "Readable")
        )
    }

    func fetchReadableConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse {
        ConversationItemsResponse(data: [], firstID: nil, hasMore: false, lastID: nil)
    }

    func deleteConversation(_ conversationID: String) async throws {
        deletedConversationIDs.append(conversationID)
    }

    func cloneConversation(_ conversationID: String) async throws -> ConversationSummary {
        clonedConversation
    }

    func archiveConversation(_ conversationID: String) async throws {
        archivedConversationIDs.append(conversationID)
    }

    func unarchiveConversation(_ conversationID: String) async throws {
        unarchivedConversationIDs.append(conversationID)
    }

    func pinConversation(_ conversationID: String) async throws {
        pinnedConversationIDs.append(conversationID)
    }

    func unpinConversation(_ conversationID: String) async throws {
        unpinnedConversationIDs.append(conversationID)
    }
}
