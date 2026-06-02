import Foundation

struct ProjectPersistence {
    static let legacyDefaultsKey = "chatProjects"
    static let cacheFilename = "projects.json"
    private static let selectedProjectDefaultsKey = "selectedProjectID"

    let accountID: String
    var defaults: UserDefaults = .standard
    var fileManager: FileManager = .default

    init(accountID: String, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.accountID = accountID
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func loadProjects() -> [ChatProject] {
        guard let data = fileCache.data(filename: Self.cacheFilename, legacyDefaultsKey: Self.legacyDefaultsKey),
              let projects = try? JSONDecoder().decode([ChatProject].self, from: data) else {
            return []
        }
        return projects.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func saveProjects(_ projects: [ChatProject]) -> Bool {
        guard let data = try? JSONEncoder().encode(projects) else { return false }
        return fileCache.write(data, filename: Self.cacheFilename, legacyDefaultsKey: Self.legacyDefaultsKey)
    }

    func loadSelectedProjectID() -> String? {
        defaults.string(forKey: selectedProjectDefaultsScopedKey)
    }

    func saveSelectedProjectID(_ selectedProjectID: String?) {
        if let selectedProjectID {
            defaults.set(selectedProjectID, forKey: selectedProjectDefaultsScopedKey)
        } else {
            defaults.removeObject(forKey: selectedProjectDefaultsScopedKey)
        }
    }

    func selectedProjectDefaultsKey() -> String {
        selectedProjectDefaultsScopedKey
    }

    private var selectedProjectDefaultsScopedKey: String {
        AccountStorageScope.scopedDefaultsKey(Self.selectedProjectDefaultsKey, accountID: accountID)
    }

    private var fileCache: FileCache {
        FileCache(accountID: accountID, defaults: defaults, fileManager: fileManager)
    }
}
