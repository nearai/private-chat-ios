import Foundation

@MainActor
final class FileStore: ObservableObject {
    @Published private(set) var remoteFiles: [RemoteFileInfo] = []
    @Published private(set) var remoteFilePreview: RemoteFilePreview?
    @Published private(set) var isLoadingRemoteFiles = false
    @Published private(set) var isLoadingRemoteFilePreview = false

    var bannerHandler: (@MainActor (String) -> Void)?

    private let service: FileService

    init(service: FileService) {
        self.service = service
    }

    enum AttachmentLimit: Equatable {
        case allowed
        case blocked(message: String)
    }

    func reset() {
        remoteFiles = []
        remoteFilePreview = nil
        isLoadingRemoteFiles = false
        isLoadingRemoteFilePreview = false
    }

    func refreshRemoteFiles(showErrors: Bool = true) async {
        guard !isLoadingRemoteFiles else { return }
        isLoadingRemoteFiles = true
        defer { isLoadingRemoteFiles = false }

        do {
            remoteFiles = try await service.remoteFiles()
            if showErrors {
                showBanner("File library refreshed.")
            }
        } catch {
            if showErrors {
                showBanner(error.localizedDescription)
            }
        }
    }

    func previewRemoteFile(_ file: RemoteFileInfo) async {
        guard !isLoadingRemoteFilePreview else { return }
        isLoadingRemoteFilePreview = true
        remoteFilePreview = nil
        defer { isLoadingRemoteFilePreview = false }

        do {
            remoteFilePreview = try await service.remoteFilePreview(file)
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    @discardableResult
    func deleteRemoteFile(_ file: RemoteFileInfo) async -> String? {
        do {
            try await service.deleteRemoteFile(file.id)
            remoteFiles.removeAll { $0.id == file.id }
            if remoteFilePreview?.id == file.id {
                remoteFilePreview = nil
            }
            showBanner("Deleted \(file.name).")
            return file.id
        } catch {
            showBanner(error.localizedDescription)
            return nil
        }
    }

    func registerUploadedAttachment(_ attachment: ChatAttachment) {
        guard !attachment.isLocalOnly else { return }
        guard !remoteFiles.contains(where: { $0.id == attachment.id }) else { return }
        remoteFiles.insert(
            RemoteFileInfo(
                id: attachment.id,
                bytes: attachment.bytes,
                createdAt: Date().timeIntervalSince1970,
                filename: attachment.name,
                purpose: attachment.kind
            ),
            at: 0
        )
    }

    nonisolated static func promptAttachmentLimit(
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

    nonisolated static func projectAttachmentLimit(
        projectAttachmentCount: Int,
        maxProjectAttachments: Int
    ) -> AttachmentLimit {
        guard projectAttachmentCount < maxProjectAttachments else {
            return .blocked(message: "A Project holds up to twelve files.")
        }
        return .allowed
    }

    private func showBanner(_ message: String) {
        bannerHandler?(message)
    }
}
