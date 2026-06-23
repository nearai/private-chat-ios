import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testMessageStreamServiceOnlyTimesOutPrivateInferenceRoutes() {
        XCTAssertEqual(MessageStreamService.visibleOutputTimeout(for: "zai-org/GLM-5.1-FP8"), 90)
        XCTAssertNil(MessageStreamService.visibleOutputTimeout(for: ModelOption.nearCloudModelID(for: "openai/gpt-5.5")))
        XCTAssertNil(MessageStreamService.visibleOutputTimeout(for: ModelOption.ironclawModelID))
        XCTAssertEqual(CouncilStreamService.defaultConcurrentStreamLimit, 2)
    }

    func testWebSearchStreamPreservesSourceMetadata() throws {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)
        let event = api.parseStreamEvent(Data("""
        {
          "type": "response.output_item.done",
          "item": {
            "type": "web_search_call",
            "action": {
              "query": "test",
              "sources": [
                {
                  "url": "https://example.com/a",
                  "title": "Example source",
                  "published_at": "2026-05-31",
                  "source_type": "news_article",
                  "snippet": "A short cited passage."
                }
              ]
            }
          }
        }
        """.utf8))

        guard case let .webSearchCompleted(_, sources)? = event else {
            return XCTFail("Expected web search event")
        }
        let source = try XCTUnwrap(sources.first)
        XCTAssertEqual(source.displayTitle, "Example source")
        XCTAssertEqual(source.displaySubtitle, "example.com · 2026-05-31 · News Article")
        XCTAssertEqual(source.snippetPreview, "A short cited passage.")
    }

    func testStreamingPreviewHelperPreservesFullLongText() {
        let longText = String(repeating: "a", count: 6_000)

        XCTAssertEqual(StreamingPreviewHelper.preview(from: longText), longText)
    }

    func testSnippetPreviewTracksStoredSnippetLength() throws {
        let snippet = String(repeating: "s", count: 600)
        let source = WebSearchSource(
            type: "news_article",
            url: "https://example.com/full-snippet",
            title: "Full snippet",
            publishedAt: nil,
            snippet: snippet
        )

        let storedSnippet = try XCTUnwrap(source.snippet)
        XCTAssertEqual(storedSnippet.count, 600)
        XCTAssertEqual(source.snippetPreview, storedSnippet)
        XCTAssertEqual(source.snippetPreview?.count, 600)
    }

    func testComposerStateSendabilityTracksDraftAttachmentsAndStreaming() {
        let empty = ComposerState(
            draft: "  ",
            pendingAttachments: [],
            isStreaming: false,
            routeReadinessTitle: nil,
            routeReadinessMessage: nil
        )
        XCTAssertFalse(empty.hasSendableContent)
        XCTAssertTrue(empty.sendDisabled)

        let withDraft = ComposerState(
            draft: "hello",
            pendingAttachments: [],
            isStreaming: false,
            routeReadinessTitle: nil,
            routeReadinessMessage: nil
        )
        XCTAssertTrue(withDraft.hasSendableContent)
        XCTAssertFalse(withDraft.sendDisabled)

        let streamingEmpty = ComposerState(
            draft: "",
            pendingAttachments: [],
            isStreaming: true,
            routeReadinessTitle: nil,
            routeReadinessMessage: nil
        )
        XCTAssertFalse(streamingEmpty.hasSendableContent)
        XCTAssertFalse(streamingEmpty.sendDisabled)

        let withAttachment = ComposerState(
            draft: "",
            pendingAttachments: [
                ChatAttachment(id: "file-1", name: "launch-brief.pdf", kind: "file", bytes: 128)
            ],
            isStreaming: false,
            routeReadinessTitle: nil,
            routeReadinessMessage: nil
        )
        XCTAssertTrue(withAttachment.hasSendableContent)
        XCTAssertEqual(withAttachment.pendingAttachmentCount, 1)
    }

    func testResponseStreamParserHandlesCoreEvents() throws {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)

        XCTAssertEqual(
            api.parseStreamEvent(Data(#"{"type":"response.created","response":{"id":"resp_123"}}"#.utf8)),
            .created(responseID: "resp_123")
        )
        XCTAssertEqual(
            api.parseStreamEvent(Data(#"{"type":"response.output_text.delta","delta":"hello"}"#.utf8)),
            .textDelta("hello")
        )
        XCTAssertEqual(
            api.parseStreamEvent(Data(#"{"type":"response.completed","response":{"id":"resp_123"}}"#.utf8)),
            .completed(responseID: "resp_123")
        )
    }

    func testResponseStreamVisibilityAndEmbeddedFailureParsing() throws {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)

        XCTAssertFalse(ResponseStreamEvent.reasoningStarted.hasVisibleOutput)
        XCTAssertFalse(ResponseStreamEvent.textDelta("   ").hasVisibleOutput)
        XCTAssertTrue(ResponseStreamEvent.textDelta("visible answer").hasVisibleOutput)
        XCTAssertTrue(ResponseStreamEvent.itemDone(text: "done").hasVisibleOutput)

        XCTAssertEqual(
            api.parseStreamEvent(Data(#"{"type":"response.output_text.delta","delta":"{\"error\":{\"message\":\"model stalled\"}}"}"#.utf8)),
            .failed("model stalled")
        )
        XCTAssertEqual(
            api.parseStreamEvent(Data(#"{"type":"response.output_text.done","text":"{\"detail\":\"tool denied\"}"}"#.utf8)),
            .failed("tool denied")
        )
    }

    func testResponseStreamParserHandlesToolAndFailureEvents() throws {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)

        XCTAssertEqual(
            api.parseStreamEvent(Data(#"{"type":"response.output_item.added","item":{"type":"web_search_call","action":{"query":"latest AI news"}}}"#.utf8)),
            .webSearchStarted(query: "latest AI news")
        )

        guard case let .webSearchCompleted(query, sources)? = api.parseStreamEvent(Data("""
        {
          "type": "response.output_item.done",
          "item": {
            "type": "web_search_call",
            "action": {
              "query": "latest AI news",
              "sources": [
                {
                  "title": "AI Update",
                  "url": "https://example.com/ai",
                  "snippet": "New model release"
                }
              ]
            }
          }
        }
        """.utf8)) else {
            return XCTFail("Expected web search completion event")
        }
        XCTAssertEqual(query, "latest AI news")
        XCTAssertEqual(sources.first?.url, "https://example.com/ai")

        XCTAssertEqual(
            api.parseStreamEvent(Data(#"{"type":"response.failed","response":{"error":{"message":"Access denied"}}}"#.utf8)),
            .failed("Access denied")
        )

        XCTAssertEqual(
            api.parseStreamEvent(Data(#"{"type":"response.failed","response":{"error":{"message":"Access temporarily restricted. Please try again later.","status":429,"code":"private_route_rate_limited"}}}"#.utf8)),
            .failedWithStatus(message: "Access temporarily restricted. Please try again later.", statusCode: 429)
        )

        XCTAssertEqual(
            api.parseStreamEvent(Data(#"{"type":"response.failed","response":{"error":{"message":"The private route is temporarily busy.","code":"private_route_capacity"}}}"#.utf8)),
            .failedWithStatus(message: "The private route is temporarily busy.", statusCode: 503)
        )
    }

    func testChatStreamEventGateRejectsStaleConversationEvents() {
        XCTAssertTrue(ChatStreamEventGate.canApply(
            selectedConversationID: "conv-live",
            eventConversationID: "conv-live"
        ))
        XCTAssertFalse(ChatStreamEventGate.canApply(
            selectedConversationID: "conv-live",
            eventConversationID: "conv-stale"
        ))
        XCTAssertFalse(ChatStreamEventGate.canApply(
            selectedConversationID: nil,
            eventConversationID: "conv-live"
        ))
    }

    @MainActor
    func testMessageTimelineStoreDiscardsStaleConversationEvents() {
        let store = MessageTimelineStore()
        store.messages = [
            ChatMessage(
                id: "assistant-1",
                role: .assistant,
                text: "",
                model: ModelOption.nearPrivateDefaultModelID,
                createdAt: Date(timeIntervalSince1970: 1_000),
                status: "streaming",
                responseID: nil,
                isStreaming: true
            )
        ]

        store.applyIfConversationMatches(
            selectedConversationID: "conv-live",
            streamEvent: .textDelta("stale answer"),
            conversationID: "conv-stale",
            assistantMessageID: "assistant-1"
        )
        store.flushPendingTextDelta(for: "assistant-1")

        XCTAssertEqual(store.messages.first?.text, "")
        XCTAssertEqual(store.messages.first?.status, "streaming")

        store.applyIfConversationMatches(
            selectedConversationID: "conv-live",
            streamEvent: .textDelta("live answer"),
            conversationID: "conv-live",
            assistantMessageID: "assistant-1"
        )
        store.flushPendingTextDelta(for: "assistant-1")

        XCTAssertEqual(store.messages.first?.text, "live answer")
    }

    @MainActor
    func testChatStoreDiscardsStaleConversationStreamEvents() async {
        let timelineStore = MessageTimelineStore()
        let conversationStore = ConversationStore(
            repository: ConversationRepository(api: PrivateChatAPI(configuration: .production))
        )
        let store = ChatStore(
            api: PrivateChatAPI(configuration: .production),
            conversationStore: conversationStore,
            messageTimelineStore: timelineStore
        )
        let selectedConversation = ConversationSummary(
            id: "conv-live",
            createdAt: 1_700_000_000,
            metadata: ConversationMetadata(title: "Live")
        )
        store.selectedConversation = selectedConversation
        store.messages = [
            ChatMessage(
                id: "assistant-1",
                role: .assistant,
                text: "",
                model: ModelOption.nearPrivateDefaultModelID,
                createdAt: Date(timeIntervalSince1970: 1_000),
                status: "streaming",
                responseID: nil,
                isStreaming: true
            )
        ]

        await store.apply(
            streamEvent: .textDelta("stale answer"),
            conversationID: "conv-stale",
            assistantMessageID: "assistant-1"
        )
        timelineStore.flushPendingTextDelta(for: "assistant-1")

        XCTAssertEqual(store.messages.first?.text, "")
        XCTAssertEqual(store.messages.first?.status, "streaming")

        await store.apply(
            streamEvent: .textDelta("live answer"),
            conversationID: selectedConversation.id,
            assistantMessageID: "assistant-1"
        )
        timelineStore.flushPendingTextDelta(for: "assistant-1")

        XCTAssertEqual(store.messages.first?.text, "live answer")
    }

    @MainActor
    func testPrivateRouteBusyRetriesSameRouteOnceBeforeBreaker() async throws {
        PrivateRouteRetryURLProtocol.install(responses: [
            (
                statusCode: 403,
                body: """
                data: {"error":{"message":"The private route is temporarily busy. Try again in a moment."}}

                """
            ),
            (
                statusCode: 200,
                body: """
                data: {"type":"response.created","response":{"id":"resp_retry"}}
                data: {"type":"response.output_text.delta","delta":"Recovered privately."}
                data: {"type":"response.completed","response":{"id":"resp_retry"}}
                data: [DONE]

                """
            )
        ])
        defer { PrivateRouteRetryURLProtocol.uninstall() }

        let api = PrivateChatAPI(configuration: .production)
        api.authToken = "test-session-token"
        let routeHealth = RouteHealthMonitor()
        let diagnostics = ConnectionDiagnostics()
        let conversationStore = ConversationStore(
            repository: ConversationRepository(api: PrivateChatAPI(configuration: .production))
        )
        let timelineStore = MessageTimelineStore()
        let store = ChatStore(
            api: api,
            conversationStore: conversationStore,
            messageTimelineStore: timelineStore,
            routeHealth: routeHealth,
            diagnostics: diagnostics
        )
        let conversation = ConversationSummary(
            id: "conv-retry",
            createdAt: 1_700_000_000,
            metadata: ConversationMetadata(title: "Retry")
        )
        store.selectedConversation = conversation
        store.sendCurrentAssistantMessageID = "assistant-retry"
        store.messages = [
            ChatMessage(
                id: "assistant-retry",
                role: .assistant,
                text: "",
                model: ModelOption.nearPrivateDefaultModelID,
                createdAt: Date(timeIntervalSince1970: 1_000),
                status: "streaming",
                responseID: nil,
                isStreaming: true
            )
        ]

        let finalModel = try await store.streamResponseWithFallback(
            initialModel: ModelOption.nearPrivateDefaultModelID,
            text: "health check",
            attachments: [],
            conversationID: conversation.id,
            previousResponseID: nil,
            initiator: "test"
        )
        store.flushPendingTextDelta(for: "assistant-retry")

        XCTAssertEqual(finalModel, ModelOption.nearPrivateDefaultModelID)
        XCTAssertEqual(PrivateRouteRetryURLProtocol.requestPaths, ["/v1/responses", "/v1/responses"])
        XCTAssertFalse(routeHealth.isTripped(.nearPrivate))
        XCTAssertEqual(diagnostics.lastPrivateOutcome?.succeeded, true)
        XCTAssertEqual(store.messages.first?.text, "Recovered privately.")
    }

    @MainActor
    func testPrivateRouteTransportFailureRetriesSameRouteOnce() async throws {
        PrivateRouteRetryURLProtocol.install(responses: [
            (
                statusCode: 200,
                body: """
                data: {"type":"response.failed","response":{"error":{"message":"OpenAI API error: API error: error sending request for url (https://cloud-api.near.ai/v1/responses)"}}}
                data: [DONE]

                """
            ),
            (
                statusCode: 200,
                body: """
                data: {"type":"response.created","response":{"id":"resp_retry_transport"}}
                data: {"type":"response.output_text.delta","delta":"Recovered after transport miss."}
                data: {"type":"response.completed","response":{"id":"resp_retry_transport"}}
                data: [DONE]

                """
            )
        ])
        defer { PrivateRouteRetryURLProtocol.uninstall() }

        let api = PrivateChatAPI(configuration: .production)
        api.authToken = "test-session-token"
        let routeHealth = RouteHealthMonitor()
        let diagnostics = ConnectionDiagnostics()
        let conversationStore = ConversationStore(
            repository: ConversationRepository(api: PrivateChatAPI(configuration: .production))
        )
        let timelineStore = MessageTimelineStore()
        let store = ChatStore(
            api: api,
            conversationStore: conversationStore,
            messageTimelineStore: timelineStore,
            routeHealth: routeHealth,
            diagnostics: diagnostics
        )
        let conversation = ConversationSummary(
            id: "conv-transport-retry",
            createdAt: 1_700_000_000,
            metadata: ConversationMetadata(title: "Transport retry")
        )
        store.selectedConversation = conversation
        store.sendCurrentAssistantMessageID = "assistant-transport-retry"
        store.messages = [
            ChatMessage(
                id: "assistant-transport-retry",
                role: .assistant,
                text: "",
                model: ModelOption.nearPrivateDefaultModelID,
                createdAt: Date(timeIntervalSince1970: 1_000),
                status: "streaming",
                responseID: nil,
                isStreaming: true
            )
        ]

        let finalModel = try await store.streamResponseWithFallback(
            initialModel: ModelOption.nearPrivateDefaultModelID,
            text: "health check",
            attachments: [],
            conversationID: conversation.id,
            previousResponseID: nil,
            initiator: "test"
        )
        store.flushPendingTextDelta(for: "assistant-transport-retry")

        XCTAssertEqual(finalModel, ModelOption.nearPrivateDefaultModelID)
        XCTAssertEqual(PrivateRouteRetryURLProtocol.requestPaths, ["/v1/responses", "/v1/responses"])
        XCTAssertFalse(routeHealth.isTripped(.nearPrivate))
        XCTAssertEqual(diagnostics.lastPrivateOutcome?.succeeded, true)
        XCTAssertEqual(store.messages.first?.text, "Recovered after transport miss.")
    }

    @MainActor
    func testPrivateRouteRateLimitDoesNotAutoRetrySameRoute() async throws {
        PrivateRouteRetryURLProtocol.install(responses: [
            (
                statusCode: 403,
                body: """
                data: {"error":{"message":"Access temporarily restricted. Please try again later."}}

                """
            ),
            (
                statusCode: 200,
                body: """
                data: {"type":"response.created","response":{"id":"resp_should_not_run"}}
                data: {"type":"response.output_text.delta","delta":"This should not render."}
                data: {"type":"response.completed","response":{"id":"resp_should_not_run"}}
                data: [DONE]

                """
            )
        ])
        defer { PrivateRouteRetryURLProtocol.uninstall() }

        let api = PrivateChatAPI(configuration: .production)
        api.authToken = "test-session-token"
        let routeHealth = RouteHealthMonitor()
        let diagnostics = ConnectionDiagnostics()
        let conversationStore = ConversationStore(
            repository: ConversationRepository(api: PrivateChatAPI(configuration: .production))
        )
        let timelineStore = MessageTimelineStore()
        let store = ChatStore(
            api: api,
            conversationStore: conversationStore,
            messageTimelineStore: timelineStore,
            routeHealth: routeHealth,
            diagnostics: diagnostics
        )
        let conversation = ConversationSummary(
            id: "conv-rate-limit",
            createdAt: 1_700_000_000,
            metadata: ConversationMetadata(title: "Rate limit")
        )
        store.selectedConversation = conversation
        store.sendCurrentAssistantMessageID = "assistant-rate-limit"
        store.messages = [
            ChatMessage(
                id: "assistant-rate-limit",
                role: .assistant,
                text: "",
                model: ModelOption.nearPrivateDefaultModelID,
                createdAt: Date(timeIntervalSince1970: 1_000),
                status: "streaming",
                responseID: nil,
                isStreaming: true
            )
        ]

        do {
            _ = try await store.streamResponseWithFallback(
                initialModel: ModelOption.nearPrivateDefaultModelID,
                text: "health check",
                attachments: [],
                conversationID: conversation.id,
                previousResponseID: nil,
                initiator: "test"
            )
            XCTFail("Explicit private-route rate limits must not auto-retry.")
        } catch {
            XCTAssertEqual(PrivateRouteRetryURLProtocol.requestPaths, ["/v1/responses"])
            XCTAssertTrue(routeHealth.isTripped(.nearPrivate))
            XCTAssertEqual(diagnostics.lastPrivateOutcome?.succeeded, false)
            XCTAssertTrue(diagnostics.privateLooksSessionRateLimited)
            XCTAssertEqual(store.messages.first?.text, "")
        }
    }

    func testWidgetStrippedStreamingPreviewHidesUnclosedFence() {
        let text = "Partial answer text.\n\n```near-widget\n{\"kind\":\"chart\","
        let preview = MessageWidget.strippedStreamingPreview(text)
        XCTAssertEqual(preview, "Partial answer text.")
        XCTAssertFalse(preview.contains("near-widget"))
    }

    func testWidgetStrippedStreamingPreviewHidesGenericFenceWithSentinel() {
        let text = "Partial answer text.\n\n```json\nNEAR-WIDGET\n{\"kind\":\"news_brief\","
        let preview = MessageWidget.strippedStreamingPreview(text)
        XCTAssertEqual(preview, "Partial answer text.")
        XCTAssertFalse(preview.contains("NEAR-WIDGET"))
        XCTAssertFalse(preview.contains("\"kind\""))
    }

    @MainActor
    func testMessageTimelineStoreAppliesStreamEventsOutsideChatStore() {
        let store = MessageTimelineStore()
        let assistant = ChatMessage(
            id: "assistant-1",
            role: .assistant,
            text: "",
            model: ModelOption.nearPrivateDefaultModelID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            status: "streaming",
            responseID: nil,
            isStreaming: true
        )
        let source = WebSearchSource(type: "news_article", url: "https://example.com/report", title: "Report")
        var titleUpdate: (conversationID: String, title: String)?
        store.messages = [assistant]

        store.apply(streamEvent: .created(responseID: "resp-1"), conversationID: "conv-1", assistantMessageID: "assistant-1")
        store.apply(streamEvent: .webSearchStarted(query: "latest report"), conversationID: "conv-1", assistantMessageID: "assistant-1")
        store.apply(streamEvent: .webSearchCompleted(query: "latest report", sources: [source]), conversationID: "conv-1", assistantMessageID: "assistant-1")
        store.apply(streamEvent: .textDelta("Hello"), conversationID: "conv-1", assistantMessageID: "assistant-1")
        store.flushPendingTextDelta(for: "assistant-1")
        store.apply(streamEvent: .completed(responseID: "resp-1"), conversationID: "conv-1", assistantMessageID: "assistant-1")
        store.apply(
            streamEvent: .titleUpdated("Better title"),
            conversationID: "conv-1",
            assistantMessageID: "assistant-1"
        ) { conversationID, title in
            titleUpdate = (conversationID, title)
        }

        let updated = store.messages.first
        XCTAssertEqual(updated?.text, "Hello")
        XCTAssertEqual(updated?.responseID, "resp-1")
        XCTAssertEqual(updated?.status, "completed")
        XCTAssertEqual(updated?.isStreaming, false)
        XCTAssertEqual(updated?.searchQuery, "latest report")
        XCTAssertEqual(updated?.sources, [source])
        XCTAssertNotNil(updated?.firstTokenAt)
        XCTAssertEqual(titleUpdate?.conversationID, "conv-1")
        XCTAssertEqual(titleUpdate?.title, "Better title")
    }

    @MainActor
    func testMessageTimelineStoreCancelsAndFlushesStreamingMessages() {
        let store = MessageTimelineStore()
        store.messages = [
            ChatMessage(
                id: "assistant-1",
                role: .assistant,
                text: "",
                model: ModelOption.nearPrivateDefaultModelID,
                createdAt: Date(timeIntervalSince1970: 1_000),
                status: "streaming",
                responseID: nil,
                isStreaming: true
            ),
            ChatMessage(
                id: "council-1",
                role: .assistant,
                text: "",
                model: ModelOption.nearPrivateDefaultModelID,
                createdAt: Date(timeIntervalSince1970: 1_001),
                status: "streaming",
                responseID: nil,
                councilBatchID: "batch-1",
                isStreaming: true
            )
        ]

        store.apply(streamEvent: .textDelta("partial"), conversationID: "conv-1", assistantMessageID: "assistant-1")
        store.apply(streamEvent: .textDelta("council"), conversationID: "conv-1", assistantMessageID: "council-1")
        store.markStreamingMessagesCancelled(
            assistantMessageID: "assistant-1",
            councilAssistantMessageIDs: ["council-1"]
        )

        XCTAssertEqual(store.messages.first(where: { $0.id == "assistant-1" })?.text, "partial")
        XCTAssertEqual(store.messages.first(where: { $0.id == "assistant-1" })?.status, "cancelled")
        XCTAssertEqual(store.messages.first(where: { $0.id == "assistant-1" })?.isStreaming, false)
        XCTAssertEqual(store.messages.first(where: { $0.id == "council-1" })?.text, "council")
        XCTAssertEqual(store.messages.first(where: { $0.id == "council-1" })?.status, "cancelled")
        XCTAssertEqual(store.messages.first(where: { $0.id == "council-1" })?.isStreaming, false)
    }

    @MainActor
    func testSendDraftDataQuestionFallsThroughToModelRouting() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.draft = "what is the eth price"

        store.sendDraft()

        // Bare answer requests must not be replaced by a hardcoded live-data
        // widget. They fall through to normal model routing/readiness instead.
        XCTAssertFalse(store.isStreaming)
        XCTAssertTrue(store.messages.isEmpty)
    }


    @MainActor
    func testSendDraftCreateTrackerInvokesCallbackWithoutStreaming() throws {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        var created: Briefing?
        store.onCreateTracker = { created = $0 }
        store.draft = "create a tracker to tell me the eth price every morning at 8 am using council"

        store.sendDraft()

        let briefing = try XCTUnwrap(created)
        XCTAssertEqual(briefing.kind, .customPrompt)
        XCTAssertNil(briefing.accountID)
        XCTAssertEqual(briefing.schedule, .daily(hour: 8, minute: 0))
        XCTAssertTrue(briefing.prompt.contains("Run this recurring workflow through chat"))
        XCTAssertTrue(briefing.prompt.contains("ETH"))
        // Tracker creation is synchronous: a confirmation turn, no streaming.
        XCTAssertFalse(store.isStreaming)
        XCTAssertEqual(store.messages.first?.role, .user)
        XCTAssertEqual(store.messages.last?.role, .assistant)
        XCTAssertTrue(store.messages.last?.text.contains("Created a tracker") == true)
    }


    @MainActor
    func testCancelStreamFinalizesCurrentAssistantMessage() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.sendMessages = [
            ChatMessage(
                id: "assistant-cancel",
                role: .assistant,
                text: "partial",
                model: ModelOption.nearPrivateDefaultModelID,
                createdAt: Date(timeIntervalSince1970: 1_000),
                status: "streaming",
                responseID: nil,
                isStreaming: true
            )
        ]
        store.sendCurrentAssistantMessageID = "assistant-cancel"
        store.sendIsStreaming = true
        store.sendStreamTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        XCTAssertTrue(store.isStreaming)

        store.cancelStream()

        XCTAssertFalse(store.isStreaming)
        XCTAssertNil(store.sendStreamTask)
        let placeholder = store.messages.first { $0.id == "assistant-cancel" }
        XCTAssertEqual(placeholder?.isStreaming, false)
        XCTAssertEqual(placeholder?.status, "cancelled")
    }
}

private final class PrivateRouteRetryURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var queuedResponses: [(statusCode: Int, body: String)] = []
    private(set) static var requestPaths: [String] = []

    static func install(responses: [(statusCode: Int, body: String)]) {
        lock.lock()
        queuedResponses = responses
        requestPaths = []
        lock.unlock()
        URLProtocol.registerClass(Self.self)
    }

    static func uninstall() {
        URLProtocol.unregisterClass(Self.self)
        lock.lock()
        queuedResponses = []
        requestPaths = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path == "/v1/responses"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: APIError.invalidURL)
            return
        }

        Self.lock.lock()
        Self.requestPaths.append(url.path)
        let response = Self.queuedResponses.isEmpty
            ? (statusCode: 500, body: #"data: {"error":{"message":"unexpected request"}}"#)
            : Self.queuedResponses.removeFirst()
        Self.lock.unlock()

        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
