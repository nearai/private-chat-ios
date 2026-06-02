import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testAppDeepLinkCanImportHostedIronclawBridge() throws {
        var components = URLComponents(string: "nearprivatechat://connect")!
        components.queryItems = [
            URLQueryItem(name: "endpoint", value: "https://example.com/ironclaw"),
            URLQueryItem(name: "token", value: "secret-token"),
            URLQueryItem(name: "thread_id", value: "thread-123"),
            URLQueryItem(name: "prompt", value: "Review the latest repo status")
        ]

        let action = try XCTUnwrap(AppDeepLinkAction.parse(components.url!))

        XCTAssertEqual(action.route, .agent)
        XCTAssertEqual(action.draft, "Review the latest repo status")
        XCTAssertEqual(action.hostedBridgeImport?.endpoint, "https://example.com/ironclaw")
        XCTAssertEqual(action.hostedBridgeImport?.authToken, "secret-token")
        XCTAssertEqual(action.hostedBridgeImport?.threadID, "thread-123")
        XCTAssertTrue(action.hostedBridgeImport?.isEnabled == true)
    }


    @MainActor
    func testPendingExternalDeepLinkDescriptionMentionsHostedBridgeImport() throws {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        let url = try XCTUnwrap(
            URL(
                string: "nearprivatechat://ironclaw?endpoint=https%3A%2F%2Fexample.com%2Fironclaw&token=secret-token&prompt=Review%20this"
            )
        )

        XCTAssertTrue(store.handleIncomingURL(url))
        XCTAssertEqual(
            store.pendingExternalDeepLinkDescription,
            "Open an IronClaw Mobile agent. Agent connection for example.com will be saved and enabled. Token will be saved. A prompt will be staged but not sent."
        )
    }

    func testChatImportNormalizesDeveloperAndToolRoles() throws {
        let payload = Data("""
        {
          "conversation": {
            "title": "Imported",
            "created_at": 123
          },
          "messages": [
            {
              "role": "developer",
              "text": "System guidance",
              "model": "nearai/gpt-oss-120b"
            },
            {
              "role": "tool",
              "text": "Tool output",
              "model": "deepseek-v3.1"
            }
          ]
        }
        """.utf8)

        let conversations = try ChatImportBuilder.conversations(from: payload)

        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations[0].items.map(\.role), ["system", "assistant"])
    }

    func testChatImportRejectsOversizedPayloads() {
        let oversized = Data(repeating: 0x20, count: ChatImportLimits.maxImportBytes + 1)
        XCTAssertThrowsError(try ChatImportBuilder.conversations(from: oversized))

        let hugeMessage = String(repeating: "a", count: ChatImportLimits.maxTextBytesPerItem + 1)
        let payload = Data("""
        {
          "conversation": {"title": "Huge", "created_at": 123},
          "messages": [
            {"role": "user", "text": "\(hugeMessage)", "model": "test"}
          ]
        }
        """.utf8)
        XCTAssertThrowsError(try ChatImportBuilder.conversations(from: payload))
    }

    func testConversationTranscriptClipboardRejectsEmptyTranscript() {
        XCTAssertEqual(
            ConversationTranscriptClipboard.copyTranscript(conversation: nil, messages: []),
            .emptyTranscript
        )
    }

    func testChatImportServiceCreatesConversationsAndBatchesItems() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("near-private-chat-import-\(UUID().uuidString)")
            .appendingPathExtension("json")
        try Data("""
        {
          "conversation": {
            "title": "Imported services agreement draft",
            "created_at": 123
          },
          "messages": [
            {"role": "user", "text": "Draft the agreement.", "model": "nearai/gpt-oss-120b"},
            {"role": "assistant", "text": "Here is the draft.", "model": "deepseek-v3.1"}
          ]
        }
        """.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let api = ChatImportConversationAPIFake()
        let service = ChatImportService(conversationAPI: api)

        let summary = try await service.importChats(
            from: url,
            importedAt: Date(timeIntervalSince1970: 1_700)
        )

        XCTAssertEqual(summary.importedCount, 1)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(summary.bannerMessage, "Imported 1 chat.")
        XCTAssertEqual(api.createdConversations.map(\.title), ["Imported services agreement draft"])
        XCTAssertEqual(api.createdConversations.first?.metadata["imported_at"], "1700000")
        XCTAssertEqual(api.createdConversations.first?.metadata["initial_created_at"], "123")
        XCTAssertEqual(api.addedItems.count, 1)
        XCTAssertEqual(api.addedItems.first?.conversationID, "import-1")
        XCTAssertEqual(api.addedItems.first?.items.map(\.role), ["user", "assistant"])
    }

    func testProjectArchiveStateRoundTripsAndDefaultsToActive() throws {
        let archivedPayload = Data("""
        {
          "id": "project-1",
          "name": "Archived",
          "createdAt": 123,
          "archivedAt": 456,
          "conversationIDs": [],
          "attachments": [],
          "instructions": "",
          "memorySummary": "",
          "links": [],
          "notes": []
        }
        """.utf8)

        let archivedProject = try JSONDecoder().decode(ChatProject.self, from: archivedPayload)
        XCTAssertTrue(archivedProject.isArchived)
        XCTAssertNotNil(archivedProject.archivedAt)

        let activePayload = Data("""
        {
          "id": "project-2",
          "name": "Active",
          "createdAt": 123,
          "conversationIDs": [],
          "attachments": [],
          "instructions": "",
          "memorySummary": "",
          "links": [],
          "notes": []
        }
        """.utf8)

        let activeProject = try JSONDecoder().decode(ChatProject.self, from: activePayload)
        XCTAssertFalse(activeProject.isArchived)
    }

    @MainActor
    func testProjectStoreScopesVisibleAndArchivedConversations() {
        let selected = ChatProject(
            id: "project-1",
            name: "Q3 Launch",
            createdAt: Date(timeIntervalSince1970: 1_000),
            conversationIDs: ["pinned", "normal"],
            iconName: ProjectIcon.folder.symbolName,
            paletteName: ProjectPalette.sky.rawValue
        )
        let pinned = ConversationSummary(
            id: "pinned",
            createdAt: 1_000,
            metadata: ConversationMetadata(title: "Pinned", pinnedAt: "now")
        )
        let normal = ConversationSummary(
            id: "normal",
            createdAt: 2_000,
            metadata: ConversationMetadata(title: "Normal")
        )
        let archived = ConversationSummary(
            id: "archived",
            createdAt: 3_000,
            metadata: ConversationMetadata(title: "Archived", archivedAt: "then")
        )

        let store = ProjectStore(
            projects: [selected],
            selectedProjectID: selected.id,
            conversations: [archived, normal, pinned]
        )

        XCTAssertEqual(store.selectedProject?.name, "Q3 Launch")
        XCTAssertEqual(store.visibleConversations.map(\.id), ["pinned", "normal"])
        XCTAssertEqual(store.archivedConversations.map(\.id), ["archived"])
    }

    @MainActor
    func testProjectStoreSeparatesVisibleAndArchivedProjects() {
        let active = ChatProject(
            id: "project-1",
            name: "Active",
            createdAt: Date(timeIntervalSince1970: 1_000),
            conversationIDs: []
        )
        let archived = ChatProject(
            id: "project-2",
            name: "Archived",
            createdAt: Date(timeIntervalSince1970: 2_000),
            archivedAt: Date(timeIntervalSince1970: 3_000),
            conversationIDs: []
        )

        let store = ProjectStore(
            projects: [archived, active],
            selectedProjectID: archived.id,
            conversations: []
        )

        XCTAssertNil(store.selectedProject)
        XCTAssertEqual(store.visibleProjects.map(\.id), ["project-1"])
        XCTAssertEqual(store.archivedProjects.map(\.id), ["project-2"])
    }


    @MainActor
    func testActiveSystemPromptIncludesFormatContractWithoutSoulMarkdown() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.systemPrompt = "Prefer short answers."

        let prompt = store.activeSystemPromptForTesting(model: ModelOption.nearPrivateDefaultModelID)

        XCTAssertTrue(prompt.contains("Format contract:"))
        XCTAssertTrue(prompt.contains("GitHub-flavored tables"))
        XCTAssertTrue(prompt.contains("fenced code blocks with language tags"))
        XCTAssertTrue(prompt.contains("Prefer short answers."))
        XCTAssertFalse(prompt.contains("About the user / Response preferences"))
    }


    @MainActor
    func testApplyingSetupSeedsLocalSoulMarkdownForSimpleChats() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))

        var profile = UserSetupProfile.defaults
        profile.goalText = "Map the strongest privacy proof workflow."
        profile.contextStyle = .simple

        store.applySetupProfile(profile)

        XCTAssertNil(store.selectedProjectID)
        XCTAssertTrue(store.soulMarkdown.contains("# soul.md"))
        XCTAssertTrue(store.soulMarkdown.contains("## Intent"))
        XCTAssertTrue(store.soulMarkdown.contains("Ask privately"))
        XCTAssertTrue(store.soulMarkdown.contains("## Voice & Format"))

        let privatePrompt = store.activeSystemPromptForTesting(model: ModelOption.nearPrivateDefaultModelID)
        XCTAssertTrue(privatePrompt.contains("Map the strongest privacy proof workflow."))

        let cloudPrompt = store.activeSystemPromptForTesting(model: ModelOption.nearCloudModelID(for: "provider/current-model"))
        XCTAssertFalse(cloudPrompt.contains("Map the strongest privacy proof workflow."))
        XCTAssertTrue(cloudPrompt.contains("Ask privately"))
    }


    @MainActor
    func testApplyingSetupDoesNotOverwriteExistingSoulMarkdown() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        let existing = """
        # soul.md

        ## Voice & Format
        Keep the existing voice profile.
        """
        store.soulMarkdown = existing

        var profile = UserSetupProfile.defaults
        profile.goalText = "Replace this if setup overwrites user text."

        store.applySetupProfile(profile)

        XCTAssertEqual(store.soulMarkdown, existing)
    }

    func testMarkdownMathParserSplitsInlineMathDelimiters() {
        let segments = MarkdownMathParser.inlineSegments(
            in: "Energy $E=mc^2$ and \\(x_i\\) stay inline."
        )

        XCTAssertEqual(
            segments,
            [
                .text("Energy "),
                .math("E=mc^2"),
                .text(" and "),
                .math("x_i"),
                .text(" stay inline.")
            ]
        )
    }

    func testMarkdownMathParserDoesNotTreatCurrencyAsInlineMath() {
        let segments = MarkdownMathParser.inlineSegments(
            in: "The fee is $12 and the variable is $x$."
        )

        XCTAssertEqual(
            segments,
            [
                .text("The fee is $12 and the variable is "),
                .math("x"),
                .text(".")
            ]
        )
    }

    func testMarkdownMathParserParsesBlockMathDelimiters() throws {
        let dollarBlock = [
            "Before",
            "$$",
            "\\int_0^1 x^2 dx",
            "$$",
            "After"
        ]
        let bracketBlock = ["\\[ a^2 + b^2 = c^2 \\]"]

        XCTAssertEqual(
            MarkdownMathParser.blockMath(at: 1, in: dollarBlock),
            MarkdownMathBlockParseResult(formula: "\\int_0^1 x^2 dx", consumedLineCount: 3)
        )
        XCTAssertEqual(
            MarkdownMathParser.blockMath(at: 0, in: bracketBlock),
            MarkdownMathBlockParseResult(formula: "a^2 + b^2 = c^2", consumedLineCount: 1)
        )
    }
}

private final class ChatImportConversationAPIFake: ConversationAPI {
    struct CreatedConversation {
        let title: String
        let metadata: [String: String]
    }

    struct AddedItems {
        let conversationID: String
        let items: [ConversationImportItem]
    }

    private(set) var createdConversations: [CreatedConversation] = []
    private(set) var addedItems: [AddedItems] = []

    func fetchConversations() async throws -> [ConversationSummary] {
        []
    }

    func createConversation(title: String) async throws -> ConversationSummary {
        try await createConversation(title: title, metadata: [:])
    }

    func createConversation(title: String, metadata: [String: String]) async throws -> ConversationSummary {
        createdConversations.append(CreatedConversation(title: title, metadata: metadata))
        return ConversationSummary(id: "import-\(createdConversations.count)", createdAt: nil, metadata: ConversationMetadata(title: title))
    }

    func addItemsToConversation(_ conversationID: String, items: [ConversationImportItem]) async throws {
        addedItems.append(AddedItems(conversationID: conversationID, items: items))
    }

    func updateConversationTitle(_ conversationID: String, title: String) async throws {}

    func fetchConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse {
        ConversationItemsResponse(data: [], firstID: nil, hasMore: false, lastID: nil)
    }

    func fetchReadableConversation(_ conversationID: String) async throws -> ConversationSummary {
        ConversationSummary(id: conversationID, createdAt: nil, metadata: ConversationMetadata(title: "Readable"))
    }

    func fetchReadableConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse {
        ConversationItemsResponse(data: [], firstID: nil, hasMore: false, lastID: nil)
    }

    func deleteConversation(_ conversationID: String) async throws {}
    func cloneConversation(_ conversationID: String) async throws -> ConversationSummary {
        ConversationSummary(id: "\(conversationID)-copy", createdAt: nil, metadata: ConversationMetadata(title: "Copy"))
    }
    func archiveConversation(_ conversationID: String) async throws {}
    func unarchiveConversation(_ conversationID: String) async throws {}
    func pinConversation(_ conversationID: String) async throws {}
    func unpinConversation(_ conversationID: String) async throws {}
}
