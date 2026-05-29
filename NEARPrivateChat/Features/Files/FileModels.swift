import Foundation
import SwiftUI

struct ChatAttachment: Identifiable, Codable, Hashable {
    static let pendingTextKind = "pending_text"
    static let localDocumentKind = "pdf_local"

    var id: String
    var name: String
    var kind: String
    var bytes: Int?

    var isLocalPendingText: Bool {
        kind == Self.pendingTextKind || id.hasPrefix("local-paste-")
    }

    /// A document kept entirely on-device (privacy mode): never uploaded to the
    /// backend; only its relevant passages are inlined into the prompt at send.
    var isLocalOnly: Bool {
        kind == Self.localDocumentKind || id.hasPrefix("local-doc-")
    }

    var displaySize: String? {
        guard let bytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var displayKind: String {
        if isLocalPendingText {
            return "Text paste"
        }
        if isLocalOnly {
            return "PDF · on device"
        }
        if kind == "pdf_text" {
            return "PDF text"
        }
        let fileExtension = (name as NSString).pathExtension.lowercased()
        switch fileExtension {
        case "pdf":
            return "PDF"
        case "md", "markdown":
            return "Markdown"
        case "csv":
            return "CSV"
        case "json":
            return "JSON"
        case "txt", "text":
            return "Text"
        default:
            return kind
        }
    }

    var systemImageName: String {
        if isLocalPendingText {
            return "doc.text"
        }
        let fileExtension = (name as NSString).pathExtension.lowercased()
        switch fileExtension {
        case "pdf":
            return "doc.richtext"
        case "csv":
            return "tablecells"
        case "json":
            return "curlybraces"
        case "md", "markdown", "txt", "text":
            return "doc.text"
        default:
            return "paperclip"
        }
    }
}

struct RemoteFileInfo: Identifiable, Decodable, Hashable {
    var id: String
    var object: String?
    var bytes: Int?
    var createdAt: TimeInterval?
    var expiresAt: TimeInterval?
    var filename: String?
    var purpose: String?

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case bytes
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case filename
        case purpose
    }

    init(
        id: String,
        object: String? = nil,
        bytes: Int? = nil,
        createdAt: TimeInterval? = nil,
        expiresAt: TimeInterval? = nil,
        filename: String? = nil,
        purpose: String? = nil
    ) {
        self.id = id
        self.object = object
        self.bytes = bytes
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.filename = filename
        self.purpose = purpose
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        bytes = try container.decodeIfPresent(Int.self, forKey: .bytes)
        createdAt = Self.decodeTimeInterval(from: container, forKey: .createdAt)
        expiresAt = Self.decodeTimeInterval(from: container, forKey: .expiresAt)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        purpose = try container.decodeIfPresent(String.self, forKey: .purpose)
    }

    var name: String {
        let trimmed = (filename ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
    }

    var displaySize: String? {
        guard let bytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var displayKind: String {
        attachment.displayKind
    }

    var systemImageName: String {
        attachment.systemImageName
    }

    var createdAtDisplay: String? {
        guard let createdAt else { return nil }
        return Date(timeIntervalSince1970: createdAt).formatted(date: .abbreviated, time: .shortened)
    }

    var attachment: ChatAttachment {
        ChatAttachment(id: id, name: name, kind: purpose ?? "user_data", bytes: bytes)
    }

    private static func decodeTimeInterval(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> TimeInterval? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return TimeInterval(value)
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return TimeInterval(value)
        }
        return nil
    }
}

struct RemoteFilesResponse: Decodable, Hashable {
    var object: String?
    var data: [RemoteFileInfo]
    var firstID: String?
    var lastID: String?
    var hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case object
        case data
        case firstID = "first_id"
        case lastID = "last_id"
        case hasMore = "has_more"
    }

    init(from decoder: Decoder) throws {
        if var unkeyedContainer = try? decoder.unkeyedContainer() {
            object = nil
            firstID = nil
            lastID = nil
            hasMore = nil
            var files: [RemoteFileInfo] = []
            while !unkeyedContainer.isAtEnd {
                files.append(try unkeyedContainer.decode(RemoteFileInfo.self))
            }
            data = files
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        data = try container.decodeIfPresent([RemoteFileInfo].self, forKey: .data) ?? []
        firstID = try container.decodeIfPresent(String.self, forKey: .firstID)
        lastID = try container.decodeIfPresent(String.self, forKey: .lastID)
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore)
    }
}

struct RemoteFilePreview: Identifiable, Hashable {
    var id: String { file.id }
    var file: RemoteFileInfo
    var text: String
    var byteCount: Int
    var isText: Bool
    var isTruncated: Bool

    init(file: RemoteFileInfo, data: Data, maxPreviewBytes: Int = 96 * 1024) {
        self.file = file
        byteCount = data.count
        let previewData = Data(data.prefix(maxPreviewBytes))
        isTruncated = data.count > maxPreviewBytes

        if let decoded = String(data: previewData, encoding: .utf8) {
            isText = true
            text = decoded
        } else if data.prefix(4).elementsEqual([0x25, 0x50, 0x44, 0x46]) {
            isText = false
            text = "PDF binary loaded. Add it to a prompt or project so the model can use it as file context."
        } else {
            isText = false
            text = "Binary preview unavailable. Add it to a prompt or project so the model can use it as file context."
        }
    }
}
