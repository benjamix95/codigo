import XCTest
@testable import CoderIDE

@MainActor
final class ChatStoreRustBootstrapPolicyTests: XCTestCase {
    func testSkipsRustBootstrapDuringXCTestHostLaunchWithoutExplicitLibraryPath() {
        XCTAssertTrue(
            shouldSkipRustStoreBootstrapForTests(
                environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
            )
        )
    }

    func testDoesNotSkipRustBootstrapWhenLibraryPathIsExplicitlyProvided() {
        XCTAssertFalse(
            shouldSkipRustStoreBootstrapForTests(
                environment: [
                    "XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration",
                    "SOLOCODE_REVIEW_CORE_LIBRARY_PATH": "/tmp/libsolocode_rust_core.dylib",
                ]
            )
        )
    }

    func testDoesNotSkipRustBootstrapForNormalAppLaunchEnvironment() {
        XCTAssertFalse(
            shouldSkipRustStoreBootstrapForTests(environment: [:])
        )
    }

    func testMarkersSanitizationDoesNotCrashWhenReviewCoreIsForcedOff() async {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        defer { unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT") }

        let input = "  Before [CODERIDE:todo_write|id=t1]\n"
        let sanitized = await ChatStore.stripCoderideMarkers(input)

        XCTAssertEqual(sanitized, "Before")
    }

    func testOperationalThinkingExtractionReturnsNilWhenReviewCoreIsForcedOff() async {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        defer { unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT") }
        let line = await ChatStore.extractLastOperationalThinkingLine(
            from: "Done\nExplored files\nReading config"
        )

        XCTAssertNil(line)
    }
}
