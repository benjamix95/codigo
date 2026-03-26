import CoderEngine
import XCTest

final class RipgrepInstallerTests: XCTestCase {
    func testCommonBinaryPathsIncludesHomebrewLocations() {
        let paths = RipgrepInstaller.commonBinaryPaths
        XCTAssertTrue(paths.contains("/opt/homebrew/bin/rg"))
        XCTAssertTrue(paths.contains("/usr/local/bin/rg"))
    }

    func testIsInstalledIsStableCall() {
        _ = RipgrepInstaller.isInstalled()
    }
}
