import SwiftUI
import UIKit

enum SourceFaviconResolver {
    private struct KnownSource {
        let suffix: String
        let aliases: [String]
        let mark: String
        let tint: Color
    }

    static func faviconURL(for rawValue: String?) -> URL? {
        faviconURLs(for: rawValue).first
    }

    static func faviconURLs(for rawValue: String?) -> [URL] {
        guard let host = canonicalFaviconHost(for: rawValue) else { return [] }
        return [
            googleFaviconURL(queryName: "domain_url", value: "https://\(host)"),
            googleFaviconURL(queryName: "domain", value: host),
            duckDuckGoFaviconURL(host: host),
            URL(string: "https://\(host)/favicon.ico")
        ].compactMap { $0 }
    }

    static func canonicalFaviconHost(for rawValue: String?) -> String? {
        if let host = normalizedPublicHost(from: rawValue) {
            return host
        }
        return knownSource(from: rawValue)?.suffix
    }

    static func normalizedPublicHost(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.user == nil,
              components.password == nil,
              let host = components.host,
              URLSecurity.isPublicHost(host) else {
            return nil
        }

        return normalizedHost(host)
    }

    static func canonicalSourceDomain(from rawValue: String?) -> String? {
        if let host = normalizedPublicHost(from: rawValue) {
            return host
        }
        return knownSource(from: rawValue)?.suffix
    }

    static func sourceIdentity(domain: String?, label: String?) -> String? {
        if normalizedPublicHost(from: domain) != nil {
            return domain?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if knownSource(from: label) != nil {
            return label?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nonBlank(domain) ?? nonBlank(label)
    }

    static func displayName(for rawValue: String?, fallback: String? = nil) -> String? {
        if let source = knownSource(from: rawValue) ?? knownSource(from: fallback) {
            return displayName(for: source)
        }
        if let host = canonicalSourceDomain(from: rawValue) {
            return host
        }
        return nonBlank(rawValue) ?? nonBlank(fallback)
    }

    static func fallbackTint(for rawValue: String?) -> Color {
        if let source = knownSource(from: rawValue) {
            return source.tint
        }
        let palette: [Color] = [
            .actionPrimary,
            .trustVerified,
            .proofVerified,
            .proofStale,
            Color(red: 0.66, green: 0.30, blue: 0.86),
            Color(red: 0.08, green: 0.54, blue: 0.70),
            Color(red: 0.78, green: 0.22, blue: 0.30)
        ]
        guard let host = normalizedPublicHost(from: rawValue), !host.isEmpty else {
            return .actionPrimary
        }
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in host.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return palette[Int(hash % UInt64(palette.count))]
    }

    static func fallbackLetter(for rawValue: String?, fallback: String) -> String {
        fallbackMark(for: rawValue, fallback: fallback, maxLength: 1)
    }

    static func fallbackMark(for rawValue: String?, fallback: String, maxLength: Int = 2) -> String {
        if let source = knownSource(from: rawValue) ?? knownSource(from: fallback) {
            return String(source.mark.prefix(max(1, maxLength)))
        }
        let value = canonicalSourceDomain(from: rawValue) ?? fallback
        let hostLead = value.split(separator: ".").first.map(String.init) ?? value
        let letters = hostLead.uppercased().filter { $0.isLetter || $0.isNumber }
        if !letters.isEmpty {
            return String(letters.prefix(max(1, maxLength)))
        }
        return String(fallback.uppercased().prefix(max(1, maxLength)))
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
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }

    private static func googleFaviconURL(queryName: String, value: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "sz", value: "64"),
            URLQueryItem(name: queryName, value: value)
        ]
        return components?.url
    }

    private static func duckDuckGoFaviconURL(host: String) -> URL? {
        URL(string: "https://icons.duckduckgo.com/ip2/\(host).ico")
    }

    private static func knownSource(from rawValue: String?) -> KnownSource? {
        guard let rawValue else { return nil }
        if let host = normalizedPublicHost(from: rawValue) {
            return knownSource(forHost: host)
        }
        return knownSource(forLabel: rawValue)
    }

    private static func knownSource(forHost host: String) -> KnownSource? {
        knownSources.first { host == $0.suffix || host.hasSuffix(".\($0.suffix)") }
    }

    private static func knownSource(forLabel rawLabel: String) -> KnownSource? {
        let label = normalizedLabel(rawLabel)
        guard !label.isEmpty else { return nil }
        return knownSources.first { source in
            normalizedLabel(source.suffix) == label
                || normalizedLabel(source.mark) == label
                || source.aliases.contains(label)
        }
    }

    private static func normalizedLabel(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func nonBlank(_ rawValue: String?) -> String? {
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func displayName(for source: KnownSource) -> String {
        switch source.suffix {
        case "reuters.com":
            return "Reuters"
        case "apnews.com":
            return "AP"
        case "bloomberg.com":
            return "Bloomberg"
        case "google.com":
            return "Google"
        case "bbc.com":
            return "BBC"
        case "cnn.com":
            return "CNN"
        case "cbsnews.com":
            return "CBS"
        case "wsj.com":
            return "WSJ"
        case "nytimes.com":
            return "NYTimes"
        case "theguardian.com":
            return "Guardian"
        case "cnbc.com":
            return "CNBC"
        case "axios.com":
            return "Axios"
        case "techcrunch.com":
            return "TechCrunch"
        case "theverge.com":
            return "The Verge"
        case "macrumors.com":
            return "MacRumors"
        case "aljazeera.com":
            return "Al Jazeera"
        default:
            return source.suffix
        }
    }

    private static let knownSources: [KnownSource] = [
        KnownSource(
            suffix: "reuters.com",
            aliases: ["reuters", "thomsonreuters"],
            mark: "R",
            tint: Color(red: 0.95, green: 0.38, blue: 0.13)
        ),
        KnownSource(
            suffix: "apnews.com",
            aliases: ["ap", "apnews", "associatedpress"],
            mark: "AP",
            tint: Color.brandBlack
        ),
        KnownSource(
            suffix: "bloomberg.com",
            aliases: ["bloomberg", "bloombergnews"],
            mark: "B",
            tint: Color.brandBlack
        ),
        KnownSource(
            suffix: "google.com",
            aliases: ["google", "googlenews"],
            mark: "G",
            tint: Color.googleBlue
        ),
        KnownSource(
            suffix: "bbc.com",
            aliases: ["bbc", "bbcnews"],
            mark: "B",
            tint: Color(red: 0.72, green: 0.02, blue: 0.04)
        ),
        KnownSource(
            suffix: "cnn.com",
            aliases: ["cnn", "cnnnews"],
            mark: "C",
            tint: Color(red: 0.80, green: 0.02, blue: 0.04)
        ),
        KnownSource(
            suffix: "cbsnews.com",
            aliases: ["cbs", "cbsnews"],
            mark: "C",
            tint: Color(red: 0.08, green: 0.20, blue: 0.42)
        ),
        KnownSource(
            suffix: "wsj.com",
            aliases: ["wsj", "wallstreetjournal", "thewallstreetjournal"],
            mark: "WS",
            tint: Color(red: 0.88, green: 0.37, blue: 0.12)
        ),
        KnownSource(
            suffix: "nytimes.com",
            aliases: ["nytimes", "nyt", "newyorktimes", "thenewyorktimes"],
            mark: "NY",
            tint: Color.brandBlack
        ),
        KnownSource(
            suffix: "theguardian.com",
            aliases: ["guardian", "theguardian", "guardiannigeria"],
            mark: "G",
            tint: Color(red: 0.03, green: 0.16, blue: 0.35)
        ),
        KnownSource(
            suffix: "cnbc.com",
            aliases: ["cnbc"],
            mark: "C",
            tint: Color(red: 0.04, green: 0.29, blue: 0.54)
        ),
        KnownSource(
            suffix: "axios.com",
            aliases: ["axios"],
            mark: "A",
            tint: Color(red: 0.93, green: 0.33, blue: 0.13)
        ),
        KnownSource(
            suffix: "techcrunch.com",
            aliases: ["techcrunch", "tc"],
            mark: "TC",
            tint: Color(red: 0.03, green: 0.58, blue: 0.27)
        ),
        KnownSource(
            suffix: "theverge.com",
            aliases: ["verge", "theverge"],
            mark: "V",
            tint: Color(red: 0.38, green: 0.20, blue: 0.88)
        ),
        KnownSource(
            suffix: "macrumors.com",
            aliases: ["macrumors"],
            mark: "M",
            tint: Color(red: 0.08, green: 0.38, blue: 0.78)
        ),
        KnownSource(
            suffix: "aljazeera.com",
            aliases: ["aljazeera", "aljazeeranews"],
            mark: "AJ",
            tint: Color(red: 0.71, green: 0.45, blue: 0.12)
        )
    ]
}

/// Fetches favicons through an ephemeral, cookie-free session so the lookup
/// can never accumulate a cross-session tracking identifier. Decoded images
/// are kept in a memory cache keyed by host.
enum FaviconLoader {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024, diskCapacity: 0)
        return URLSession(configuration: configuration)
    }()

    static let cache = NSCache<NSString, UIImage>()

    static func load(host: String, urls: [URL]) async -> UIImage? {
        let key = host as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        for url in urls {
            guard let (data, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                continue
            }
            cache.setObject(image, forKey: key)
            return image
        }
        return nil
    }
}

struct SourceFaviconView: View {
    let domain: String?
    let size: CGFloat
    let fallbackText: String
    let fallbackColor: Color
    let fallbackForegroundColor: Color
    let cornerRadius: CGFloat
    let borderColor: Color?
    let borderWidth: CGFloat
    /// Whether the favicon may be fetched over the network. Network favicons
    /// are reserved for sources that came from an explicit web search;
    /// model-emitted or unknown-provenance domains stay local-only (tinted
    /// letter tile) so conversation-derived hostnames never leave the device.
    let allowsNetworkFavicon: Bool

    @State private var loadedImage: UIImage?

    init(
        domain: String?,
        size: CGFloat,
        fallbackText: String,
        fallbackColor: Color? = nil,
        fallbackForegroundColor: Color = .white,
        cornerRadius: CGFloat? = nil,
        borderColor: Color? = nil,
        borderWidth: CGFloat = 0,
        allowsNetworkFavicon: Bool = false
    ) {
        self.domain = domain
        self.size = size
        self.fallbackText = fallbackText
        self.fallbackColor = fallbackColor ?? SourceFaviconResolver.fallbackTint(for: domain ?? fallbackText)
        self.fallbackForegroundColor = fallbackForegroundColor
        self.cornerRadius = cornerRadius ?? max(4, size * 0.25)
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.allowsNetworkFavicon = allowsNetworkFavicon
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle.app(cornerRadius))
            .overlay {
                if let borderColor, borderWidth > 0 {
                    RoundedRectangle.app(cornerRadius)
                        .stroke(borderColor, lineWidth: borderWidth)
                }
            }
            .task(id: resolvedHost) {
                await loadFaviconIfAllowed()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let loadedImage {
            Image(uiImage: loadedImage)
                .resizable()
                .scaledToFit()
                .padding(imagePadding)
                .frame(width: size, height: size)
                .background(Color.appSecondaryBackground)
        } else {
            fallback
        }
    }

    private func loadFaviconIfAllowed() async {
        guard allowsNetworkFavicon,
              let host = resolvedHost,
              !faviconURLs.isEmpty else {
            loadedImage = nil
            return
        }
        loadedImage = await FaviconLoader.load(host: host, urls: faviconURLs)
    }

    private var resolvedHost: String? {
        SourceFaviconResolver.canonicalFaviconHost(for: domain)
    }

    private var faviconURLs: [URL] {
        SourceFaviconResolver.faviconURLs(for: domain)
    }

    private var fallback: some View {
        Text(SourceFaviconResolver.fallbackMark(for: domain, fallback: fallbackText, maxLength: fallbackMaxLength))
            .font(fallbackFont)
            .minimumScaleFactor(0.45)
            .foregroundStyle(fallbackForegroundColor)
            .frame(width: size, height: size)
            .background(fallbackColor, in: RoundedRectangle.app(cornerRadius))
            .overlay {
                RoundedRectangle.app(cornerRadius)
                    .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
            }
    }

    private var imagePadding: CGFloat {
        size <= 14 ? 1 : 2
    }

    private var fallbackMaxLength: Int {
        size >= 18 ? 2 : 1
    }

    private var fallbackFont: Font {
        size < 18 ? .caption2.weight(.bold) : .caption.weight(.bold)
    }
}
