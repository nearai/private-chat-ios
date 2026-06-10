import SwiftUI
import UIKit

enum SourceFaviconResolver {
    static func faviconURL(for rawValue: String?) -> URL? {
        guard let host = normalizedPublicHost(from: rawValue) else { return nil }
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "sz", value: "64"),
            URLQueryItem(name: "domain", value: host)
        ]
        return components?.url
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

    static func fallbackTint(for rawValue: String?) -> Color {
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
        let value = normalizedPublicHost(from: rawValue) ?? fallback
        let letters = value.uppercased().filter { $0.isLetter || $0.isNumber }
        if let first = letters.first {
            return String(first)
        }
        return String(fallback.uppercased().prefix(1))
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

    static func load(host: String, url: URL) async -> UIImage? {
        let key = host as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let image = UIImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
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
        self.fallbackColor = fallbackColor ?? SourceFaviconResolver.fallbackTint(for: domain)
        self.fallbackForegroundColor = fallbackForegroundColor
        self.cornerRadius = cornerRadius ?? max(4, size * 0.25)
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.allowsNetworkFavicon = allowsNetworkFavicon
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if let borderColor, borderWidth > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
              let faviconURL else {
            loadedImage = nil
            return
        }
        loadedImage = await FaviconLoader.load(host: host, url: faviconURL)
    }

    private var resolvedHost: String? {
        SourceFaviconResolver.normalizedPublicHost(from: domain)
    }

    private var faviconURL: URL? {
        SourceFaviconResolver.faviconURL(for: domain)
    }

    private var fallback: some View {
        Text(SourceFaviconResolver.fallbackLetter(for: domain, fallback: fallbackText))
            .font(.system(size: max(8, size * 0.56), weight: .bold))
            .foregroundStyle(fallbackForegroundColor)
            .frame(width: size, height: size)
            .background(fallbackColor, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var imagePadding: CGFloat {
        size <= 14 ? 1 : 2
    }
}
