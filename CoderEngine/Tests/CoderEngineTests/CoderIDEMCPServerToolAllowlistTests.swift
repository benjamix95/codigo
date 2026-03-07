import XCTest

#if canImport(CoderIDEMCPServer)
@testable import CoderIDEMCPServer

final class CoderIDEMCPServerToolAllowlistTests: XCTestCase {
    func testAllowsAdvertisedToolRuntimeName() {
        XCTAssertTrue(CoderIDETools.isAllowedRuntimeToolName("read"))
    }

    func testRejectsUnadvertisedBashRuntimeName() {
        XCTAssertFalse(CoderIDETools.isAllowedRuntimeToolName("bash"))
    }

    func testNamespacedBashMCPNameNormalizesToRejectedRuntimeName() {
        let runtimeName = CoderIDETools.runtimeToolName(from: "coderide/coderide_bash")
        XCTAssertEqual(runtimeName, "bash")
        XCTAssertFalse(CoderIDETools.isAllowedRuntimeToolName(runtimeName))
    }
}
#endif
