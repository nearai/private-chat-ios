import Foundation

enum UserSetupStorage {
    static let completedKey = "userSetupProfileV1Completed"
    static let profileKey = "userSetupProfileV1Data"
    static let launchCardPendingKey = "userSetupLaunchCardPending"
    private static let scopedVersion = "v2"
    private static let protectedStoreDirectoryName = "SetupProfiles"
    private static let protectedProfileFilename = "profile.json"
    private static let protectedCompletionFilename = "completed.txt"
    private static let protectedLaunchCardPendingFilename = "launch-card-pending.txt"

    static func accountID(userID: String?, sessionID: String?, token: String?) -> String? {
        if let userID = userID?.trimmingCharacters(in: .whitespacesAndNewlines), !userID.isEmpty {
            return "user:\(userID)"
        }
        if let sessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines), !sessionID.isEmpty {
            return "session:\(sessionID)"
        }
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return "token:\(stableTokenDigest(token))"
        }
        return nil
    }

    static func isFallbackAccountID(_ accountID: String) -> Bool {
        accountID.hasPrefix("session:") || accountID.hasPrefix("token:")
    }

    static func isCompleted(for accountID: String, defaults: UserDefaults = .standard) -> Bool {
        if usesProtectedStorage(defaults) {
            if let data = readProtectedData(for: accountID, filename: protectedCompletionFilename),
               let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return value == "true"
            }
            return defaults.bool(forKey: scopedCompletedKey(for: accountID))
        }
        return defaults.bool(forKey: scopedCompletedKey(for: accountID))
    }

    static func load(for accountID: String, defaults: UserDefaults = .standard) -> UserSetupProfile? {
        if usesProtectedStorage(defaults),
           let data = readProtectedData(for: accountID, filename: protectedProfileFilename),
           let profile = try? JSONDecoder().decode(UserSetupProfile.self, from: data) {
            return profile
        }
        guard let data = defaults.data(forKey: scopedProfileKey(for: accountID)) else { return nil }
        return try? JSONDecoder().decode(UserSetupProfile.self, from: data)
    }

    static func save(_ profile: UserSetupProfile, for accountID: String, defaults: UserDefaults = .standard) {
        if usesProtectedStorage(defaults) {
            if let data = try? JSONEncoder().encode(profile.normalizedForDefaults) {
                writeProtectedData(data, for: accountID, filename: protectedProfileFilename)
            }
            writeProtectedData(Data("true".utf8), for: accountID, filename: protectedCompletionFilename)
            writeProtectedData(Data("true".utf8), for: accountID, filename: protectedLaunchCardPendingFilename)
            defaults.removeObject(forKey: scopedProfileKey(for: accountID))
            defaults.removeObject(forKey: scopedCompletedKey(for: accountID))
            defaults.removeObject(forKey: scopedLaunchCardPendingKey(for: accountID))
            return
        }
        if let data = try? JSONEncoder().encode(profile.normalizedForDefaults) {
            defaults.set(data, forKey: scopedProfileKey(for: accountID))
        }
        defaults.set(true, forKey: scopedCompletedKey(for: accountID))
        defaults.set(true, forKey: scopedLaunchCardPendingKey(for: accountID))
    }

    static func saveWithoutPendingLaunchCard(
        _ profile: UserSetupProfile,
        for accountID: String,
        defaults: UserDefaults = .standard
    ) {
        save(profile, for: accountID, defaults: defaults)
        clearPendingLaunchCard(for: accountID, defaults: defaults)
    }

    static func completeFirstRunPrivateChat(
        for accountID: String,
        defaults: UserDefaults = .standard
    ) -> UserSetupProfile {
        let profile = UserSetupProfile.defaults
        saveWithoutPendingLaunchCard(profile, for: accountID, defaults: defaults)
        return profile
    }

    static func completeFirstRunQuickStart(
        for accountID: String,
        preset: UserSetupStarterPreset,
        defaults: UserDefaults = .standard
    ) -> UserSetupProfile {
        let profile = preset.quickStartProfile
        saveWithoutPendingLaunchCard(profile, for: accountID, defaults: defaults)
        return profile
    }

    static func clearCompletion(for accountID: String, defaults: UserDefaults = .standard) {
        if usesProtectedStorage(defaults) {
            writeProtectedData(Data("false".utf8), for: accountID, filename: protectedCompletionFilename)
            defaults.removeObject(forKey: scopedCompletedKey(for: accountID))
            return
        }
        defaults.set(false, forKey: scopedCompletedKey(for: accountID))
    }

    static func hasPendingLaunchCard(for accountID: String, defaults: UserDefaults = .standard) -> Bool {
        if usesProtectedStorage(defaults) {
            if let data = readProtectedData(for: accountID, filename: protectedLaunchCardPendingFilename),
               let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() {
                return text == "true" || text == "1"
            }
            if defaults.object(forKey: scopedLaunchCardPendingKey(for: accountID)) != nil {
                return defaults.bool(forKey: scopedLaunchCardPendingKey(for: accountID))
            }
            return false
        }
        return defaults.bool(forKey: scopedLaunchCardPendingKey(for: accountID))
    }

    static func clearPendingLaunchCard(for accountID: String, defaults: UserDefaults = .standard) {
        if usesProtectedStorage(defaults) {
            writeProtectedData(Data("false".utf8), for: accountID, filename: protectedLaunchCardPendingFilename)
            defaults.removeObject(forKey: scopedLaunchCardPendingKey(for: accountID))
            return
        }
        defaults.set(false, forKey: scopedLaunchCardPendingKey(for: accountID))
    }

    static func presentationProfile(
        for accountID: String,
        currentDefaults: UserSetupProfile,
        defaults: UserDefaults = .standard
    ) -> UserSetupProfile {
        if let stored = load(for: accountID, defaults: defaults) {
            return stored
        }
        if isCompleted(for: accountID, defaults: defaults) {
            return currentDefaults.normalizedForDefaults
        }
        return .defaults
    }

    static func needsFirstRunSetup(for accountID: String, defaults: UserDefaults = .standard) -> Bool {
        load(for: accountID, defaults: defaults) == nil &&
            !isCompleted(for: accountID, defaults: defaults)
    }

    static func migrate(from oldAccountID: String, to newAccountID: String, defaults: UserDefaults = .standard) {
        guard oldAccountID != newAccountID,
              isFallbackAccountID(oldAccountID),
              !isCompleted(for: newAccountID, defaults: defaults) else { return }
        if let profile = load(for: oldAccountID, defaults: defaults) {
            save(profile, for: newAccountID, defaults: defaults)
        } else if isCompleted(for: oldAccountID, defaults: defaults) {
            if usesProtectedStorage(defaults) {
                writeProtectedData(Data("true".utf8), for: newAccountID, filename: protectedCompletionFilename)
            } else {
                defaults.set(true, forKey: scopedCompletedKey(for: newAccountID))
            }
        }
        if hasPendingLaunchCard(for: oldAccountID, defaults: defaults) {
            if usesProtectedStorage(defaults) {
                writeProtectedData(Data("true".utf8), for: newAccountID, filename: protectedLaunchCardPendingFilename)
            } else {
                defaults.set(true, forKey: scopedLaunchCardPendingKey(for: newAccountID))
            }
        }
        if usesProtectedStorage(defaults) {
            removeProtectedData(for: oldAccountID, filename: protectedProfileFilename)
            removeProtectedData(for: oldAccountID, filename: protectedCompletionFilename)
            removeProtectedData(for: oldAccountID, filename: protectedLaunchCardPendingFilename)
            defaults.removeObject(forKey: scopedProfileKey(for: oldAccountID))
            defaults.removeObject(forKey: scopedCompletedKey(for: oldAccountID))
            defaults.removeObject(forKey: scopedLaunchCardPendingKey(for: oldAccountID))
        } else {
            defaults.removeObject(forKey: scopedProfileKey(for: oldAccountID))
            defaults.removeObject(forKey: scopedCompletedKey(for: oldAccountID))
            defaults.removeObject(forKey: scopedLaunchCardPendingKey(for: oldAccountID))
        }
    }

    @available(*, deprecated, message: "Use account-scoped save(_:for:) instead.")
    static func save(_ profile: UserSetupProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    @available(*, deprecated, message: "Use account-scoped clearCompletion(for:) instead.")
    static func clearCompletion() {
        UserDefaults.standard.set(false, forKey: completedKey)
    }

    private static func scopedCompletedKey(for accountID: String) -> String {
        "\(completedKey).\(scopedVersion).\(normalizedAccountID(accountID))"
    }

    private static func scopedProfileKey(for accountID: String) -> String {
        "\(profileKey).\(scopedVersion).\(normalizedAccountID(accountID))"
    }

    private static func scopedLaunchCardPendingKey(for accountID: String) -> String {
        "\(launchCardPendingKey).\(scopedVersion).\(normalizedAccountID(accountID))"
    }

    private static func usesProtectedStorage(_ defaults: UserDefaults) -> Bool {
        defaults === UserDefaults.standard
    }

    private static func protectedDirectoryURL(for accountID: String) -> URL? {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return baseURL
            .appendingPathComponent("NEARPrivateChat", isDirectory: true)
            .appendingPathComponent(protectedStoreDirectoryName, isDirectory: true)
            .appendingPathComponent(normalizedAccountID(accountID), isDirectory: true)
    }

    private static func protectedFileURL(for accountID: String, filename: String) -> URL? {
        protectedDirectoryURL(for: accountID)?.appendingPathComponent(filename, isDirectory: false)
    }

    private static func readProtectedData(for accountID: String, filename: String) -> Data? {
        guard let url = protectedFileURL(for: accountID, filename: filename) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func writeProtectedData(_ data: Data, for accountID: String, filename: String) {
        guard let directoryURL = protectedDirectoryURL(for: accountID),
              let fileURL = protectedFileURL(for: accountID, filename: filename) else { return }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            var mutableDirectoryURL = directoryURL
            try? mutableDirectoryURL.setResourceValues(directoryValues)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            var fileValues = URLResourceValues()
            fileValues.isExcludedFromBackup = true
            var mutableFileURL = fileURL
            try? mutableFileURL.setResourceValues(fileValues)
        } catch {
            return
        }
    }

    private static func removeProtectedData(for accountID: String, filename: String) {
        guard let url = protectedFileURL(for: accountID, filename: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func normalizedAccountID(_ accountID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = accountID.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar).description : "_"
        }
        return String(scalars.joined()).prefix(96).description
    }

    private static func stableTokenDigest(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
