import Foundation

struct FileCache {
    let accountID: String
    var defaults: UserDefaults = .standard
    var fileManager: FileManager = .default

    init(accountID: String, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.accountID = accountID
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func data(filename: String, legacyDefaultsKey: String) -> Data? {
        let url = fileURL(filename: filename)
        if let data = try? Data(contentsOf: url) {
            return data
        }
        guard accountID == AccountStorageScope.signedOutAccountID else {
            return nil
        }
        guard let legacyData = defaults.data(forKey: legacyDefaultsKey) else {
            return nil
        }
        return write(legacyData, filename: filename, legacyDefaultsKey: legacyDefaultsKey) ? legacyData : nil
    }

    @discardableResult
    func write(_ data: Data, filename: String, legacyDefaultsKey: String) -> Bool {
        var url = fileURL(filename: filename)
        var directoryURL = url.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            try? directoryURL.setResourceValues(directoryValues)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var fileValues = URLResourceValues()
            fileValues.isExcludedFromBackup = true
            try? url.setResourceValues(fileValues)
            #if os(iOS)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
            #endif
            if accountID == AccountStorageScope.signedOutAccountID {
                defaults.removeObject(forKey: legacyDefaultsKey)
            }
            return true
        } catch {
            #if DEBUG
            assertionFailure("Secure file-backed cache write failed for \(filename): \(error.localizedDescription)")
            #endif
            return false
        }
    }

    func loadProtectedText(filename: String, legacyDefaultsKey: String) -> String {
        if let data = data(filename: filename, legacyDefaultsKey: legacyDefaultsKey),
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        guard let legacyValue = defaults.string(forKey: legacyDefaultsKey) else {
            return ""
        }
        saveProtectedText(legacyValue, filename: filename, legacyDefaultsKey: legacyDefaultsKey)
        return legacyValue
    }

    @discardableResult
    func saveProtectedText(_ value: String, filename: String, legacyDefaultsKey: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remove(filename: filename, legacyDefaultsKey: legacyDefaultsKey)
            return true
        }
        guard let data = value.data(using: .utf8),
              write(data, filename: filename, legacyDefaultsKey: legacyDefaultsKey) else {
            return false
        }
        defaults.removeObject(forKey: legacyDefaultsKey)
        return true
    }

    func remove(filename: String, legacyDefaultsKey: String) {
        try? fileManager.removeItem(at: fileURL(filename: filename))
        defaults.removeObject(forKey: legacyDefaultsKey)
    }

    func fileURL(filename: String) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("NEARPrivateChat", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(AccountStorageScope.normalizedStorageScope(accountID), isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }
}
