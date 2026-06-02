import Foundation

enum ChatLocalIntentTranscriptWriter {
    static func userMessage(
        id: String = "local-user-\(UUID().uuidString)",
        text: String,
        model: String,
        createdAt: Date = Date()
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            role: .user,
            text: text,
            model: model,
            createdAt: createdAt,
            status: "completed",
            responseID: nil,
            isStreaming: false
        )
    }

    static func assistantMessage(
        id: String = "local-assistant-\(UUID().uuidString)",
        text: String,
        model: String,
        createdAt: Date = Date(),
        status: String = "completed",
        isStreaming: Bool = false,
        widget: MessageWidget? = nil,
        trustMetadata: MessageTrustMetadata?
    ) -> ChatMessage {
        var message = ChatMessage(
            id: id,
            role: .assistant,
            text: text,
            model: model,
            createdAt: createdAt,
            status: status,
            responseID: nil,
            isStreaming: isStreaming,
            trustMetadata: trustMetadata
        )
        message.widget = widget
        return message
    }

    @discardableResult
    static func appendAssistant(
        text: String,
        model: String,
        messages: inout [ChatMessage],
        widget: MessageWidget? = nil,
        streaming: Bool = false,
        trustMetadata: (Date) -> MessageTrustMetadata?
    ) -> String {
        let createdAt = Date()
        let id = "local-assistant-\(UUID().uuidString)"
        messages.append(assistantMessage(
            id: id,
            text: text,
            model: model,
            createdAt: createdAt,
            status: streaming ? "searching" : "completed",
            isStreaming: streaming,
            widget: widget,
            trustMetadata: trustMetadata(createdAt)
        ))
        return id
    }
}
