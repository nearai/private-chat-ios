import Foundation
import Security

enum KeychainStore {
    private static let service = "ai.near.privatechat.ios"
    private static let simulatorFallbackPrefix = "keychainFallback."
    private static let simulatorFallbackTTL: TimeInterval = 24 * 60 * 60

    static func save<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            #if targetEnvironment(simulator)
            saveSimulatorFallbackData(data, account: account)
            #endif
            return
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            #if targetEnvironment(simulator)
            saveSimulatorFallbackData(data, account: account)
            return
            #else
            throw APIError.status(Int(addStatus), "Unable to save credentials.")
            #endif
        }
        #if targetEnvironment(simulator)
        saveSimulatorFallbackData(data, account: account)
        #endif
    }

    static func read<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            #if targetEnvironment(simulator)
            if let fallbackValue = try readSimulatorFallback(type, account: account) {
                return fallbackValue
            }
            #endif
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            #if targetEnvironment(simulator)
            if let fallbackValue = try readSimulatorFallback(type, account: account) {
                return fallbackValue
            }
            #endif
            throw APIError.status(Int(status), "Unable to read credentials.")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            #if targetEnvironment(simulator)
            if let fallbackValue = try readSimulatorFallback(type, account: account) {
                return fallbackValue
            }
            #endif
            throw error
        }
    }

    static func readString(account: String) throws -> String? {
        do {
            if let keychainValue = try read(String.self, account: account)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !keychainValue.isEmpty {
                return keychainValue
            }
        } catch {
            #if !targetEnvironment(simulator)
            throw error
            #endif
        }

        #if targetEnvironment(simulator)
        if let fallbackValue = try readSimulatorFallback(String.self, account: account)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fallbackValue.isEmpty {
            return fallbackValue
        }
        #endif
        return nil
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        #if targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: fallbackKey(for: account))
        #endif
    }

    private static func fallbackKey(for account: String) -> String {
        "\(simulatorFallbackPrefix)\(service).\(account)"
    }

    #if targetEnvironment(simulator)
    private struct SimulatorFallbackEnvelope: Codable {
        var data: Data
        var expiresAt: Date
    }

    private static func saveSimulatorFallbackData(_ data: Data, account: String) {
        let envelope = SimulatorFallbackEnvelope(
            data: data,
            expiresAt: Date().addingTimeInterval(simulatorFallbackTTL)
        )
        if let encoded = try? JSONEncoder().encode(envelope) {
            UserDefaults.standard.set(encoded, forKey: fallbackKey(for: account))
        }
    }

    private static func readSimulatorFallback<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        let key = fallbackKey(for: account)
        if let data = UserDefaults.standard.data(forKey: key) {
            let decoder = JSONDecoder()
            if let envelope = try? decoder.decode(SimulatorFallbackEnvelope.self, from: data) {
                guard envelope.expiresAt > Date() else {
                    UserDefaults.standard.removeObject(forKey: key)
                    return nil
                }
                return try decoder.decode(type, from: envelope.data)
            }

            do {
                let legacyValue = try decoder.decode(type, from: data)
                saveSimulatorFallbackData(data, account: account)
                return legacyValue
            } catch {
                if type == String.self, let stringValue = decodeSimulatorFallbackString(from: data) {
                    if let encoded = try? JSONEncoder().encode(stringValue) {
                        saveSimulatorFallbackData(encoded, account: account)
                    }
                    return stringValue as? T
                }
                throw error
            }
        }

        if type == String.self,
           let stringValue = UserDefaults.standard.string(forKey: key),
           !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let encoded = try? JSONEncoder().encode(stringValue) {
                saveSimulatorFallbackData(encoded, account: account)
            }
            return stringValue as? T
        }
        return nil
    }

    private static func decodeSimulatorFallbackString(from data: Data) -> String? {
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(String.self, from: data),
           !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return decoded
        }

        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        if let decodedData = Data(base64Encoded: raw),
           let decoded = try? decoder.decode(String.self, from: decodedData),
           !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return decoded
        }

        if raw.hasPrefix("\""), raw.hasSuffix("\""),
           let quotedData = raw.data(using: .utf8),
           let decoded = try? decoder.decode(String.self, from: quotedData),
           !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return decoded
        }

        return raw
    }
    #endif
}
