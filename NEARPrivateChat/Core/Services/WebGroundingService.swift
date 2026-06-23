import Foundation
import OSLog

struct WebGroundingContext: Hashable {
    let query: String
    let fetchedAt: Date
    let results: [WebGroundingResult]

    var sources: [WebSearchSource] {
        results.compactMap {
            guard let url = WebSearchSource.sanitizedURLString($0.urlString) else { return nil }
            return WebSearchSource(
                type: $0.kind,
                url: url,
                title: $0.title,
                publishedAt: $0.publishedAt
            )
        }
    }

    var promptSection: String {
        let date = fetchedAt.formatted(date: .complete, time: .shortened)
        let safeResults = results.compactMap(Self.safePromptResult)
        let items = safeResults.enumerated().map { index, result in
            let published = result.publishedAt.map { " Published: \($0)." } ?? ""
            let snippet = result.snippet.isEmpty ? "" : "\n   Untrusted snippet: \"\(result.snippet)\""
            return """
            \(index + 1). \(result.title)
               Source: \(result.sourceName).\(published)
               URL: \(result.urlString)\(snippet)
            """
        }.joined(separator: "\n")

        return """
        App-side web search results for "\(query)".
        Retrieved: \(date).

        \(items)
        """
    }

    private static func safePromptResult(_ result: WebGroundingResult) -> WebGroundingResult? {
        guard let url = WebSearchSource.sanitizedURLString(result.urlString),
              let parsedURL = URL(string: url) else {
            return nil
        }
        let host = parsedURL.host(percentEncoded: false) ?? result.sourceName
        return WebGroundingResult(
            title: sanitizedEvidenceText(result.title, maxCharacters: 180),
            urlString: url,
            sourceName: sanitizedEvidenceText(host, maxCharacters: 120),
            snippet: sanitizedEvidenceText(result.snippet, maxCharacters: 360),
            publishedAt: result.publishedAt.map { sanitizedEvidenceText($0, maxCharacters: 80) },
            kind: result.kind
        )
    }

    private static func sanitizedEvidenceText(_ value: String, maxCharacters: Int) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxCharacters else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: maxCharacters)
        return "\(normalized[..<end])..."
    }
}

struct WebGroundingResult: Hashable {
    let title: String
    let urlString: String
    let sourceName: String
    let snippet: String
    let publishedAt: String?
    let kind: String
}

final class WebGroundingService {
    func cancel() {
        // Searches are structured awaits owned by the caller today. Keep this
        // hook so ChatStore lifecycle cleanup has a stable owner boundary.
    }

    private let session: URLSession
#if DEBUG
    private let logger = Logger(subsystem: "ai.near.privatechat", category: "web-grounding")
#endif

    init(session: URLSession = .shared) {
        self.session = session
    }

    enum SearchMode: Equatable {
        case automatic
        case newsFirst
        case webFirst

        func prefersNews(researchModeEnabled: Bool, needsLiveWeb: Bool) -> Bool {
            switch self {
            case .automatic:
                return researchModeEnabled || needsLiveWeb
            case .newsFirst:
                return true
            case .webFirst:
                return false
            }
        }
    }

    func search(for prompt: String, preferNews: Bool) async throws -> WebGroundingContext {
        let queries = Self.queries(from: prompt)
        var combined: [WebGroundingResult] = []
        for query in queries {
            async let newsResults = safeFetchGoogleNews(query: query)
            async let webResults = safeFetchDuckDuckGo(query: query)
            let news = await newsResults
            let web = await webResults

            if preferNews {
                combined += news + web
            } else {
                combined += web + news
            }
        }

        let rankingQuery = queries.joined(separator: " ")
        let ranked = Self.ranked(Self.unique(combined).compactMap(Self.publicHTTPSResult), query: rankingQuery).prefix(8)
        guard !ranked.isEmpty else {
            throw APIError.status(0, "No web results found.")
        }
#if DEBUG
        let newsCount = ranked.filter { $0.kind == "news" }.count
        let webCount = ranked.filter { $0.kind == "web" }.count
        logger.debug("web search queries=\(queries.joined(separator: " | "), privacy: .public) preferNews=\(preferNews) resultCount=\(ranked.count) news=\(newsCount) web=\(webCount)")
#endif
        return WebGroundingContext(query: queries.joined(separator: " | "), fetchedAt: Date(), results: Array(ranked))
    }

    private func safeFetchGoogleNews(query: String) async -> [WebGroundingResult] {
        (try? await fetchGoogleNews(query: query)) ?? []
    }

    private func safeFetchDuckDuckGo(query: String) async -> [WebGroundingResult] {
        (try? await fetchDuckDuckGo(query: query)) ?? []
    }

    static func query(from prompt: String) -> String {
        let normalizedPrompt = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let directiveStrippedPrompt = strippedLeadingSearchDirective(from: normalizedPrompt)
        if !looksMultiTopicCurrentEventsPrompt(directiveStrippedPrompt),
           let newsTopic = extractNewsTopic(from: directiveStrippedPrompt) {
            return clippedQuery("\(newsTopic) latest news")
        }

        var query = directiveStrippedPrompt
        let instructionPatterns = [
            #"(?i)\b(from\s+)?(google\s+)?news\s+only\b"#,
            #"(?i)\b(from\s+)?google\s+news\b"#,
            #"(?i)\b(web|internet|general\s+web)\s+only\b"#,
            #"(?i)\bnot\s+news\b"#,
            #"(?i)\b(with|using)\s+(the\s+)?(live\s+|current\s+)?(web(\s+search|\s+sources?)?|internet|sources?)\b"#,
            #"(?i)\b(and\s+)?cite\s+(your\s+)?sources?\b.*$"#,
            #"(?i)\b(with\s+)?sources?\b.*$"#,
            #"(?i)\b(answer|respond|return)\s+(in|with|as)\b.*$"#,
            #"(?i)\b(in|as)\s+(\d+|one|two|three|four|five)\s+(bullets?|sentences?|points?)\b.*$"#,
            #"(?i)\bseparate\s+confirmed\s+facts\b.*$"#,
            #"(?i)\bplease\b"#
        ]
        for pattern in instructionPatterns {
            query = query.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        let leadingQuestionPatterns = [
            #"(?i)^what\s+(is|are|was|were|did|does|do|happened)\s+"#,
            #"(?i)^who\s+(is|are|was|were)\s+"#,
            #"(?i)^when\s+(is|are|was|were|did)\s+"#,
            #"(?i)^where\s+(is|are|was|were|did)\s+"#,
            #"(?i)^why\s+(is|are|was|were|did|does|do)\s+"#,
            #"(?i)^how\s+(is|are|was|were|did|does|do)\s+"#,
            #"(?i)^(tell me about|give me|find|search for|look up|research|investigate)\s+"#,
            #"(?i)^check\s+(today'?s|todays|latest|current)?\s*(reporting|reports|news|developments)\s+(on|about)\s+"#,
            #"(?i)^check\s+"#
        ]
        for pattern in leadingQuestionPatterns {
            query = query.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        query = normalizedNewsHeadlineQuery(query)
        query = cleanedQuery(query)

        if query.isEmpty {
            query = cleanedQuery(normalizedPrompt)
        }
        if query.count > 180 {
            return clippedQuery(query)
        }
        return query.isEmpty ? "current news" : query
    }

    static func queries(from prompt: String) -> [String] {
        let primaryQuery = query(from: prompt)
        var candidates = [primaryQuery]
        candidates.append(contentsOf: currentEventsTopicQueries(from: primaryQuery))

        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            let cleaned = clippedQuery(candidate)
            let key = cleaned.lowercased()
            guard !cleaned.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return cleaned
        }
        .prefix(3)
        .map { $0 }
    }

    static func searchMode(for prompt: String) -> SearchMode {
        let normalized = normalizedQueryInput(prompt).lowercased()
        guard !normalized.isEmpty else { return .automatic }

        let webOnlyPatterns = [
            #"\b(web|internet|general\s+web)\s+only\b"#,
            #"\bnot\s+news\b"#,
            #"\b(no|without)\s+news\b"#
        ]
        if webOnlyPatterns.contains(where: { normalized.range(of: $0, options: .regularExpression) != nil }) {
            return .webFirst
        }

        let newsPatterns = [
            #"\b(from\s+)?google\s+news\b"#,
            #"\bnews\s+only\b"#,
            #"\b(latest|recent|current)\s+news\b"#,
            #"\b(news|headlines?|stories)\b.*\b(today|this\s+(morning|week|month|year))\b"#,
            #"\b(today|this\s+(morning|week|month|year))\b.*\b(news|headlines?|stories)\b"#
        ]
        if newsPatterns.contains(where: { normalized.range(of: $0, options: .regularExpression) != nil }) {
            return .newsFirst
        }

        return .automatic
    }

    static func searchPrompt(for text: String, priorUserTexts: [String]) -> String? {
        let prompt = normalizedQueryInput(text)
        guard !prompt.isEmpty else { return nil }
        guard isLowSignalFollowUp(prompt) else { return prompt }
        return priorUserTexts.reversed().first { candidate in
            let normalizedCandidate = normalizedQueryInput(candidate)
            return !normalizedCandidate.isEmpty && !isLowSignalFollowUp(normalizedCandidate)
        }.map(normalizedQueryInput)
    }

    static func isLowSignalFollowUp(_ text: String) -> Bool {
        let normalized = normalizedQueryInput(text)
        guard !normalized.isEmpty else { return true }

        let lowercased = normalized.lowercased()
        let words = wordTokens(in: normalized)
        let loweredWords = words.map { $0.lowercased() }
        let wordCount = loweredWords.count
        guard wordCount > 0 else { return true }

        let exactPhrases: Set<String> = [
            "again",
            "continue",
            "do it",
            "do that",
            "do the job",
            "do the job asked",
            "do the job i asked",
            "fix it",
            "go",
            "go ahead",
            "keep going",
            "more",
            "next",
            "ok",
            "okay",
            "please",
            "redo",
            "retry",
            "run",
            "run it",
            "try again",
            "try one more time",
            "yes"
        ]
        if exactPhrases.contains(lowercased) {
            return true
        }

        if wordCount <= 3,
           loweredWords.count >= 2,
           loweredWords[0] == "where",
           ["is", "are", "was", "were"].contains(loweredWords[1]) {
            let objectWords = Array(loweredWords.dropFirst(2))
            if objectWords.isEmpty || objectWords.allSatisfy(lowSignalObjectWords.contains) {
                return true
            }
        }

        guard wordCount <= 5 else { return false }
        if imperativeWords.contains(loweredWords[0]) {
            let remainder = Array(loweredWords.dropFirst())
            return remainder.isEmpty || remainder.allSatisfy(lowSignalImperativeWords.contains)
        }
        if loweredWords[0] == "please" {
            let remainder = Array(loweredWords.dropFirst())
            return remainder.isEmpty || remainder.allSatisfy(lowSignalImperativeWords.contains)
        }

        return false
    }

    private static let imperativeWords: Set<String> = [
        "continue",
        "do",
        "fix",
        "go",
        "redo",
        "retry",
        "run",
        "try"
    ]

    private static let lowSignalObjectWords: Set<String> = [
        "answer",
        "cost",
        "data",
        "info",
        "it",
        "job",
        "price",
        "result",
        "results",
        "source",
        "sources",
        "that",
        "the",
        "thing",
        "this"
    ]

    private static let lowSignalImperativeWords: Set<String> = lowSignalObjectWords.union([
        "again",
        "ahead",
        "asked",
        "going",
        "i",
        "it",
        "job",
        "me",
        "more",
        "one",
        "please",
        "same",
        "the",
        "time"
    ])

    private static func normalizedQueryInput(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func wordTokens(in value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func extractNewsTopic(from prompt: String) -> String? {
        let patterns = [
            #"(?i)\b(?:latest|recent|current)\s+(?:news|updates|developments)\s+(?:on|about|for|in)\s+([^?.!,;]+)"#,
            #"(?i)\bnews\s+(?:on|about|for|in)\s+([^?.!,;]+)"#,
            #"(?i)\b(?:latest|recent|current)\s+([^?.!,;]{2,80}?)\s+(?:news|updates|developments)\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)
            guard let match = regex.firstMatch(in: prompt, range: range),
                  match.numberOfRanges > 1,
                  let topicRange = Range(match.range(at: 1), in: prompt) else {
                continue
            }
            let topic = cleanedQuery(String(prompt[topicRange]))
            if !topic.isEmpty {
                return topic
            }
        }
        return nil
    }

    private static func looksMultiTopicCurrentEventsPrompt(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        let hasConnector = lowercased.range(of: #"\b(and|or|plus)\b"#, options: .regularExpression) != nil
        let hasFreshCue = lowercased.range(
            of: #"\b(today|latest|current|recent|news|reporting|developments|updates)\b"#,
            options: .regularExpression
        ) != nil
        return hasConnector && hasFreshCue
    }

    private static func strippedLeadingSearchDirective(from value: String) -> String {
        value
            .replacingOccurrences(
                of: #"(?i)^\s*(use|using|with)\s+(the\s+)?(live\s+|current\s+)?(web(\s+search|\s+sources?)?|internet|search|sources?)\s*(to\s+)?[:,\-]?\s*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)^\s*run\s+(a\s+)?(live\s+|current\s+)?(web\s+)?search\s+(for|on|about)\s+"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedNewsHeadlineQuery(_ value: String) -> String {
        var query = value
        let leadingHeadlinePatterns = [
            #"(?i)^the\s+"#,
            #"(?i)^top\s+(\d+|one|two|three|four|five)\s+"#,
            #"(?i)^biggest\s+(\d+|one|two|three|four|five)?\s*"#,
            #"(?i)^major\s+(\d+|one|two|three|four|five)?\s*"#
        ]
        for pattern in leadingHeadlinePatterns {
            query = query.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        query = query.replacingOccurrences(of: #"(?i)\bnews\s+stories\b"#, with: "news", options: .regularExpression)
        query = query.replacingOccurrences(of: #"(?i)\bstories\b"#, with: "news", options: .regularExpression)
        query = query.replacingOccurrences(of: #"(?i)\bheadlines?\b"#, with: "news", options: .regularExpression)
        return query
    }

    private static func cleanedQuery(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"(?i)\b(and|or)\s*$"#, with: "", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func clippedQuery(_ value: String) -> String {
        let cleaned = cleanedQuery(value)
        guard cleaned.count > 180 else { return cleaned.isEmpty ? "current news" : cleaned }
        let end = cleaned.index(cleaned.startIndex, offsetBy: 180)
        return cleanedQuery(String(cleaned[..<end]))
    }

    private static func currentEventsTopicQueries(from query: String) -> [String] {
        let lowercased = query.lowercased()
        let isFreshQuery = [
            "today", "latest", "current", "news", "reporting", "developments", "updates"
        ].contains { lowercased.contains($0) }
        let hasConnector = lowercased.range(of: #"\b(and|or|plus)\b"#, options: .regularExpression) != nil
        guard isFreshQuery, hasConnector else { return [] }

        let splitReady = query
            .replacingOccurrences(
                of: #"(?i)\s+\b(and|plus)\b\s+(the\s+)?(latest|current|recent)\s+"#,
                with: " | ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)\s+\b(and|plus)\b\s+"#,
                with: " | ",
                options: .regularExpression
            )

        let parts = splitReady
            .split(separator: "|")
            .map { topicQuery(from: String($0)) }
            .filter { !$0.isEmpty }

        guard parts.count > 1 else { return [] }
        return parts
    }

    private static func topicQuery(from value: String) -> String {
        var topic = value
            .replacingOccurrences(of: #"(?i)\b(or)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^(the\s+)?(latest|current|recent|today'?s|todays)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bprivate-market\b"#, with: "private market", options: .regularExpression)
        topic = cleanedQuery(topic)

        let wordCount = wordTokens(in: topic).count
        guard wordCount >= 2 else { return "" }

        if topic.range(of: #"(?i)\b(news|updates|developments|reporting)\b"#, options: .regularExpression) != nil {
            return topic
        }
        return "\(topic) latest news"
    }

    private func fetchGoogleNews(query: String) async throws -> [WebGroundingResult] {
        guard var components = URLComponents(string: "https://news.google.com/rss/search") else {
            throw APIError.invalidURL
        }
        let newsQuery = Self.googleNewsQuery(from: query)
        components.queryItems = [
            URLQueryItem(name: "q", value: newsQuery),
            URLQueryItem(name: "hl", value: "en-US"),
            URLQueryItem(name: "gl", value: "US"),
            URLQueryItem(name: "ceid", value: "US:en")
        ]
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("NEARPrivateChat/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try validate(response)

        let parser = XMLParser(data: data)
        let delegate = GoogleNewsRSSParser()
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? APIError.status(0, "Could not parse news search results.")
        }
        return delegate.items.prefix(6).map {
            WebGroundingResult(
                title: $0.title,
                urlString: $0.link,
                sourceName: $0.sourceName,
                snippet: $0.summary,
                publishedAt: $0.pubDate,
                kind: "news"
            )
        }
    }

    private func fetchDuckDuckGo(query: String) async throws -> [WebGroundingResult] {
        guard var components = URLComponents(string: "https://lite.duckduckgo.com/lite/") else {
            throw APIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 NEARPrivateChat/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try validate(response)
        guard let html = String(data: data, encoding: .utf8) else {
            return []
        }
        return Self.parseDuckDuckGoResults(html)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.status(http.statusCode, "Search request failed.")
        }
    }

    private static func parseDuckDuckGoResults(_ html: String) -> [WebGroundingResult] {
        let pattern = #"<a rel="nofollow" href="([^"]+)" class='result-link'>(.*?)</a>.*?<td class='result-snippet'>\s*(.*?)\s*</td>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: nsRange).compactMap { match in
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html),
                  let snippetRange = Range(match.range(at: 3), in: html),
                  let urlString = decodedDuckDuckGoURL(String(html[hrefRange])) else {
                return nil
            }
            let title = cleanHTML(String(html[titleRange]))
            let snippet = cleanHTML(String(html[snippetRange]))
            guard !title.isEmpty, !urlString.isEmpty else { return nil }
            return WebGroundingResult(
                title: title,
                urlString: urlString,
                sourceName: URL(string: urlString)?.host ?? "Web",
                snippet: snippet,
                publishedAt: nil,
                kind: "web"
            )
        }
    }

    private static func decodedDuckDuckGoURL(_ href: String) -> String? {
        let absolute = href.hasPrefix("//") ? "https:\(href)" : href
        guard let components = URLComponents(string: htmlDecoded(absolute)) else {
            return nil
        }
        if let redirected = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let url = URL(string: redirected),
           URLSecurity.isPublicHTTPSURL(url) {
            return url.absoluteString
        }
        return components.url.flatMap { URLSecurity.isPublicHTTPSURL($0) ? $0.absoluteString : nil }
    }

    private static func publicHTTPSResult(_ result: WebGroundingResult) -> WebGroundingResult? {
        guard let url = WebSearchSource.sanitizedURLString(result.urlString),
              let parsedURL = URL(string: url) else {
            return nil
        }
        return WebGroundingResult(
            title: result.title,
            urlString: url,
            sourceName: parsedURL.host(percentEncoded: false) ?? result.sourceName,
            snippet: result.snippet,
            publishedAt: result.publishedAt,
            kind: result.kind
        )
    }

    private static func cleanHTML(_ text: String) -> String {
        let withoutTags = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return htmlDecoded(withoutTags)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func htmlDecoded(_ text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        let pattern = #"&#x([0-9a-fA-F]+);|&#([0-9]+);"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: decoded, range: NSRange(decoded.startIndex..<decoded.endIndex, in: decoded))
            for match in matches.reversed() {
                let hexValue = Range(match.range(at: 1), in: decoded).map { String(decoded[$0]) }
                let decimalValue = Range(match.range(at: 2), in: decoded).map { String(decoded[$0]) }
                let scalarValue = hexValue.flatMap { UInt32($0, radix: 16) } ?? decimalValue.flatMap { UInt32($0, radix: 10) }
                guard let scalarValue, let scalar = UnicodeScalar(scalarValue),
                      let range = Range(match.range(at: 0), in: decoded) else {
                    continue
                }
                decoded.replaceSubrange(range, with: String(Character(scalar)))
            }
        }
        return decoded
    }

    private static func unique(_ results: [WebGroundingResult]) -> [WebGroundingResult] {
        var seen = Set<String>()
        return results.filter { result in
            let key = (URL(string: result.urlString)?.host ?? result.urlString).lowercased() + "|" + result.title.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func ranked(_ results: [WebGroundingResult], query: String) -> [WebGroundingResult] {
        results
            .enumerated()
            .sorted { lhs, rhs in
                let lhsScore = sourceQualityScore(lhs.element, query: query) - Double(lhs.offset) * 0.01
                let rhsScore = sourceQualityScore(rhs.element, query: query) - Double(rhs.offset) * 0.01
                return lhsScore > rhsScore
            }
            .map(\.element)
    }

    private static func sourceQualityScore(_ result: WebGroundingResult, query: String) -> Double {
        let host = normalizedHost(URL(string: result.urlString)?.host ?? result.sourceName)
        let sourceName = result.sourceName.lowercased()
        let haystack = "\(result.title) \(result.snippet) \(sourceName) \(host)".lowercased()
        let freshQuery = queryNeedsFreshResults(query)
        var score = result.kind == "news" ? 8.0 : 0.0

        if freshQuery {
            score += result.kind == "news" ? 24 : -8
        }

        if preferredSourceHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            score += 36
        }
        if officialAIHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            score += 18
        }
        if lowQualityHostFragments.contains(where: { host.contains($0) }) {
            score -= 34
        }
        if result.publishedAt?.isEmpty == false {
            score += freshQuery ? 14 : 4
        }

        let queryTerms = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !queryStopWords.contains($0) }
        let matchedTerms = Set(queryTerms.filter { haystack.contains($0) })
        score += Double(min(matchedTerms.count, 6)) * 2.0
        return score
    }

    static func googleNewsQuery(from query: String) -> String {
        let cleaned = cleanedQuery(query)
        guard queryNeedsFreshResults(cleaned),
              cleaned.range(of: #"\bwhen:\d+[hdm]\b"#, options: .regularExpression) == nil else {
            return cleaned
        }
        return "\(cleaned) when:1d"
    }

#if DEBUG
    static func rankedForTesting(_ results: [WebGroundingResult], query: String) -> [WebGroundingResult] {
        ranked(results, query: query)
    }
#endif

    private static func queryNeedsFreshResults(_ query: String) -> Bool {
        query.lowercased().range(
            of: #"\b(today|latest|current|recent|breaking|this\s+(morning|afternoon|evening|week)|news|headlines?|stories|reporting|developments|updates)\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func normalizedHost(_ host: String) -> String {
        host
            .lowercased()
            .replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let preferredSourceHosts: Set<String> = [
        "openai.com",
        "anthropic.com",
        "ai.googleblog.com",
        "blog.google",
        "deepmind.google",
        "microsoft.com",
        "blogs.microsoft.com",
        "nvidia.com",
        "apple.com",
        "about.fb.com",
        "meta.com",
        "mistral.ai",
        "huggingface.co",
        "arxiv.org",
        "nature.com",
        "science.org",
        "technologyreview.com",
        "reuters.com",
        "bloomberg.com",
        "ft.com",
        "wsj.com",
        "theverge.com",
        "wired.com",
        "semianalysis.com"
    ]

    private static let officialAIHosts: Set<String> = [
        "openai.com",
        "anthropic.com",
        "google.com",
        "deepmind.google",
        "microsoft.com",
        "nvidia.com",
        "meta.com",
        "mistral.ai",
        "huggingface.co",
        "x.ai",
        "near.ai"
    ]

    private static let lowQualityHostFragments: [String] = [
        "coupon",
        "casino",
        "betting",
        "buildfastwithai",
        "aitool",
        "toolify",
        "futuretools",
        "topai",
        "bestai"
    ]

    private static let queryStopWords: Set<String> = [
        "the", "and", "for", "with", "what", "that", "this", "from", "latest", "news", "current", "recent", "summarize"
    ]
}

private final class GoogleNewsRSSParser: NSObject, XMLParserDelegate {
    struct Item {
        var title = ""
        var link = ""
        var pubDate = ""
        var sourceName = "Google News"
        var summary = ""
    }

    private(set) var items: [Item] = []
    private var currentItem: Item?
    private var currentElement = ""
    private var buffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        buffer = ""
        if elementName == "item" {
            currentItem = Item()
        } else if elementName == "source", currentItem != nil {
            currentItem?.sourceName = attributeDict["url"].flatMap { URL(string: $0)?.host } ?? currentItem?.sourceName ?? "Google News"
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "title":
            currentItem?.title = value
        case "link":
            currentItem?.link = value
        case "pubDate":
            currentItem?.pubDate = value
        case "source":
            if !value.isEmpty {
                currentItem?.sourceName = value
            }
        case "description":
            currentItem?.summary = WebGroundingService.htmlDecodedForRSS(value)
        case "item":
            if let item = currentItem, !item.title.isEmpty, !item.link.isEmpty {
                items.append(item)
            }
            currentItem = nil
        default:
            break
        }
        buffer = ""
        currentElement = ""
    }
}

private extension WebGroundingService {
    static func htmlDecodedForRSS(_ text: String) -> String {
        cleanRSSDescription(text)
    }

    private static func cleanRSSDescription(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
