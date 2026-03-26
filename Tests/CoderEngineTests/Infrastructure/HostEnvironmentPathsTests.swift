import CoderEngine
import XCTest

final class HostEnvironmentPathsTests: XCTestCase {
    func testAugmentedPATHPreservesSegments() {
        let merged = HostEnvironmentPaths.augmentedPATH(existing: "/usr/bin:/bin")
        XCTAssertTrue(merged.split(separator: ":").contains("/usr/bin"))
        XCTAssertTrue(merged.split(separator: ":").contains("/bin"))
    }

    func testHomebrewBinaryDirectoriesMatchRipgrepSearchPaths() {
        for dir in HostEnvironmentPaths.homebrewBinaryDirectories {
            XCTAssertTrue(dir.hasSuffix("/bin"))
        }
        XCTAssertTrue(HostEnvironmentPaths.homebrewBinaryDirectories.contains("/opt/homebrew/bin"))
        XCTAssertTrue(HostEnvironmentPaths.homebrewBinaryDirectories.contains("/usr/local/bin"))
    }
}
