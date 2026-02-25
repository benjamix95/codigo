import XCTest
@testable import CoderEngine

final class WebToolsTests: XCTestCase {

    // MARK: - WebSearchProvider Enum

    func testProviderAllCasesCount() {
        XCTAssertEqual(WebSearchProvider.allCases.count, 4)
    }

    func testProviderRawValues() {
        XCTAssertEqual(WebSearchProvider.duckduckgo.rawValue, "duckduckgo")
        XCTAssertEqual(WebSearchProvider.brave.rawValue, "brave")
        XCTAssertEqual(WebSearchProvider.tavily.rawValue, "tavily")
        XCTAssertEqual(WebSearchProvider.serper.rawValue, "serper")
    }

    func testProviderDisplayNames() {
        XCTAssertEqual(WebSearchProvider.duckduckgo.displayName, "DuckDuckGo")
        XCTAssertEqual(WebSearchProvider.brave.displayName, "Brave Search")
        XCTAssertEqual(WebSearchProvider.tavily.displayName, "Tavily")
        XCTAssertEqual(WebSearchProvider.serper.displayName, "Serper")
    }

    func testProviderRequiresApiKey() {
        XCTAssertFalse(WebSearchProvider.duckduckgo.requiresApiKey)
        XCTAssertTrue(WebSearchProvider.brave.requiresApiKey)
        XCTAssertTrue(WebSearchProvider.tavily.requiresApiKey)
        XCTAssertTrue(WebSearchProvider.serper.requiresApiKey)
    }

    func testProviderSignupURLs() {
        XCTAssertTrue(WebSearchProvider.duckduckgo.signupURL.isEmpty)
        XCTAssertTrue(WebSearchProvider.brave.signupURL.contains("brave.com"))
        XCTAssertTrue(WebSearchProvider.tavily.signupURL.contains("tavily.com"))
        XCTAssertTrue(WebSearchProvider.serper.signupURL.contains("serper.dev"))
    }

    func testProviderFreeTierDescriptions() {
        for provider in WebSearchProvider.allCases {
            XCTAssertFalse(provider.freeTierDescription.isEmpty, "\(provider.rawValue) should have a free tier description")
        }
    }

    func testProviderInitFromRawValue() {
        XCTAssertEqual(WebSearchProvider(rawValue: "duckduckgo"), .duckduckgo)
        XCTAssertEqual(WebSearchProvider(rawValue: "brave"), .brave)
        XCTAssertEqual(WebSearchProvider(rawValue: "tavily"), .tavily)
        XCTAssertEqual(WebSearchProvider(rawValue: "serper"), .serper)
        XCTAssertNil(WebSearchProvider(rawValue: "google"))
        XCTAssertNil(WebSearchProvider(rawValue: ""))
    }

    // MARK: - WebSearchService Initialization

    func testDefaultProviderIsDuckDuckGo() async {
        let service = WebSearchService()
        let provider = await service.activeProvider
        XCTAssertEqual(provider, .duckduckgo)
    }

    func testLegacyInitWithApiKeySetsProviderToBrave() async {
        let service = WebSearchService(apiKey: "test-key-123")
        let provider = await service.activeProvider
        XCTAssertEqual(provider, .brave)
    }

    func testLegacyInitWithEmptyApiKeySetsProviderToDuckDuckGo() async {
        let service = WebSearchService(apiKey: "")
        let provider = await service.activeProvider
        XCTAssertEqual(provider, .duckduckgo)
    }

    func testLegacyInitWithNilApiKeySetsProviderToDuckDuckGo() async {
        let service = WebSearchService(apiKey: nil)
        let provider = await service.activeProvider
        XCTAssertEqual(provider, .duckduckgo)
    }

    func testExplicitProviderInit() async {
        let service = WebSearchService(provider: .tavily, apiKeys: [.tavily: "test-key"])
        let provider = await service.activeProvider
        XCTAssertEqual(provider, .tavily)
    }

    // MARK: - WebSearchService Validation

    func testSearchEmptyQueryThrows() async {
        let service = WebSearchService()
        do {
            _ = try await service.search(query: "")
            XCTFail("Expected error for empty query")
        } catch {
            let desc = error.localizedDescription
            XCTAssertTrue(desc.contains("Empty query"), "Expected 'Empty query' error, got: \(desc)")
        }
    }

    func testSearchWhitespaceOnlyQueryThrows() async {
        let service = WebSearchService()
        do {
            _ = try await service.search(query: "   \n\t  ")
            XCTFail("Expected error for whitespace-only query")
        } catch {
            let desc = error.localizedDescription
            XCTAssertTrue(desc.contains("Empty query"), "Expected 'Empty query' error, got: \(desc)")
        }
    }

    // MARK: - WebFetchService Validation

    func testFetchEmptyURLThrows() async {
        let service = WebFetchService()
        do {
            _ = try await service.fetch(urlString: "")
            XCTFail("Expected error for empty URL")
        } catch let error as WebToolsError {
            if case .invalidURL = error {
                // Expected
            } else {
                XCTFail("Expected invalidURL error, got: \(error)")
            }
        } catch {
            XCTFail("Expected WebToolsError, got: \(error)")
        }
    }

    func testFetchLocalhostBlocked() async {
        let service = WebFetchService()
        do {
            _ = try await service.fetch(urlString: "http://localhost:8080/api")
            XCTFail("Expected error for localhost")
        } catch let error as WebToolsError {
            if case .invalidURL(let msg) = error {
                XCTAssertTrue(msg.contains("localhost") || msg.contains("private"), "Error should mention localhost, got: \(msg)")
            } else {
                XCTFail("Expected invalidURL error, got: \(error)")
            }
        } catch {
            XCTFail("Expected WebToolsError, got: \(error)")
        }
    }

    func testFetchPrivateIPBlocked() async {
        let service = WebFetchService()
        let privateAddresses = ["http://192.168.1.1", "http://10.0.0.1", "http://172.16.0.1", "http://127.0.0.1"]
        for addr in privateAddresses {
            do {
                _ = try await service.fetch(urlString: addr)
                XCTFail("Expected error for private address: \(addr)")
            } catch let error as WebToolsError {
                if case .invalidURL = error {
                    // Expected
                } else {
                    XCTFail("Expected invalidURL error for \(addr), got: \(error)")
                }
            } catch {
                XCTFail("Expected WebToolsError for \(addr), got: \(error)")
            }
        }
    }

    func testFetchPrependsHTTPS() async {
        let service = WebFetchService()
        // This will likely fail with a network error (can't reach test domain),
        // but it should NOT fail with "invalidURL" — it should prepend https://
        do {
            _ = try await service.fetch(urlString: "example.com")
            // If it succeeds, that's fine too
        } catch let error as WebToolsError {
            // Should NOT be invalidURL (the URL was valid after prepending https://)
            if case .invalidURL = error {
                XCTFail("URL should have been valid after prepending https://")
            }
            // Any other error (httpError, timeout, etc.) is fine — means URL was accepted
        } catch {
            // Network error is acceptable — URL was accepted
        }
    }

    // MARK: - WebToolsError

    func testWebToolsErrorDescriptions() {
        let errors: [WebToolsError] = [
            .invalidURL("https://bad.url"),
            .httpError(404),
            .decodingFailed,
            .searchFailed("timeout"),
            .timeout,
            .noResults,
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) description should not be empty")
        }
    }

    func testWebToolsErrorInvalidURLContainsURL() {
        let error = WebToolsError.invalidURL("https://bad.url")
        XCTAssertTrue(error.errorDescription!.contains("https://bad.url"))
    }

    func testWebToolsErrorHTTPContainsCode() {
        let error = WebToolsError.httpError(503)
        XCTAssertTrue(error.errorDescription!.contains("503"))
    }

    func testWebToolsErrorSearchFailedContainsMessage() {
        let error = WebToolsError.searchFailed("rate limited")
        XCTAssertTrue(error.errorDescription!.contains("rate limited"))
    }

    // MARK: - HTMLToMarkdown

    func testConvertHeadings() {
        let html = "<h1>Title</h1><h2>Subtitle</h2><h3>Section</h3>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("# Title"), "Expected h1 conversion, got: \(md)")
        XCTAssertTrue(md.contains("## Subtitle"), "Expected h2 conversion, got: \(md)")
        XCTAssertTrue(md.contains("### Section"), "Expected h3 conversion, got: \(md)")
    }

    func testConvertLinks() {
        let html = #"<a href="https://example.com">Click here</a>"#
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("[Click here](https://example.com)"), "Expected link conversion, got: \(md)")
    }

    func testConvertEmphasis() {
        let html = "<strong>bold</strong> and <em>italic</em>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("**bold**"), "Expected bold conversion, got: \(md)")
        XCTAssertTrue(md.contains("*italic*"), "Expected italic conversion, got: \(md)")
    }

    func testConvertInlineCode() {
        let html = "<code>let x = 42</code>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("`let x = 42`"), "Expected code conversion, got: \(md)")
    }

    func testConvertCodeBlock() {
        let html = "<pre>func hello() {\n  print(\"hi\")\n}</pre>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("```"), "Expected code block markers, got: \(md)")
        XCTAssertTrue(md.contains("func hello()"), "Expected code block content, got: \(md)")
    }

    func testConvertList() {
        let html = "<ul><li>Apple</li><li>Banana</li></ul>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("- Apple"), "Expected list item, got: \(md)")
        XCTAssertTrue(md.contains("- Banana"), "Expected list item, got: \(md)")
    }

    func testConvertBlockquote() {
        let html = "<blockquote>Famous quote</blockquote>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("> Famous quote"), "Expected blockquote, got: \(md)")
    }

    func testConvertHorizontalRule() {
        let html = "<p>Before</p><hr/><p>After</p>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("---"), "Expected horizontal rule, got: \(md)")
    }

    func testStripsScriptAndStyleTags() {
        let html = "<html><body><script>alert('xss')</script><style>.foo{color:red}</style><p>Content</p></body></html>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertFalse(md.contains("alert"), "Script content should be removed")
        XCTAssertFalse(md.contains("color:red"), "Style content should be removed")
        XCTAssertTrue(md.contains("Content"), "Regular content should be preserved")
    }

    func testStripsNavAndFooter() {
        let html = "<body><nav>Menu items</nav><main><p>Article</p></main><footer>Copyright</footer></body>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertFalse(md.contains("Menu items"), "Nav should be stripped")
        XCTAssertFalse(md.contains("Copyright"), "Footer should be stripped")
        XCTAssertTrue(md.contains("Article"), "Main content should be preserved")
    }

    func testExtractsArticleContent() {
        let html = "<html><body><div>Sidebar</div><article><p>Article content</p></article></body></html>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("Article content"), "Article content should be extracted")
    }

    func testExtractsMainContent() {
        let html = "<html><body><div>Header</div><main><p>Main content</p></main></body></html>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("Main content"), "Main content should be extracted")
    }

    func testDecodesHTMLEntities() {
        let html = "<p>Tom &amp; Jerry &lt;3&gt; &quot;Cartoons&quot; &copy; 2024</p>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("Tom & Jerry"), "Should decode &amp;")
        XCTAssertTrue(md.contains("<3>"), "Should decode &lt; and &gt;")
        XCTAssertTrue(md.contains("\"Cartoons\""), "Should decode &quot;")
        XCTAssertTrue(md.contains("©"), "Should decode &copy;")
    }

    func testDecodesNumericEntities() {
        let html = "<p>&#65;&#66;&#67;</p>"  // ABC
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("ABC"), "Should decode numeric entities, got: \(md)")
    }

    func testDecodesHexEntities() {
        let html = "<p>&#x41;&#x42;&#x43;</p>"  // ABC
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("ABC"), "Should decode hex entities, got: \(md)")
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(HTMLToMarkdown.convert(""), "")
    }

    func testStripTagsBasic() {
        let html = "<b>bold</b> and <i>italic</i>"
        let stripped = HTMLToMarkdown.stripTags(html)
        XCTAssertEqual(stripped, "bold and italic")
    }

    func testStripTagsDecodesEntities() {
        let html = "Tom &amp; Jerry"
        let stripped = HTMLToMarkdown.stripTags(html)
        XCTAssertEqual(stripped, "Tom & Jerry")
    }

    func testStripTagsTrims() {
        let html = "  <span>  hello  </span>  "
        let stripped = HTMLToMarkdown.stripTags(html)
        XCTAssertEqual(stripped, "hello")
    }

    func testCollapsesExcessiveWhitespace() {
        let html = "<p>Line one</p>\n\n\n\n\n<p>Line two</p>"
        let md = HTMLToMarkdown.convert(html)
        // Should not have more than 2 consecutive newlines
        XCTAssertFalse(md.contains("\n\n\n"), "Should collapse excessive newlines, got: \(md)")
    }
}
