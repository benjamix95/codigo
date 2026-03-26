import XCTest
@testable import CoderEngine

final class ExcludedDirectoriesTests: XCTestCase {

    func testDefaultSetContainsNodeModules() {
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("node_modules"))
    }

    func testDefaultSetContainsPythonVenvs() {
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("venv"))
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains(".venv"))
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("__pycache__"))
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("site-packages"))
    }

    func testDefaultSetContainsRubyBundle() {
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("bundle"))
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains(".bundle"))
    }

    func testDefaultSetContainsRustTarget() {
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("target"))
    }

    func testDefaultSetContainsDotNet() {
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("packages"))
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("bin"))
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("obj"))
    }

    func testDefaultSetContainsIOS() {
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("Pods"))
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("Carthage"))
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("DerivedData"))
    }

    func testDefaultSetContainsDocker() {
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains(".docker"))
    }

    func testDefaultSetContainsTerraform() {
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains(".terraform"))
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains(".terragrunt-cache"))
    }

    func testDefaultSetContainsPnpmStore() {
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains(".pnpm-store"))
    }

    func testDefaultSetContainsBowerComponents() {
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("bower_components"))
    }

    func testDefaultSetContainsExportAndToolingDirs() {
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("output"))
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("jspm_packages"))
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("zig-cache"))
        XCTAssertTrue(ExcludedDirectories.defaultSet.contains("_build"))
    }

    func testRipgrepGlobArgsGeneratesExclusionFlags() {
        let args = ExcludedDirectories.ripgrepGlobArgs
        // Should have pairs of --glob + pattern
        XCTAssertTrue(args.count > 0)
        XCTAssertEqual(args.count % 2, 0, "Should be pairs of --glob + pattern")

        // Verify structure
        for i in stride(from: 0, to: args.count, by: 2) {
            XCTAssertEqual(args[i], "--glob")
            XCTAssertTrue(args[i + 1].hasPrefix("!"), "Glob pattern should start with !")
        }
    }
}
