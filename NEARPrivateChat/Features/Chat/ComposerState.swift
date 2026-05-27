import Foundation

struct ComposerState: Hashable {
    let draft: String
    let pendingAttachments: [ChatAttachment]
    let isStreaming: Bool
    let routeReadinessTitle: String?
    let routeReadinessMessage: String?

    var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var pendingAttachmentCount: Int {
        pendingAttachments.count
    }

    var hasSendableContent: Bool {
        !trimmedDraft.isEmpty || !pendingAttachments.isEmpty
    }

    var sendDisabled: Bool {
        isStreaming ? false : !hasSendableContent
    }
}
