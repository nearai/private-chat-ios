import Foundation

enum ConversationTranscriptClipboard {
    enum Result: Equatable {
        case copied
        case emptyTranscript
    }

    @discardableResult
    static func copyTranscript(
        conversation: ConversationSummary?,
        messages: [ChatMessage]
    ) -> Result {
        guard !messages.isEmpty else {
            return .emptyTranscript
        }

        let transcript = ConversationExportBuilder.transcriptText(
            conversation: conversation,
            messages: messages
        )
        Clipboard.copy(transcript)
        return .copied
    }
}
