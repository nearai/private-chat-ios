import Foundation

struct SettingsPersistence {
    private static let preferredDefaultModelDefaultsKey = "preferredDefaultModelID"
    private static let selectedModelDefaultsKey = "selectedModel"
    private static let councilModelDefaultsKey = "councilModelIDs"
    private static let pinnedModelDefaultsKey = "pinnedModelIDs"
    private static let selectedProjectDefaultsKey = "selectedProjectID"
    private static let webSearchDefaultsKey = "webSearchEnabled"
    private static let sourceModeDefaultsKey = "sourceMode"
    private static let researchModeDefaultsKey = "researchModeEnabled"
    private static let systemPromptDefaultsKey = "systemPrompt"
    private static let systemPromptCacheFilename = "system-prompt.txt"
    private static let soulMarkdownDefaultsKey = "soulMarkdown"
    private static let soulMarkdownCacheFilename = "soul.md"
    private static let largeTextAsFileDefaultsKey = "largeTextAsFileEnabled"
    private static let passiveMemoryDefaultsKey = "passiveMemoryEnabled"
    private static let keepDocumentsOnDeviceDefaultsKey = "keepDocumentsOnDevice"
    private static let advancedModelParamsDefaultsKey = "advancedModelParams"
    private static let ironclawSettingsDefaultsKey = "ironclawSettings"
    private static let ironclawTokenKeychainAccount = "ironclaw.authToken"
    private static let nearCloudAPIKeychainAccount = "nearCloud.apiKey"

    let accountID: String
    var defaults: UserDefaults = .standard
    var fileManager: FileManager = .default

    init(accountID: String, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.accountID = accountID
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func scopedDefaultsKey(_ key: String) -> String {
        AccountStorageScope.scopedDefaultsKey(key, accountID: accountID)
    }

    func scopedKeychainAccount(_ account: String) -> String {
        scopedDefaultsKey(account)
    }

    func loadPreferredDefaultModelID() -> String? {
        defaults.string(forKey: scopedDefaultsKey(Self.preferredDefaultModelDefaultsKey))
    }

    func savePreferredDefaultModelID(_ modelID: String?) {
        let key = scopedDefaultsKey(Self.preferredDefaultModelDefaultsKey)
        if let modelID, !modelID.isEmpty {
            defaults.set(modelID, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func loadSelectedModelID() -> String? {
        defaults.string(forKey: scopedDefaultsKey(Self.selectedModelDefaultsKey))
    }

    func saveSelectedModelID(_ modelID: String) {
        defaults.set(modelID, forKey: scopedDefaultsKey(Self.selectedModelDefaultsKey))
    }

    func loadCouncilModelIDs() -> [String] {
        defaults.stringArray(forKey: scopedDefaultsKey(Self.councilModelDefaultsKey)) ?? []
    }

    func saveCouncilModelIDs(_ modelIDs: [String]) {
        defaults.set(modelIDs, forKey: scopedDefaultsKey(Self.councilModelDefaultsKey))
    }

    func loadPinnedModelIDs(maxCount: Int) -> [String] {
        Array(Self.uniqueStrings(defaults.stringArray(forKey: scopedDefaultsKey(Self.pinnedModelDefaultsKey)) ?? []).prefix(maxCount))
    }

    func savePinnedModelIDs(_ modelIDs: [String]) {
        defaults.set(modelIDs, forKey: scopedDefaultsKey(Self.pinnedModelDefaultsKey))
    }

    func loadWebSearchEnabled(default defaultValue: Bool) -> Bool {
        loadOptionalBool(key: Self.webSearchDefaultsKey) ?? defaultValue
    }

    func saveWebSearchEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: scopedDefaultsKey(Self.webSearchDefaultsKey))
    }

    func loadSourceMode(default defaultValue: ChatSourceMode) -> ChatSourceMode {
        guard let rawValue = defaults.string(forKey: scopedDefaultsKey(Self.sourceModeDefaultsKey)),
              let sourceMode = ChatSourceMode(rawValue: rawValue) else {
            return defaultValue
        }
        return sourceMode
    }

    func saveSourceMode(_ sourceMode: ChatSourceMode) {
        defaults.set(sourceMode.rawValue, forKey: scopedDefaultsKey(Self.sourceModeDefaultsKey))
    }

    func loadResearchModeEnabled(default defaultValue: Bool = false) -> Bool {
        loadOptionalBool(key: Self.researchModeDefaultsKey) ?? defaultValue
    }

    func saveResearchModeEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: scopedDefaultsKey(Self.researchModeDefaultsKey))
    }

    func loadLargeTextAsFileEnabled(default defaultValue: Bool) -> Bool {
        loadOptionalBool(key: Self.largeTextAsFileDefaultsKey) ?? defaultValue
    }

    func saveLargeTextAsFileEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: scopedDefaultsKey(Self.largeTextAsFileDefaultsKey))
    }

    func loadPassiveMemoryEnabled(default defaultValue: Bool = true) -> Bool {
        defaults.object(forKey: Self.passiveMemoryDefaultsKey) as? Bool ?? defaultValue
    }

    func savePassiveMemoryEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Self.passiveMemoryDefaultsKey)
    }

    func loadKeepDocumentsOnDevice(default defaultValue: Bool = false) -> Bool {
        guard defaults.object(forKey: Self.keepDocumentsOnDeviceDefaultsKey) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: Self.keepDocumentsOnDeviceDefaultsKey)
    }

    func saveKeepDocumentsOnDevice(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Self.keepDocumentsOnDeviceDefaultsKey)
    }

    func loadAdvancedModelParams() -> AdvancedModelParams {
        guard let data = defaults.data(forKey: scopedDefaultsKey(Self.advancedModelParamsDefaultsKey)),
              let params = try? JSONDecoder().decode(AdvancedModelParams.self, from: data) else {
            return .defaults
        }
        return params.sanitized
    }

    func saveAdvancedModelParams(_ params: AdvancedModelParams) {
        guard let data = try? JSONEncoder().encode(params.sanitized) else { return }
        defaults.set(data, forKey: scopedDefaultsKey(Self.advancedModelParamsDefaultsKey))
    }

    func loadIronclawSettings() -> IronclawSettings {
        guard let data = defaults.data(forKey: scopedDefaultsKey(Self.ironclawSettingsDefaultsKey)),
              let settings = try? JSONDecoder().decode(IronclawSettings.self, from: data) else {
            return .default
        }
        let sanitized = settings.standalonePhoneSanitized
        if sanitized != settings {
            saveIronclawSettings(sanitized)
        }
        return sanitized
    }

    func saveIronclawSettings(_ settings: IronclawSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: scopedDefaultsKey(Self.ironclawSettingsDefaultsKey))
    }

    func loadSystemPrompt() -> String {
        fileCache.loadProtectedText(
            filename: Self.systemPromptCacheFilename,
            legacyDefaultsKey: scopedDefaultsKey(Self.systemPromptDefaultsKey)
        )
    }

    @discardableResult
    func saveSystemPrompt(_ value: String) -> Bool {
        fileCache.saveProtectedText(
            value,
            filename: Self.systemPromptCacheFilename,
            legacyDefaultsKey: scopedDefaultsKey(Self.systemPromptDefaultsKey)
        )
    }

    func loadSoulMarkdown() -> String {
        fileCache.loadProtectedText(
            filename: Self.soulMarkdownCacheFilename,
            legacyDefaultsKey: scopedDefaultsKey(Self.soulMarkdownDefaultsKey)
        )
    }

    @discardableResult
    func saveSoulMarkdown(_ value: String) -> Bool {
        fileCache.saveProtectedText(
            value,
            filename: Self.soulMarkdownCacheFilename,
            legacyDefaultsKey: scopedDefaultsKey(Self.soulMarkdownDefaultsKey)
        )
    }

    func loadIronclawAuthToken() -> String? {
        (try? KeychainStore.readString(account: scopedKeychainAccount(Self.ironclawTokenKeychainAccount))) ?? nil
    }

    func saveIronclawAuthToken(_ token: String) throws {
        try KeychainStore.save(token, account: scopedKeychainAccount(Self.ironclawTokenKeychainAccount))
    }

    func deleteIronclawAuthToken() {
        KeychainStore.delete(account: scopedKeychainAccount(Self.ironclawTokenKeychainAccount))
    }

    func loadNearCloudAPIKey() -> String? {
        (try? KeychainStore.readString(account: scopedKeychainAccount(Self.nearCloudAPIKeychainAccount))) ?? nil
    }

    func saveNearCloudAPIKey(_ apiKey: String) throws {
        try KeychainStore.save(apiKey, account: scopedKeychainAccount(Self.nearCloudAPIKeychainAccount))
    }

    func deleteNearCloudAPIKey() {
        KeychainStore.delete(account: scopedKeychainAccount(Self.nearCloudAPIKeychainAccount))
    }

    static func shouldMigrateStorage(from oldAccountID: String, to newAccountID: String) -> Bool {
        oldAccountID != newAccountID &&
            UserSetupStorage.isFallbackAccountID(oldAccountID) &&
            !UserSetupStorage.isFallbackAccountID(newAccountID) &&
            newAccountID != AccountStorageScope.signedOutAccountID
    }

    static func migrateAccountScopedStorage(from oldAccountID: String, to newAccountID: String) {
        let defaultsKeys = [
            selectedModelDefaultsKey,
            councilModelDefaultsKey,
            pinnedModelDefaultsKey,
            selectedProjectDefaultsKey,
            webSearchDefaultsKey,
            sourceModeDefaultsKey,
            researchModeDefaultsKey,
            systemPromptDefaultsKey,
            soulMarkdownDefaultsKey,
            largeTextAsFileDefaultsKey,
            advancedModelParamsDefaultsKey,
            ironclawSettingsDefaultsKey
        ]
        for key in defaultsKeys {
            let oldKey = AccountStorageScope.scopedDefaultsKey(key, accountID: oldAccountID)
            let newKey = AccountStorageScope.scopedDefaultsKey(key, accountID: newAccountID)
            if UserDefaults.standard.object(forKey: newKey) == nil,
               let object = UserDefaults.standard.object(forKey: oldKey) {
                UserDefaults.standard.set(object, forKey: newKey)
            }
            UserDefaults.standard.removeObject(forKey: oldKey)
        }

        let fileCaches: [(filename: String, legacyKey: String)] = [
            (systemPromptCacheFilename, systemPromptDefaultsKey),
            (soulMarkdownCacheFilename, soulMarkdownDefaultsKey),
            (ConversationCache.cacheFilename, ConversationCache.legacyDefaultsKey),
            (ProjectPersistence.cacheFilename, ProjectPersistence.legacyDefaultsKey),
            (MessageCache.cacheFilename, MessageCache.legacyDefaultsKey),
            (AgentThreadPersistence.cacheFilename, AgentThreadPersistence.legacyDefaultsKey)
        ]
        for cache in fileCaches {
            let newCache = FileCache(accountID: newAccountID)
            let oldCache = FileCache(accountID: oldAccountID)
            if newCache.data(filename: cache.filename, legacyDefaultsKey: cache.legacyKey) == nil,
               let oldData = oldCache.data(filename: cache.filename, legacyDefaultsKey: cache.legacyKey) {
                _ = newCache.write(oldData, filename: cache.filename, legacyDefaultsKey: cache.legacyKey)
            }
            try? FileManager.default.removeItem(at: oldCache.fileURL(filename: cache.filename))
        }

        let keychainAccounts = [
            ironclawTokenKeychainAccount,
            nearCloudAPIKeychainAccount
        ]
        for account in keychainAccounts {
            let oldAccount = AccountStorageScope.scopedDefaultsKey(account, accountID: oldAccountID)
            let newAccount = AccountStorageScope.scopedDefaultsKey(account, accountID: newAccountID)
            if (try? KeychainStore.readString(account: newAccount)) == nil,
               let value = try? KeychainStore.readString(account: oldAccount) {
                try? KeychainStore.save(value, account: newAccount)
            }
            KeychainStore.delete(account: oldAccount)
        }
    }

    private var fileCache: FileCache {
        FileCache(accountID: accountID, defaults: defaults, fileManager: fileManager)
    }

    private func loadOptionalBool(key: String) -> Bool? {
        guard defaults.object(forKey: scopedDefaultsKey(key)) != nil else { return nil }
        return defaults.bool(forKey: scopedDefaultsKey(key))
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else {
                continue
            }
            output.append(trimmed)
        }
        return output
    }
}
