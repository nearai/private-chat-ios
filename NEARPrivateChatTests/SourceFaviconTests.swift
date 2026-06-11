import XCTest
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testSourceFaviconURLDerivationNormalizesPublicHosts() {
        XCTAssertEqual(
            SourceFaviconResolver.faviconURL(for: "https://www.example.com/story?id=1")?.absoluteString,
            "https://www.google.com/s2/favicons?sz=64&domain=example.com"
        )
        XCTAssertEqual(
            SourceFaviconResolver.faviconURL(for: "near.org")?.absoluteString,
            "https://www.google.com/s2/favicons?sz=64&domain=near.org"
        )
        XCTAssertEqual(SourceFaviconResolver.normalizedPublicHost(from: "http://www.apple.com/news"), "apple.com")
        XCTAssertEqual(SourceFaviconResolver.normalizedPublicHost(from: "  HTTPS://WWW.REUTERS.COM/world  "), "reuters.com")
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

    func testWebSearchSourceProvenanceControlsNetworkFaviconsAndBadges() {
        let web = WebSearchSource(type: "web", url: "https://example.com/a")
        XCTAssertTrue(web.allowsNetworkFavicon)
        XCTAssertEqual(web.sourceBadgeLabel, "Web")

        let inferred = WebSearchSource(type: "inferred", url: "https://example.com/b")
        XCTAssertTrue(inferred.allowsNetworkFavicon)
        XCTAssertEqual(inferred.sourceBadgeLabel, "Web")

        let news = WebSearchSource(type: "news_article", url: "https://example.com/c")
        XCTAssertTrue(news.allowsNetworkFavicon)
        XCTAssertEqual(news.sourceBadgeLabel, "News")

        let project = WebSearchSource(type: "project_file", url: "https://example.com/project")
        XCTAssertFalse(project.allowsNetworkFavicon)
        XCTAssertNil(project.sourceBadgeLabel)
    }
}
