import Foundation

struct DraftPersistence {
    struct DraftState: Codable, Equatable {
        var text: String
        var attachments: [ChatAttachment]
        var pendingLargePasteTexts: [String: String]
        var pendingDocumentTexts: [String: String]

        init(
            text: String,
            attachments: [ChatAttachment],
            pendingLargePasteTexts: [String: String],
            pendingDocumentTexts: [String: String] = [:]
        ) {
            self.text = text
            self.attachments = attachments
            self.pendingLargePasteTexts = pendingLargePasteTexts
            self.pendingDocumentTexts = pendingDocumentTexts
        }

        private enum CodingKeys: String, CodingKey {
            case text
            case attachments
            case pendingLargePasteTexts
            case pendingDocumentTexts
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            attachments = try container.decode([ChatAttachment].self, forKey: .attachments)
            pendingLargePasteTexts = try container.decodeIfPresent([String: String].self, forKey: .pendingLargePasteTexts) ?? [:]
            pendingDocumentTexts = try container.decodeIfPresent([String: String].self, forKey: .pendingDocumentTexts) ?? [:]
        }

        var isEmpty: Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
        }

        var sanitized: DraftState {
            let attachmentIDs = Set(attachments.map(\.id))
            let filteredLargePastes = pendingLargePasteTexts.filter { attachmentIDs.contains($0.key) }
            let filteredDocumentTexts = pendingDocumentTexts.filter { attachmentIDs.contains($0.key) }
            let filteredAttachments = attachments.filter { attachment in
                if attachment.isLocalPendingSharedFile {
                    return filteredDocumentTexts[attachment.id] != nil
                }
                return !attachment.isLocalPendingText || filteredLargePastes[attachment.id] != nil
            }
            return DraftState(
                text: text,
                attachments: filteredAttachments,
                pendingLargePasteTexts: filteredLargePastes,
                pendingDocumentTexts: filteredDocumentTexts
            )
        }
    }

    private static let draftDefaultsKeyPrefix = "draftByScope"
    private static let draftStateDefaultsKeyPrefix = "draftStateByScope"
    private static let draftCacheDirectoryName = "drafts"
    private static let draftStateCacheDirectoryName = "draft-state"

    let accountID: String
    var defaults: UserDefaults = .standard
    var fileManager: FileManager = .default

    init(accountID: String, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.accountID = accountID
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func load(scopeID: String) -> DraftState {
        if let data = fileCache.data(
            filename: draftStateCacheFilename(for: scopeID),
            legacyDefaultsKey: draftStateDefaultsKey(for: scopeID)
        ),
           let state = try? JSONDecoder().decode(DraftState.self, from: data) {
            return state.sanitized
        }

        return DraftState(
            text: fileCache.loadProtectedText(
                filename: draftCacheFilename(for: scopeID),
                legacyDefaultsKey: draftDefaultsKey(for: scopeID)
            ),
            attachments: [],
            pendingLargePasteTexts: [:],
            pendingDocumentTexts: [:]
        )
    }

    @discardableResult
    func save(_ state: DraftState, scopeID: String) -> Bool {
        let state = state.sanitized
        if state.isEmpty {
            remove(scopeID: scopeID)
            return true
        }
        guard let data = try? JSONEncoder().encode(state),
              fileCache.write(
                  data,
                  filename: draftStateCacheFilename(for: scopeID),
                  legacyDefaultsKey: draftStateDefaultsKey(for: scopeID)
              ) else {
            return false
        }
        fileCache.remove(
            filename: draftCacheFilename(for: scopeID),
            legacyDefaultsKey: draftDefaultsKey(for: scopeID)
        )
        defaults.removeObject(forKey: draftStateDefaultsKey(for: scopeID))
        return true
    }

    func remove(scopeID: String) {
        fileCache.remove(
            filename: draftCacheFilename(for: scopeID),
            legacyDefaultsKey: draftDefaultsKey(for: scopeID)
        )
        fileCache.remove(
            filename: draftStateCacheFilename(for: scopeID),
            legacyDefaultsKey: draftStateDefaultsKey(for: scopeID)
        )
    }

    func draftDefaultsKey(for scopeID: String) -> String {
        scopedDefaultsKey("\(Self.draftDefaultsKeyPrefix).\(scopeID)")
    }

    func draftStateDefaultsKey(for scopeID: String) -> String {
        scopedDefaultsKey("\(Self.draftStateDefaultsKeyPrefix).\(scopeID)")
    }

    func draftCacheFilename(for scopeID: String) -> String {
        "\(Self.draftCacheDirectoryName)/\(AccountStorageScope.safeCacheFilenameComponent(scopeID)).txt"
    }

    func draftStateCacheFilename(for scopeID: String) -> String {
        "\(Self.draftStateCacheDirectoryName)/\(AccountStorageScope.safeCacheFilenameComponent(scopeID)).json"
    }

    private var fileCache: FileCache {
        FileCache(accountID: accountID, defaults: defaults, fileManager: fileManager)
    }

    private func scopedDefaultsKey(_ key: String) -> String {
        AccountStorageScope.scopedDefaultsKey(key, accountID: accountID)
    }
}
