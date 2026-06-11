import Foundation

struct ImportedChatConversation {
    let title: String
    let timestamp: TimeInterval?
    let items: [ConversationImportItem]

    var batchedItems: [[ConversationImportItem]] {
        var batches: [[ConversationImportItem]] = []
        var currentBatch: [ConversationImportItem] = []
        var hasResponseInBatch = false

        for item in items {
            if item.role == "user", !currentBatch.isEmpty, hasResponseInBatch {
                batches.append(currentBatch)
                currentBatch = []
                hasResponseInBatch = false
            }

            currentBatch.append(item)
            if item.role != "user" {
                hasResponseInBatch = true
            }
        }

        if !currentBatch.isEmpty {
            if hasResponseInBatch || batches.isEmpty {
                batches.append(currentBatch)
            } else if let lastIndex = batches.indices.last {
                batches[lastIndex].append(contentsOf: currentBatch)
            }
        }

        return batches
    }
}

enum ChatImportLimits {
    static let maxImportBytes = 8 * 1024 * 1024
    static let maxConversationCount = 100
    static let maxTotalItemCount = 5_000
    static let maxItemsPerConversation = 1_000
    static let maxContentPartsPerItem = 20
    static let maxTextBytesPerItem = 256 * 1024
    static let maxEmbeddedFileCharacters = 2 * 1024 * 1024
    static let maxImageURLCharacters = 2_048
}

struct ConversationImportItem: Encodable {
    let type = "message"
    let role: String
    let content: [ConversationImportContent]
    let model: String?

    enum CodingKeys: String, CodingKey {
        case type
        case role
        case content
        case model
    }
}

struct ConversationImportContent: Encodable {
    let type: String
    let text: String?
    let filename: String?
    let fileData: String?
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case filename
        case fileData = "file_data"
        case imageURL = "image_url"
    }

    static func text(_ text: String, role: String) -> ConversationImportContent {
        ConversationImportContent(
            type: role == "user" ? "input_text" : "output_text",
            text: text,
            filename: nil,
            fileData: nil,
            imageURL: nil
        )
    }

    static func file(filename: String, data: String) -> ConversationImportContent {
        ConversationImportContent(
            type: "input_file",
            text: nil,
            filename: filename,
            fileData: data,
            imageURL: nil
        )
    }

    static func image(url: String) -> ConversationImportContent {
        ConversationImportContent(
            type: "input_image",
            text: nil,
            filename: nil,
            fileData: nil,
            imageURL: url
        )
    }
}

enum ChatImportBuilder {
    static func conversations(from data: Data) throws -> [ImportedChatConversation] {
        guard data.count <= ChatImportLimits.maxImportBytes else {
            throw ChatImportError.tooLarge("Import JSON must be 8 MB or smaller.")
        }
        let decoder = JSONDecoder()
        if let payloads = try? decoder.decode([NativeExportPayload].self, from: data) {
            return try validated(payloads.map(nativeConversation(from:)).filter { !$0.items.isEmpty })
        }
        if let payload = try? decoder.decode(NativeExportPayload.self, from: data) {
            return try validated([nativeConversation(from: payload)].filter { !$0.items.isEmpty })
        }
        if let histories = try? decoder.decode([LegacyChatHistory].self, from: data) {
            return try validated(histories.map(legacyConversation(from:)).filter { !$0.items.isEmpty })
        }
        throw ChatImportError.invalidFormat
    }

    private static func validated(_ conversations: [ImportedChatConversation]) throws -> [ImportedChatConversation] {
        guard conversations.count <= ChatImportLimits.maxConversationCount else {
            throw ChatImportError.tooLarge("Import contains more than \(ChatImportLimits.maxConversationCount) conversations.")
        }

        var totalItems = 0
        for conversation in conversations {
            guard conversation.items.count <= ChatImportLimits.maxItemsPerConversation else {
                throw ChatImportError.tooLarge("One imported conversation has more than \(ChatImportLimits.maxItemsPerConversation) messages.")
            }
            totalItems += conversation.items.count
            guard totalItems <= ChatImportLimits.maxTotalItemCount else {
                throw ChatImportError.tooLarge("Import contains more than \(ChatImportLimits.maxTotalItemCount) messages.")
            }
            for item in conversation.items {
                try validate(item)
            }
        }
        return conversations
    }

    private static func validate(_ item: ConversationImportItem) throws {
        guard item.content.count <= ChatImportLimits.maxContentPartsPerItem else {
            throw ChatImportError.tooLarge("One imported message contains too many attachments.")
        }
        for content in item.content {
            if let text = content.text,
               text.utf8.count > ChatImportLimits.maxTextBytesPerItem {
                throw ChatImportError.tooLarge("One imported message is larger than 256 KB.")
            }
            if let fileData = content.fileData,
               fileData.count > ChatImportLimits.maxEmbeddedFileCharacters {
                throw ChatImportError.tooLarge("One imported attachment is larger than 2 MB.")
            }
            if let imageURL = content.imageURL,
               imageURL.count > ChatImportLimits.maxImageURLCharacters {
                throw ChatImportError.tooLarge("One imported image URL is too long.")
            }
            if let imageURL = content.imageURL,
               !isSafeImportedImageURL(imageURL) {
                throw ChatImportError.invalidFormat
            }
        }
    }

    private static func isSafeImportedImageURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= ChatImportLimits.maxImageURLCharacters,
              trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: trimmed) else { return false }
        return URLSecurity.isPublicHTTPSURL(url)
    }

    private static func nativeConversation(from payload: NativeExportPayload) -> ImportedChatConversation {
        ImportedChatConversation(
            title: payload.conversation?.title ?? "Imported Chat",
            timestamp: payload.conversation?.createdAt,
            items: payload.messages.compactMap { message in
                let role = normalizedRole(message.role)
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return ConversationImportItem(
                    role: role,
                    content: [.text(text, role: role)],
                    model: normalizeModelID(message.model ?? "")
                )
            }
        )
    }

    private static func legacyConversation(from history: LegacyChatHistory) -> ImportedChatConversation {
        let messages = history.chat.history.messages
            .sorted { lhs, rhs in lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending }
            .flatMap { _, message -> [ConversationImportItem] in
                let role = normalizedRole(message.role)
                let model = normalizeModelID(message.models?.first ?? message.model ?? "")
                var items: [ConversationImportItem] = []
                let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedContent.isEmpty {
                    items.append(ConversationImportItem(
                        role: role,
                        content: [.text(trimmedContent, role: role)],
                        model: model
                    ))
                }

                for file in message.files ?? [] {
                    switch file {
                    case let .file(filename, content):
                        items.append(ConversationImportItem(
                            role: role,
                            content: [.file(filename: filename, data: content)],
                            model: model
                        ))
                    case let .image(url):
                        items.append(ConversationImportItem(
                            role: role,
                            content: [.image(url: url)],
                            model: model
                        ))
                    }
                }
                return items
            }

        return ImportedChatConversation(
            title: history.chat.title,
            timestamp: history.chat.timestamp / 1000,
            items: messages
        )
    }

    private static func normalizedRole(_ role: String) -> String {
        switch role.lowercased() {
        case "user", "assistant", "system":
            return role.lowercased()
        case "developer":
            return "system"
        case "tool":
            return "assistant"
        default:
            return "assistant"
        }
    }

    private static func normalizeModelID(_ model: String) -> String? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch trimmed {
        case "gpt-oss-120b", "nearai/gpt-oss-120b":
            return "openai/gpt-oss-120b"
        case "deepseek-v3.1":
            return "deepseek-ai/DeepSeek-V3.1"
        case "qwen3-30b-a3b-instruct-2507":
            return "Qwen/Qwen3-30B-A3B-Instruct-2507"
        default:
            return trimmed
        }
    }
}

struct ChatImportSummary: Equatable {
    let importedCount: Int
    let failedCount: Int
    let firstFailure: String?

    var bannerMessage: String {
        if importedCount > 0 {
            return failedCount == 0
                ? "Imported \(importedCount) chat\(importedCount == 1 ? "" : "s")."
                : "Imported \(importedCount); \(failedCount) failed."
        }
        return firstFailure ?? "Chat import failed."
    }
}

final class ChatImportService {
    private let conversationAPI: ConversationAPI

    init(conversationAPI: ConversationAPI) {
        self.conversationAPI = conversationAPI
    }

    func importChats(from url: URL, importedAt: Date = Date()) async throws -> ChatImportSummary {
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let fileSize = values.fileSize,
           fileSize > ChatImportLimits.maxImportBytes {
            throw ChatImportError.tooLarge("Import JSON must be 8 MB or smaller.")
        }

        let imports = try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            return try ChatImportBuilder.conversations(from: data)
        }.value

        guard !imports.isEmpty else {
            throw ChatImportError.empty
        }
        guard imports.count <= ChatImportLimits.maxConversationCount,
              imports.reduce(0, { $0 + $1.items.count }) <= ChatImportLimits.maxTotalItemCount else {
            throw ChatImportError.tooLarge("Import is too large to sync safely.")
        }

        var importedCount = 0
        var failures: [String] = []
        let importedAtMilliseconds = String(Int(importedAt.timeIntervalSince1970 * 1000))

        for importedConversation in imports {
            do {
                let title = Self.clippedTitle(importedConversation.title)
                let metadata = [
                    "imported_at": importedAtMilliseconds,
                    "initial_created_at": String(Int(importedConversation.timestamp ?? importedAt.timeIntervalSince1970))
                ]
                let conversation = try await conversationAPI.createConversation(title: title, metadata: metadata)
                for batch in importedConversation.batchedItems {
                    try await conversationAPI.addItemsToConversation(conversation.id, items: batch)
                }
                importedCount += 1
            } catch {
                failures.append("\(importedConversation.title): \(ErrorMessageMapper.displayFailureMessage(error.localizedDescription))")
            }
        }

        return ChatImportSummary(
            importedCount: importedCount,
            failedCount: failures.count,
            firstFailure: failures.first
        )
    }

    private static func clippedTitle(_ rawTitle: String, maxLength: Int = 64) -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "New conversation" }
        guard title.count > maxLength else { return title }

        let prefix = String(title.prefix(maxLength))
        if let lastSpace = prefix.lastIndex(where: { $0 == " " }), prefix.distance(from: prefix.startIndex, to: lastSpace) > 24 {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

}

enum ChatImportError: LocalizedError {
    case invalidFormat
    case empty
    case tooLarge(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            "Invalid import file. Use a NEAR Private Chat export or legacy Private Chat history file."
        case .empty:
            "No importable chats found in that JSON file."
        case let .tooLarge(message):
            message
        }
    }
}

private struct NativeExportPayload: Decodable {
    let conversation: NativeExportConversation?
    let messages: [NativeExportMessage]
}

private struct NativeExportConversation: Decodable {
    let title: String
    let createdAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case title
        case createdAt = "created_at"
    }
}

private struct NativeExportMessage: Decodable {
    let role: String
    let text: String
    let model: String?
}

private struct LegacyChatHistory: Decodable {
    let chat: LegacyChat
}

private struct LegacyChat: Decodable {
    let title: String
    let timestamp: TimeInterval
    let history: LegacyChatMessages
}

private struct LegacyChatMessages: Decodable {
    let messages: [String: LegacyChatMessage]
}

private struct LegacyChatMessage: Decodable {
    let role: String
    let content: String
    let files: [LegacyChatFile]?
    let model: String?
    let models: [String]?
}

private enum LegacyChatFile: Decodable {
    case file(filename: String, content: String)
    case image(url: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case file
        case url
    }

    private enum FileKeys: String, CodingKey {
        case filename
        case data
    }

    private enum DataKeys: String, CodingKey {
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "file":
            let file = try container.nestedContainer(keyedBy: FileKeys.self, forKey: .file)
            let filename = try file.decode(String.self, forKey: .filename)
            let data = try file.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
            let content = try data.decode(String.self, forKey: .content)
            self = .file(filename: filename, content: content)
        case "image":
            self = .image(url: try container.decode(String.self, forKey: .url))
        default:
            throw ChatImportError.invalidFormat
        }
    }
}
