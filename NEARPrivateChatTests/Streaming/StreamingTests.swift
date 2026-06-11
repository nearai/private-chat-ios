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
    }

    func testWidgetStrippedStreamingPreviewHidesUnclosedFence() {
        let text = "Partial answer text.\n\n```near-widget\n{\"kind\":\"chart\","
        let preview = MessageWidget.strippedStreamingPreview(text)
        XCTAssertEqual(preview, "Partial answer text.")
        XCTAssertFalse(preview.contains("near-widget"))
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
