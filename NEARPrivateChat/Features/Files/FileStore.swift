import Foundation

struct FileStore {
    enum AttachmentLimit: Equatable {
        case allowed
        case blocked(message: String)
    }

    static func promptAttachmentLimit(
        pendingCount: Int,
        projectContextCount: Int,
        maxPromptAttachments: Int,
        maxContextAttachments: Int
    ) -> AttachmentLimit {
        guard pendingCount < maxPromptAttachments else {
            return .blocked(message: "Attach up to five files at once.")
        }
        guard pendingCount + projectContextCount < maxContextAttachments else {
            return .blocked(message: "This prompt is at its file-context limit.")
        }
        return .allowed
    }

    static func projectAttachmentLimit(
        projectAttachmentCount: Int,
        maxProjectAttachments: Int
    ) -> AttachmentLimit {
        guard projectAttachmentCount < maxProjectAttachments else {
            return .blocked(message: "A Project holds up to twelve files.")
        }
        return .allowed
    }
}
