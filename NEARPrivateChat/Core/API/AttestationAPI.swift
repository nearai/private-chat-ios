import Foundation

protocol AttestationAPI: AnyObject {
    func fetchAttestationReport(nonce: String, signingAlgorithm: String, model: String?) async throws -> AttestationSnapshot
}

final class PrivateChatAttestationAPI: AttestationAPI {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchAttestationReport(
        nonce: String,
        signingAlgorithm: String = "ecdsa",
        model: String? = nil
    ) async throws -> AttestationSnapshot {
        var query = [
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "signing_algo", value: signingAlgorithm)
        ]
        if let model, !model.isEmpty {
            query.append(URLQueryItem(name: "model", value: model))
        }
        var components = URLComponents()
        components.path = "/v1/attestation/report"
        components.queryItems = query
        guard let path = components.string else { throw APIError.invalidURL }

        let request = try client.makeRequest(path: path, method: "GET", body: nil, authenticated: false)
        let data = try await client.performRaw(request)
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
        let prettyJSON = String(data: prettyData, encoding: .utf8) ?? String(data: data, encoding: .utf8) ?? ""

        let coveredModelIDs = Self.extractModelIDs(from: jsonObject)
        let attestedAt = Self.extractAttestationDate(from: jsonObject) ?? Date()
        return AttestationSnapshot(
            nonce: nonce,
            signingAlgorithm: signingAlgorithm,
            model: coveredModelIDs.first,
            coveredModelIDs: coveredModelIDs,
            fetchedAt: attestedAt,
            chatGatewayAddress: Self.extractString(
                from: jsonObject,
                path: ["chat_api_gateway_attestation", "signing_address"]
            ),
            cloudGatewayAddress: Self.extractString(
                from: jsonObject,
                path: ["cloud_api_gateway_attestation", "signing_address"]
            ),
            modelAttestationCount: Self.extractArrayCount(from: jsonObject, path: ["model_attestations"]),
            prettyJSON: prettyJSON
        )
    }

    private static func extractString(from object: Any, path: [String]) -> String? {
        var current = object
        for key in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[key] else {
                return nil
            }
            current = next
        }
        return current as? String
    }

    private static func extractArrayCount(from object: Any, path: [String]) -> Int {
        var current = object
        for key in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[key] else {
                return 0
            }
            current = next
        }
        return (current as? [Any])?.count ?? 0
    }

    private static func extractModelIDs(from object: Any) -> [String] {
        var ids: [String] = []
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for key in ["model", "model_id", "modelId", "id", "name"] {
                    if let modelID = dictionary[key] as? String,
                       looksLikeModelID(modelID) {
                        ids.append(modelID)
                    }
                }
                dictionary.values.forEach(walk)
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(object)
        var seen = Set<String>()
        return ids.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func looksLikeModelID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 160 else { return false }
        return trimmed.contains("/") || trimmed.localizedCaseInsensitiveContains("glm") || trimmed.localizedCaseInsensitiveContains("qwen")
    }

    private static func extractAttestationDate(from object: Any) -> Date? {
        let formatter = ISO8601DateFormatter()
        var candidates: [Any] = []
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for key in ["attested_at", "generated_at", "created_at", "timestamp", "time"] {
                    if let candidate = dictionary[key] {
                        candidates.append(candidate)
                    }
                }
                dictionary.values.forEach(walk)
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(object)
        for candidate in candidates {
            if let string = candidate as? String,
               let date = formatter.date(from: string) {
                return date
            }
            if let number = candidate as? TimeInterval, number > 1_000_000_000 {
                return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1_000 : number)
            }
        }
        return nil
    }
}
