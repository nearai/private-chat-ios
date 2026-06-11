import XCTest
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    @MainActor
    func testFileStoreSuiteCacheMissPreviewAndDeleteInvalidation() async throws {
        let api = FileStoreSuiteAPI()
        api.files = [
            RemoteFileInfo(id: "file-old", bytes: 10, createdAt: 100, filename: "old.txt", purpose: "user_data"),
            RemoteFileInfo(id: "file-new", bytes: 20, createdAt: 200, filename: "new.txt", purpose: "user_data")
        ]
        api.metadataByID["file-new"] = RemoteFileInfo(
            id: "file-new",
            bytes: 20,
            createdAt: 200,
            filename: "renamed-new.txt",
            purpose: "user_data"
        )
        api.previewDataByID["file-new"] = Data("Preview body sentinel".utf8)
        let store = FileStore(service: FileService(fileAPI: api))

        await store.refreshRemoteFiles(showErrors: false)
        XCTAssertEqual(store.remoteFiles.map(\.id), ["file-new", "file-old"])

        await store.previewRemoteFile(store.remoteFiles[0])
        XCTAssertEqual(store.remoteFilePreview?.id, "file-new")
        XCTAssertEqual(store.remoteFilePreview?.file.name, "renamed-new.txt")
        XCTAssertTrue(store.remoteFilePreview?.text.contains("Preview body sentinel") == true)
        XCTAssertEqual(api.previewFetches, ["file-new"])

        let deletedID = await store.deleteRemoteFile(store.remoteFiles[0])
        XCTAssertEqual(deletedID, "file-new")
        XCTAssertEqual(api.deletedFileIDs, ["file-new"])
        XCTAssertEqual(store.remoteFiles.map(\.id), ["file-old"])
        XCTAssertNil(store.remoteFilePreview)
    }

    @MainActor
    func testAttachmentStagingStoreDocumentSentinelIsInjectedAndLocalOnlyCanBeExcluded() {
        let store = AttachmentStagingStore()
        let uploaded = ChatAttachment(id: "file-uploaded", name: "report-pdf-text.txt", kind: "pdf_text", bytes: 128)
        let localOnly = ChatAttachment(
            id: "file-local",
            name: "local-notes.pdf",
            kind: ChatAttachment.localDocumentKind,
            bytes: 128
        )
        store.stageDocumentText(
            "Acme renewal sentinel: payment is due on June 30 and the counterparty is Vega Labs.",
            for: uploaded.id
        )
        store.stageDocumentText(
            "Local only sentinel that must not ride to cloud or hosted routes.",
            for: localOnly.id
        )

        let privatePrompt = store.documentAugmentedPrompt(
            "Summarize the renewal.",
            question: "What is the Acme renewal deadline?",
            attachments: [uploaded, localOnly]
        )
        XCTAssertTrue(privatePrompt.contains("Acme renewal sentinel"))
        XCTAssertTrue(privatePrompt.contains("Relevant excerpts"))

        let cloudSafePrompt = store.documentAugmentedPrompt(
            "Summarize the renewal.",
            question: "What is the Acme renewal deadline?",
            attachments: [uploaded, localOnly].filter { !$0.isLocalOnly }
        )
        XCTAssertTrue(cloudSafePrompt.contains("Acme renewal sentinel"))
        XCTAssertFalse(cloudSafePrompt.contains("Local only sentinel"))
    }
}

private final class FileStoreSuiteAPI: FileAPI {
    var files: [RemoteFileInfo] = []
    var metadataByID: [String: RemoteFileInfo] = [:]
    var previewDataByID: [String: Data] = [:]
    var previewFetches: [String] = []
    var deletedFileIDs: [String] = []

    func uploadFile(from url: URL) async throws -> ChatAttachment {
        ChatAttachment(id: "uploaded-file", name: url.lastPathComponent, kind: "user_data", bytes: nil)
    }

    func uploadTextFile(filename: String, text: String) async throws -> ChatAttachment {
        ChatAttachment(id: "uploaded-text", name: filename, kind: "user_data", bytes: text.utf8.count)
    }

    func fetchFiles() async throws -> RemoteFilesResponse {
        let data = try JSONEncoder().encode(files.map(RemoteFilePayload.init))
        return try JSONDecoder().decode(RemoteFilesResponse.self, from: data)
    }

    func fetchFile(_ fileID: String) async throws -> RemoteFileInfo {
        metadataByID[fileID] ?? files.first { $0.id == fileID } ?? RemoteFileInfo(id: fileID, filename: "\(fileID).txt")
    }

    func fetchFileContent(_ fileID: String) async throws -> Data {
        previewDataByID[fileID] ?? Data()
    }

    func fetchFilePreviewContent(_ fileID: String, maxBytes: Int) async throws -> Data {
        previewFetches.append(fileID)
        return Data((previewDataByID[fileID] ?? Data()).prefix(maxBytes))
    }

    func deleteFile(_ fileID: String) async throws {
        deletedFileIDs.append(fileID)
    }

    private struct RemoteFilePayload: Encodable {
        let id: String
        let bytes: Int?
        let created_at: TimeInterval?
        let filename: String?
        let purpose: String?

        init(_ file: RemoteFileInfo) {
            id = file.id
            bytes = file.bytes
            created_at = file.createdAt
            filename = file.filename
            purpose = file.purpose
        }
    }
}
