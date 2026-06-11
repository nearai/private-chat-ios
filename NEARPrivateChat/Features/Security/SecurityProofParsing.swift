import Foundation

extension SecurityView {
    func gatewaySigningAddresses(_ snapshot: AttestationSnapshot) -> [(label: String, value: String)] {
        var addresses: [(label: String, value: String)] = []
        if let chatAddress = cleanedIdentifier(snapshot.chatGatewayAddress) {
            addresses.append(("Chat", chatAddress))
        }
        if let cloudAddress = cleanedIdentifier(snapshot.cloudGatewayAddress) {
            addresses.append(("Cloud", cloudAddress))
        }
        return addresses
    }

    func selectedModelHashStatus(in snapshot: AttestationSnapshot) -> String {
        if let hash = selectedModelHashPreview(in: snapshot, requireSelectedModelMatch: true) {
            return "reported model hash \(shortenedIdentifier(hash, prefix: 14, suffix: 10))"
        }
        if snapshot.modelAttestationCount > 0 {
            return "model hash not exposed in parsed evidence"
        }
        return "no model hash evidence in this report"
    }

    func selectedModelHashPreview(in snapshot: AttestationSnapshot, requireSelectedModelMatch: Bool = false) -> String? {
        guard let data = snapshot.prettyJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let attestations = value(at: ["model_attestations"], in: object) as? [Any] else {
            return nil
        }

        let attestationDictionaries = attestations.compactMap { $0 as? [String: Any] }
        let selectedModel = AttestationEvidence.normalizedModelID(selectedModelID)

        if let matchingAttestation = attestationDictionaries.first(where: { modelAttestation($0, matches: selectedModel) }),
           let hash = firstModelHash(in: matchingAttestation) {
            return hash
        }
        guard !requireSelectedModelMatch else { return nil }
        if attestationDictionaries.count == 1,
           let hash = firstModelHash(in: attestationDictionaries[0]) {
            return hash
        }
        return nil
    }

    func value(at path: [String], in object: Any) -> Any? {
        var current = object
        for key in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[key] else {
                return nil
            }
            current = next
        }
        return current
    }

    func modelAttestation(_ dictionary: [String: Any], matches normalizedModelID: String) -> Bool {
        func walk(_ value: Any) -> Bool {
            if let dictionary = value as? [String: Any] {
                for key in ["model", "model_id", "modelId", "id", "name"] {
                    if let modelID = dictionary[key] as? String,
                       AttestationEvidence.normalizedModelID(modelID) == normalizedModelID {
                        return true
                    }
                }
                return dictionary.values.contains(where: walk)
            }
            if let array = value as? [Any] {
                return array.contains(where: walk)
            }
            return false
        }
        return walk(dictionary)
    }

    func firstModelHash(in dictionary: [String: Any]) -> String? {
        func walk(_ value: Any) -> String? {
            if let dictionary = value as? [String: Any] {
                for (key, child) in dictionary where isModelHashKey(key) {
                    if let string = child as? String,
                       let cleaned = cleanedIdentifier(string) {
                        return cleaned
                    }
                }
                for child in dictionary.values {
                    if let hash = walk(child) {
                        return hash
                    }
                }
            } else if let array = value as? [Any] {
                for child in array {
                    if let hash = walk(child) {
                        return hash
                    }
                }
            }
            return nil
        }
        return walk(dictionary)
    }

    func isModelHashKey(_ key: String) -> Bool {
        let normalized = key
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        return [
            "hash",
            "digest",
            "sha256",
            "modelhash",
            "modeldigest",
            "weightshash",
            "weightsdigest"
        ].contains(normalized)
    }

    func cleanedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func shortenedIdentifier(_ value: String, prefix: Int = 12, suffix: Int = 8) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > prefix + suffix + 3 else {
            return trimmed
        }
        return "\(trimmed.prefix(prefix))...\(trimmed.suffix(suffix))"
    }
}
