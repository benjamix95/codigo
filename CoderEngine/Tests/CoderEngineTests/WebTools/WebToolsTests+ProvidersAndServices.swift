import XCTest
@testable import CoderEngine

extension WebToolsTests {
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
}
