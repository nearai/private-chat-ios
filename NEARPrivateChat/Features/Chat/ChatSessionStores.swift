import Foundation

@MainActor
final class ChatTranscriptStore: ObservableObject {
    @Published private(set) var state = ChatTranscriptState()

    var messages: [ChatMessage] {
        get { state.messages }
        set {
            guard state.messages != newValue else { return }
            state = state.updating(messages: newValue)
        }
    }

    var isStreaming: Bool {
        get { state.isStreaming }
        set {
            guard state.isStreaming != newValue else { return }
            state = state.updating(isStreaming: newValue)
        }
    }
}

struct ChatTranscriptState {
    let messages: [ChatMessage]
    let displayItems: [ChatDisplayItem]
    let isStreaming: Bool

    init(messages: [ChatMessage] = [], isStreaming: Bool = false) {
        self.messages = messages
        self.displayItems = MessageTimelineStore.displayItems(from: messages)
        self.isStreaming = isStreaming
    }

    private init(messages: [ChatMessage], displayItems: [ChatDisplayItem], isStreaming: Bool) {
        self.messages = messages
        self.displayItems = displayItems
        self.isStreaming = isStreaming
    }

    func updating(messages: [ChatMessage]) -> ChatTranscriptState {
        ChatTranscriptState(messages: messages, isStreaming: isStreaming)
    }

    func updating(isStreaming: Bool) -> ChatTranscriptState {
        ChatTranscriptState(messages: messages, displayItems: displayItems, isStreaming: isStreaming)
    }
}

@MainActor
final class ChatComposerStore: ObservableObject {
    @Published var draft = ""
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var isUploadingAttachment = false
    @Published var routeReadinessIssue: ChatRouteReadinessIssue?
}
