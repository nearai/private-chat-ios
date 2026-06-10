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

    /// Local intents are handled on-device — no model produced the reply, so the
    /// message carries no model identity and no proof metadata. Claiming the
    /// selected model (and rendering a proof footer) for an app-generated turn
    /// is a trust bug.
    static func assistantMessage(
        id: String = "local-assistant-\(UUID().uuidString)",
        text: String,
        createdAt: Date = Date(),
        status: String = "completed",
        isStreaming: Bool = false,
        widget: MessageWidget? = nil
    ) -> ChatMessage {
        var message = ChatMessage(
            id: id,
            role: .assistant,
            text: text,
            model: nil,
            createdAt: createdAt,
            status: status,
            responseID: nil,
            isStreaming: isStreaming,
            trustMetadata: nil
        )
        message.widget = widget
        return message
    }

    @discardableResult
    static func appendAssistant(
        text: String,
        messages: inout [ChatMessage],
        widget: MessageWidget? = nil,
        streaming: Bool = false
    ) -> String {
        let createdAt = Date()
        let id = "local-assistant-\(UUID().uuidString)"
        messages.append(assistantMessage(
            id: id,
            text: text,
            createdAt: createdAt,
            status: streaming ? "searching" : "completed",
            isStreaming: streaming,
            widget: widget
        ))
        return id
    }
}
