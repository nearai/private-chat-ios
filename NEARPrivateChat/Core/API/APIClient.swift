import Foundation

final class APIClient {
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    static let streamTimeout: TimeInterval = 240
    static let maxUploadBytes = 10 * 1024 * 1024
    static let maxFilePreviewBytes = 96 * 1024

    var configuration: AppConfiguration
    var authToken: String?

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    func request<T: Decodable, B: Encodable>(
        _ path: String,
        method: String,
        body: B,
        authenticated: Bool
    ) async throws -> T {
        let bodyData = try encoder.encode(body)
        let request = try makeRequest(path: path, method: method, body: bodyData, authenticated: authenticated)
        return try await perform(request)
    }

    func request<T: Decodable>(
        _ path: String,
        method: String,
        authenticated: Bool
    ) async throws -> T {
        let request = try makeRequest(path: path, method: method, body: nil, authenticated: authenticated)
        return try await perform(request)
    }

    func readableRequest<T: Decodable>(_ path: String) async throws -> T {
        let trimmedToken = authToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedToken.isEmpty else {
            return try await request(path, method: "GET", authenticated: false)
        }

        do {
            return try await request(path, method: "GET", authenticated: true)
        } catch APIError.status(let code, _) where code == 401 || code == 403 {
            return try await request(path, method: "GET", authenticated: false)
        }
    }

    func makeRequest(path: String, method: String, body: Data?, authenticated: Bool) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: configuration.baseURL)?.absoluteURL else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1000", forHTTPHeaderField: "ngrok-skip-browser-warning")
        if authenticated {
            let trimmedToken = authToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedToken.isEmpty else { throw APIError.unauthenticated }
            request.setValue(
                "nearai-prod_crabshack_session=\(trimmedToken)",
                forHTTPHeaderField: "Cookie"
            )
            request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
            request.setValue("https://private.near.ai", forHTTPHeaderField: "Origin")
            request.setValue("https://private.near.ai/", forHTTPHeaderField: "Referer")
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )
        }
        request.httpBody = body
        return request
    }

    func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.emptyResponse
        }
        #if DEBUG
        if !(200..<300).contains(http.statusCode) {
            let rawBody = String(data: data.prefix(400), encoding: .utf8) ?? "<binary>"
            let path = request.url?.path ?? "<unknown>"
            print("[NEAR API] \(request.httpMethod ?? "GET") \(path) -> HTTP \(http.statusCode)\n  body: \(rawBody)\n  headers: \(http.allHeaderFields)")
        }
        #endif
        guard (200..<300).contains(http.statusCode) else {
            let detail = decodeErrorMessage(from: data)
            let suffix = detail.isEmpty ? "" : " - \(detail)"
            throw APIError.status(http.statusCode, "HTTP \(http.statusCode)\(suffix)")
        }
        if T.self == EmptyResponse.self, data.isEmpty {
            guard let emptyResponse = EmptyResponse() as? T else {
                throw APIError.emptyResponse
            }
            return emptyResponse
        }
        guard !data.isEmpty else { throw APIError.emptyResponse }
        return try decoder.decode(T.self, from: data)
    }

    func performRaw(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.status(http.statusCode, decodeErrorMessage(from: data))
        }
        return data
    }

    func validateStreamingResponse(
        _ response: URLResponse,
        bytes: URLSession.AsyncBytes
    ) async throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            var message = ""
            for try await line in bytes.lines {
                if line.hasPrefix("data:") {
                    let dataLine = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let data = dataLine.data(using: .utf8) {
                        message = decodeErrorMessage(from: data)
                    }
                    if !message.isEmpty { break }
                } else {
                    message += line
                }
                if message.count > 1_000 { break }
            }
            if let data = message.data(using: .utf8) {
                let decoded = decodeErrorMessage(from: data)
                if !decoded.isEmpty {
                    message = decoded
                }
            }
            throw APIError.status(http.statusCode, message)
        }
    }

    func decodeErrorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["detail", "error", "message"] {
                if let value = object[key] as? String {
                    return value
                }
                if let nested = object[key] as? [String: Any],
                   let message = nested["message"] as? String {
                    return message
                }
            }
        }
        guard let raw = String(data: Data(data.prefix(240)), encoding: .utf8) else { return "" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("<"), !trimmed.hasPrefix("{") else { return "" }
        return trimmed
    }

    static func conversationPath(_ conversationID: String, suffix: [String] = []) throws -> String {
        let conversationSegment = try safePathSegment(conversationID, minimumLength: 6)
        let pathSegments = ["v1", "conversations", conversationSegment] + suffix
        return "/" + pathSegments.joined(separator: "/")
    }

    static func isSafeAPIPathID(_ value: String, minimumLength: Int = 1) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == value,
              trimmed.count >= minimumLength,
              trimmed.count <= 256,
              !trimmed.contains("."),
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains(":"),
              !trimmed.contains("%") else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func safePathSegment(_ value: String, minimumLength: Int = 1) throws -> String {
        guard isSafeAPIPathID(value, minimumLength: minimumLength),
              let encoded = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "_-"))) else {
            throw APIError.invalidURL
        }
        return encoded
    }

    static func sanitizedMultipartFilename(_ filename: String) -> String {
        let cleaned = filename
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\\", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Attachment" : String(cleaned.prefix(160))
    }
}

struct EmptyResponse: Decodable {}

struct EmptyPayload: Encodable {}

extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        let safeName = Self.multipartQuotedString(name)
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(safeName)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartFile(
        name: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String
    ) {
        let safeName = Self.multipartQuotedString(name)
        let safeFilename = Self.multipartQuotedString(filename)
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(safeName)\"; filename=\"\(safeFilename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }

    private static func multipartQuotedString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }
}
