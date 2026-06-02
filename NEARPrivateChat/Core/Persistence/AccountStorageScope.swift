import Foundation

struct AccountStorageScope: Equatable {
    static let signedOutAccountID = "signed-out"

    let accountID: String

    init(accountID: String?) {
        self.accountID = Self.resolvedAccountID(for: accountID)
    }

    init(resolvedAccountID: String) {
        self.accountID = resolvedAccountID
    }

    var normalizedID: String {
        Self.normalizedStorageScope(accountID)
    }

    func scopedDefaultsKey(_ key: String) -> String {
        Self.scopedDefaultsKey(key, accountID: accountID)
    }

    static func resolvedAccountID(for accountID: String?) -> String {
        let trimmed = accountID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? signedOutAccountID : trimmed
    }

    static func transientAccountID(prefix: String = "transient") -> String {
        "\(prefix)-\(UUID().uuidString)"
    }

    static func scopedDefaultsKey(_ key: String, accountID: String) -> String {
        "\(key).account.\(normalizedStorageScope(accountID))"
    }

    static func normalizedStorageScope(_ accountID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = accountID.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let normalized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return normalized.isEmpty ? signedOutAccountID : normalized
    }

    static func safeCacheFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        var normalized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        if normalized.count > 96 {
            normalized = "\(normalized.prefix(72))-\(stableShortDigest(value))"
        }
        return normalized.isEmpty ? "home" : normalized
    }

    private static func stableShortDigest(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
