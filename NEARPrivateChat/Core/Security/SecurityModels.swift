import Foundation
import SwiftUI

struct AttestationSnapshot: Hashable {
    let nonce: String
    let signingAlgorithm: String
    let model: String?
    let coveredModelIDs: [String]
    let fetchedAt: Date
    let chatGatewayAddress: String?
    let cloudGatewayAddress: String?
    let modelAttestationCount: Int
    let prettyJSON: String

    init(
        nonce: String,
        signingAlgorithm: String,
        model: String?,
        coveredModelIDs: [String] = [],
        fetchedAt: Date,
        chatGatewayAddress: String?,
        cloudGatewayAddress: String?,
        modelAttestationCount: Int,
        prettyJSON: String
    ) {
        self.nonce = nonce
        self.signingAlgorithm = signingAlgorithm
        self.model = model
        self.coveredModelIDs = coveredModelIDs
        self.fetchedAt = fetchedAt
        self.chatGatewayAddress = chatGatewayAddress
        self.cloudGatewayAddress = cloudGatewayAddress
        self.modelAttestationCount = modelAttestationCount
        self.prettyJSON = prettyJSON
    }
}

enum URLSecurity {
    static func isPublicHTTPSURL(_ url: URL) -> Bool {
        isPublicWebURL(url, allowHTTP: false)
    }

    static func isPublicWebURL(_ url: URL, allowHTTP: Bool = true) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              (scheme == "https" || (allowHTTP && scheme == "http")),
              components.user == nil,
              components.password == nil,
              let host = components.host,
              isPublicHost(host) else {
            return false
        }
        return true
    }

    static func isPublicHost(_ rawHost: String) -> Bool {
        let host = normalizedHost(rawHost)
        guard !host.isEmpty else { return false }
        if host == "localhost" ||
            host == "metadata" ||
            host == "metadata.google.internal" ||
            host.hasSuffix(".localhost") ||
            host.hasSuffix(".local") {
            return false
        }
        if let octets = parsedIPv4Octets(host) {
            return !isReservedIPv4(octets)
        }
        if isReservedIPv6Literal(host) {
            return false
        }
        if host.contains(":") {
            return true
        }
        if !host.contains(".") {
            return false
        }
        return true
    }

    static func normalizedPublicHTTPSURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let host = components.host,
              isPublicHost(host) else {
            return nil
        }
        components.scheme = "https"
        return components.url.flatMap { isPublicHTTPSURL($0) ? $0 : nil }
    }

    private static func normalizedHost(_ rawHost: String) -> String {
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host
    }

    private static func parsedIPv4Octets(_ host: String) -> [UInt32]? {
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count),
              pieces.allSatisfy({ !$0.isEmpty }),
              let values = optionalSequence(pieces.map { parseIPv4Component(String($0)) }) else {
            return nil
        }
        switch values.count {
        case 1:
            guard values[0] <= UInt32.max else { return nil }
            return [
                (values[0] >> 24) & 0xff,
                (values[0] >> 16) & 0xff,
                (values[0] >> 8) & 0xff,
                values[0] & 0xff
            ]
        case 2:
            guard values[0] <= 0xff, values[1] <= 0x00ff_ffff else { return nil }
            return [values[0], (values[1] >> 16) & 0xff, (values[1] >> 8) & 0xff, values[1] & 0xff]
        case 3:
            guard values[0] <= 0xff, values[1] <= 0xff, values[2] <= 0xffff else { return nil }
            return [values[0], values[1], (values[2] >> 8) & 0xff, values[2] & 0xff]
        case 4:
            guard values.allSatisfy({ $0 <= 0xff }) else { return nil }
            return values
        default:
            return nil
        }
    }

    private static func parseIPv4Component(_ value: String) -> UInt32? {
        let lowercased = value.lowercased()
        if lowercased.hasPrefix("0x") {
            return UInt32(lowercased.dropFirst(2), radix: 16)
        }
        if lowercased.count > 1, lowercased.hasPrefix("0") {
            return UInt32(lowercased.dropFirst(), radix: 8)
        }
        return UInt32(lowercased, radix: 10)
    }

    private static func optionalSequence<T>(_ values: [T?]) -> [T]? {
        var unwrapped: [T] = []
        for value in values {
            guard let value else { return nil }
            unwrapped.append(value)
        }
        return unwrapped
    }

    private static func isReservedIPv4(_ octets: [UInt32]) -> Bool {
        guard octets.count == 4 else { return true }
        let first = octets[0]
        let second = octets[1]
        switch first {
        case 0, 10, 127:
            return true
        case 100:
            return (64...127).contains(second)
        case 169:
            return second == 254
        case 172:
            return (16...31).contains(second)
        case 192:
            return second == 0 || second == 168
        case 198:
            return second == 18 || second == 19 || (second == 51 && octets[2] == 100)
        case 203:
            return second == 0 && octets[2] == 113
        case 224...255:
            return true
        default:
            return false
        }
    }

    private static func isReservedIPv6Literal(_ host: String) -> Bool {
        guard host.contains(":") else { return false }
        if host == "::" || host == "::1" {
            return true
        }
        if let mappedIPv4 = host.split(separator: ":").last,
           mappedIPv4.contains("."),
           let octets = parsedIPv4Octets(String(mappedIPv4)) {
            return isReservedIPv4(octets)
        }
        let firstHextet = host.split(separator: ":").first.map(String.init) ?? ""
        guard let firstValue = UInt32(firstHextet, radix: 16) else {
            return true
        }
        return (0xfc00...0xfdff).contains(firstValue) ||
            (0xfe80...0xfebf).contains(firstValue) ||
            firstValue == 0
    }
}
