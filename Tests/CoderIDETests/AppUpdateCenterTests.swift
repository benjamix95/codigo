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
}
