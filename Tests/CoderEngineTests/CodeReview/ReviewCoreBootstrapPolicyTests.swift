import XCTest
@testable import CoderEngine

final class ReviewCoreBootstrapPolicyTests: XCTestCase {
    func testDefersRustBootstrapWhenXCTestEnvironmentIsPresentWithoutExplicitLibraryPath() {
        XCTAssertTrue(
            shouldDeferRustReviewCoreBootstrap(
                environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
            )
        )
    }

    func testDoesNotDeferRustBootstrapWhenExplicitLibraryPathIsProvided() {
        XCTAssertFalse(
            shouldDeferRustReviewCoreBootstrap(
                environment: [
                    "XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration",
                    "SOLOCODE_REVIEW_CORE_LIBRARY_PATH": "/tmp/libsolocode_rust_core.dylib",
                ]
            )
        )
    }

    func testForceSwiftFlagDisablesRustBootstrap() {
        XCTAssertTrue(
            shouldDeferRustReviewCoreBootstrap(
                environment: ["SOLOCODE_REVIEW_CORE_FORCE_SWIFT": "1"]
            )
        )
    }
}
