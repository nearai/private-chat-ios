import XCTest
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testSourceFaviconURLDerivationNormalizesPublicHosts() {
        XCTAssertEqual(
            SourceFaviconResolver.faviconURL(for: "https://www.example.com/story?id=1")?.absoluteString,
            "https://www.google.com/s2/favicons?sz=64&domain_url=https://example.com"
        )
        XCTAssertEqual(
            SourceFaviconResolver.faviconURL(for: "near.org")?.absoluteString,
            "https://www.google.com/s2/favicons?sz=64&domain_url=https://near.org"
        )
        XCTAssertEqual(SourceFaviconResolver.normalizedPublicHost(from: "http://www.apple.com/news"), "apple.com")
        XCTAssertEqual(SourceFaviconResolver.normalizedPublicHost(from: "  HTTPS://WWW.REUTERS.COM/world  "), "reuters.com")

        let reutersCandidates = SourceFaviconResolver.faviconURLs(for: "https://www.reuters.com/world")
            .map(\.absoluteString)
        XCTAssertEqual(reutersCandidates.count, 4)
        XCTAssertEqual(reutersCandidates[1], "https://www.google.com/s2/favicons?sz=64&domain=reuters.com")
        XCTAssertEqual(reutersCandidates[2], "https://icons.duckduckgo.com/ip2/reuters.com.ico")
        XCTAssertEqual(reutersCandidates[3], "https://reuters.com/favicon.ico")
    }

    func testSourceFaviconURLDerivationRejectsEmptyPrivateAndNonHTTPInputs() {
        XCTAssertNil(SourceFaviconResolver.faviconURL(for: nil))
        XCTAssertNil(SourceFaviconResolver.faviconURL(for: "   "))
        XCTAssertNil(SourceFaviconResolver.faviconURL(for: "ftp://example.com/story"))
        XCTAssertNil(SourceFaviconResolver.faviconURL(for: "file:///tmp/private-note"))
        XCTAssertNil(SourceFaviconResolver.faviconURL(for: "localhost"))
        XCTAssertNil(SourceFaviconResolver.faviconURL(for: "https://192.168.1.10/story"))
    }

    func testSourceFaviconViewNetworkFetchIsOptIn() {
        // WidgetSourceDot constructs the view without allowsNetworkFavicon, so
        // model-emitted domains must default to local-only rendering.
        let defaultView = SourceFaviconView(domain: "https://example.com", size: 14, fallbackText: "E")
        XCTAssertFalse(defaultView.allowsNetworkFavicon)

        let webSearchView = SourceFaviconView(
            domain: "https://example.com",
            size: 20,
            fallbackText: "E",
            allowsNetworkFavicon: true
        )
        XCTAssertTrue(webSearchView.allowsNetworkFavicon)
    }

    func testSourceFallbackMarksUseRecognizablePublisherInitials() {
        XCTAssertEqual(SourceFaviconResolver.fallbackMark(for: "https://apnews.com/article/1", fallback: "A"), "AP")
        XCTAssertEqual(SourceFaviconResolver.fallbackMark(for: "https://www.reuters.com/world", fallback: "R"), "R")
        XCTAssertEqual(SourceFaviconResolver.fallbackMark(for: "https://news.google.com/topstories", fallback: "N"), "G")
        XCTAssertEqual(SourceFaviconResolver.fallbackMark(for: "Reuters", fallback: "S"), "R")
        XCTAssertEqual(SourceFaviconResolver.fallbackMark(for: "Google News", fallback: "S"), "G")
        XCTAssertEqual(SourceFaviconResolver.fallbackMark(for: "Associated Press", fallback: "S"), "AP")
        XCTAssertEqual(SourceFaviconResolver.fallbackMark(for: "CNN", fallback: "S"), "C")
        XCTAssertEqual(SourceFaviconResolver.fallbackMark(for: "CBS News", fallback: "S"), "C")
        XCTAssertEqual(SourceFaviconResolver.fallbackMark(for: "https://example.com/story", fallback: "E"), "EX")
    }

    func testSourceFallbackRecognizesCurrentEventsPublishers() {
        XCTAssertEqual(SourceFaviconResolver.displayName(for: "https://www.cnn.com/world"), "CNN")
        XCTAssertEqual(SourceFaviconResolver.displayName(for: "CBS News"), "CBS")

        let cbsURLs = SourceFaviconResolver.faviconURLs(for: "CBS News")
            .map(\.absoluteString)
        XCTAssertEqual(cbsURLs[1], "https://www.google.com/s2/favicons?sz=64&domain=cbsnews.com")
    }

    func testWidgetNewsSourcesResolveLabelOnlyPublisherBadges() {
        let reuters = WidgetNewsSource(label: "Reuters")
        XCTAssertEqual(reuters.faviconIdentity, "Reuters")
        XCTAssertEqual(reuters.displaySourceText, "Reuters")
        XCTAssertEqual(SourceFaviconResolver.fallbackMark(for: reuters.faviconIdentity, fallback: reuters.fallbackMark), "R")
        XCTAssertTrue(reuters.allowsNetworkFavicon)

        let google = WidgetNewsSource(label: "Google News")
        XCTAssertEqual(google.faviconIdentity, "Google News")
        XCTAssertEqual(google.displaySourceText, "Google")
        XCTAssertEqual(SourceFaviconResolver.fallbackMark(for: google.faviconIdentity, fallback: google.fallbackMark), "G")
        XCTAssertTrue(google.allowsNetworkFavicon)

        let apWithDomain = WidgetNewsSource(label: "A", domain: "https://www.apnews.com/article/1")
        XCTAssertEqual(apWithDomain.faviconIdentity, "https://www.apnews.com/article/1")
        XCTAssertEqual(apWithDomain.displaySourceText, "AP")
        XCTAssertEqual(SourceFaviconResolver.fallbackMark(for: apWithDomain.faviconIdentity, fallback: apWithDomain.fallbackMark), "AP")
        XCTAssertTrue(apWithDomain.allowsNetworkFavicon)

        let unknown = WidgetNewsSource(label: "Local Desk")
        XCTAssertEqual(unknown.faviconIdentity, "Local Desk")
        XCTAssertEqual(unknown.displaySourceText, "Local Desk")
        XCTAssertEqual(SourceFaviconResolver.fallbackMark(for: unknown.faviconIdentity, fallback: unknown.fallbackMark), "LO")
        XCTAssertFalse(unknown.allowsNetworkFavicon)
    }

    func testFaviconURLsWorkFromKnownSourceLabel() {
        let urls = SourceFaviconResolver.faviconURLs(for: "Reuters")
            .map(\.absoluteString)
        XCTAssertEqual(urls.count, 4)
        XCTAssertEqual(urls[1], "https://www.google.com/s2/favicons?sz=64&domain=reuters.com")
        XCTAssertEqual(urls[2], "https://icons.duckduckgo.com/ip2/reuters.com.ico")
        XCTAssertEqual(urls[3], "https://reuters.com/favicon.ico")
    }

    func testWebSearchSourceProvenanceControlsNetworkFaviconsAndBadges() {
        let missingVendorType = WebSearchSource(type: nil, url: "https://reuters.com/world")
        XCTAssertTrue(missingVendorType.allowsNetworkFavicon)
        XCTAssertEqual(missingVendorType.sourceBadgeLabel, "Web")

        let web = WebSearchSource(type: "web", url: "https://example.com/a")
        XCTAssertTrue(web.allowsNetworkFavicon)
        XCTAssertEqual(web.sourceBadgeLabel, "Web")

        let inferred = WebSearchSource(type: "inferred", url: "https://example.com/b")
        XCTAssertTrue(inferred.allowsNetworkFavicon)
        XCTAssertEqual(inferred.sourceBadgeLabel, "Web")

        let news = WebSearchSource(type: "news_article", url: "https://example.com/c")
        XCTAssertTrue(news.allowsNetworkFavicon)
        XCTAssertEqual(news.sourceBadgeLabel, "News")

        let organic = WebSearchSource(type: "search_result", url: "https://apnews.com/report")
        XCTAssertTrue(organic.allowsNetworkFavicon)
        XCTAssertEqual(organic.sourceBadgeLabel, "Web")

        let project = WebSearchSource(type: "project_file", url: "https://example.com/project")
        XCTAssertFalse(project.allowsNetworkFavicon)
        XCTAssertNil(project.sourceBadgeLabel)
    }
}
