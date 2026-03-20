import XCTest
@testable import CoderIDE

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
}
