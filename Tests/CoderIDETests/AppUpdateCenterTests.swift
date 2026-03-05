import XCTest
@testable import CoderIDE

final class AppUpdateCenterTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppUpdateCenterTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        AppUpdateCenterURLProtocolStub.requestHandler = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testShouldUpdateWhenVersionIsHigher() {
        let local = "1.2.3"
        let manifest = AppUpdateCenter.AppUpdateManifest(
            schema: 1,
            version: "1.3.0",
            build: "1",
            minimumSystemVersion: "14.0",
            releaseDate: nil,
            required: false,
            downloadURL: nil,
            releaseNotes: nil,
            releaseNotesURL: nil,
            changelogURL: nil,
            notes: nil,
            changelog: nil
        )
        XCTAssertTrue(AppUpdateCenter.shouldUpdate(localVersion: local, localBuild: "1", manifest: manifest))
    }

    func testShouldUpdateWhenVersionIsSameButBuildIsHigher() {
        let local = "1.2.3"
        let manifest = AppUpdateCenter.AppUpdateManifest(
            schema: 1,
            version: "1.2.3",
            build: "4",
            minimumSystemVersion: "14.0",
            releaseDate: nil,
            required: false,
            downloadURL: nil,
            releaseNotes: nil,
            releaseNotesURL: nil,
            changelogURL: nil,
            notes: nil,
            changelog: nil
        )
        XCTAssertTrue(AppUpdateCenter.shouldUpdate(localVersion: local, localBuild: "3", manifest: manifest))
    }

    func testShouldNotUpdateWhenManifestIsLowerOrEqual() {
        let local = "1.4.0"
        let manifest = AppUpdateCenter.AppUpdateManifest(
            schema: 1,
            version: "1.3.9",
            build: "99",
            minimumSystemVersion: "14.0",
            releaseDate: nil,
            required: false,
            downloadURL: nil,
            releaseNotes: nil,
            releaseNotesURL: nil,
            changelogURL: nil,
            notes: nil,
            changelog: nil
        )
        XCTAssertFalse(AppUpdateCenter.shouldUpdate(localVersion: local, localBuild: "20", manifest: manifest))
    }

    func testManifestDecodesSnakeCaseJSON() throws {
        let json = """
        {
          "schema": 1,
          "version": "1.0.1",
          "build": "2",
          "minimum_system_version": "14.0",
          "release_notes": "Release notes summary",
          "release_notes_url": "https://example.com/release-notes"
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(AppUpdateCenter.AppUpdateManifest.self, from: data)

        XCTAssertEqual(manifest.version, "1.0.1")
        XCTAssertEqual(manifest.build, "2")
        XCTAssertEqual(manifest.minimumSystemVersion, "14.0")
        XCTAssertEqual(manifest.releaseNotes, "Release notes summary")
        XCTAssertEqual(manifest.releaseNotesURL, "https://example.com/release-notes")
    }

    @MainActor
    func testShouldCheckNowReturnsTrueWhenLastCheckedDateIsInFutureAndHealsTimestampFailSafe() {
        let futureDate = Date().addingTimeInterval(60 * 30)
        defaults.set(futureDate, forKey: AppUpdateCenter.lastCheckedKey)
        let center = AppUpdateCenter(userDefaults: defaults)
        center.lastCheckedAt = futureDate

        XCTAssertTrue(center.shouldCheckNow())
        guard let healedDate = defaults.object(forKey: AppUpdateCenter.lastCheckedKey) as? Date else {
            XCTFail("Expected healed lastCheckedAt date in UserDefaults")
            return
        }
        let expectedHealedDate = Date().addingTimeInterval(-AppUpdateCenter.checkInterval)
        XCTAssertLessThanOrEqual(abs(healedDate.timeIntervalSince(expectedHealedDate)), 2.0)
        XCTAssertNotNil(center.lastCheckedAt)
        XCTAssertLessThanOrEqual(abs((center.lastCheckedAt ?? .distantFuture).timeIntervalSince(expectedHealedDate)), 2.0)
    }

    @MainActor
    func testShouldCheckNowReturnsFalseWhenLastCheckIsRecent() {
        let recentDate = Date().addingTimeInterval(-(AppUpdateCenter.checkInterval / 2))
        defaults.set(recentDate, forKey: AppUpdateCenter.lastCheckedKey)
        let center = AppUpdateCenter(userDefaults: defaults)
        center.lastCheckedAt = recentDate

        XCTAssertFalse(center.shouldCheckNow())
    }

    @MainActor
    func testCheckForUpdatesHTTPFailureDoesNotPersistLastCheckedAt() async {
        let url = URL(string: "https://example.com/manifest.json")!
        defaults.set(url.absoluteString, forKey: AppUpdateCenter.manifestURLKey)

        AppUpdateCenterURLProtocolStub.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? url,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let center = AppUpdateCenter(
            userDefaults: defaults,
            urlSession: makeStubbedURLSession()
        )

        await center.checkForUpdates(force: true)

        XCTAssertNil(center.lastCheckedAt)
        XCTAssertNil(defaults.object(forKey: AppUpdateCenter.lastCheckedKey))
        if case .failed = center.state {
            XCTAssertNotNil(center.lastError)
        } else {
            XCTFail("Expected failed state for HTTP 500 response")
        }
    }

    @MainActor
    func testCheckForUpdatesSuccessPersistsLastCheckedAt() async {
        let url = URL(string: "https://example.com/manifest.json")!
        defaults.set(url.absoluteString, forKey: AppUpdateCenter.manifestURLKey)

        let manifestJSON = """
        {
          "schema": 1,
          "version": "1.0.1",
          "build": "2",
          "minimum_system_version": "1.0"
        }
        """

        AppUpdateCenterURLProtocolStub.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(manifestJSON.utf8))
        }

        let center = AppUpdateCenter(
            userDefaults: defaults,
            urlSession: makeStubbedURLSession()
        )

        await center.checkForUpdates(force: true)

        guard let persistedDate = defaults.object(forKey: AppUpdateCenter.lastCheckedKey) as? Date else {
            XCTFail("Expected persisted lastCheckedAt on successful update check")
            return
        }
        XCTAssertNotNil(center.lastCheckedAt)
        XCTAssertLessThanOrEqual(abs(persistedDate.timeIntervalSinceNow), 2.0)
        if case .failed(let message) = center.state {
            XCTFail("Unexpected failed state after successful response: \(message)")
        }
    }

    private func makeStubbedURLSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AppUpdateCenterURLProtocolStub.self]
        return URLSession(configuration: config)
    }
}

private final class AppUpdateCenterURLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
