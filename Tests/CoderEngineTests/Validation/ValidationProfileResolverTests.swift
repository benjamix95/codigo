import XCTest
@testable import CoderEngine

final class ValidationProfileResolverTests: XCTestCase {
    func testResolverMapsTriggerToMatchingProfile() {
        XCTAssertEqual(
            ValidationProfileResolver.resolve(trigger: .reviewPatchPreview),
            .reviewPatchPreview
        )
        XCTAssertEqual(
            ValidationProfileResolver.resolve(trigger: .reviewPatchApply),
            .reviewPatchApply
        )
        XCTAssertEqual(
            ValidationProfileResolver.resolve(trigger: .gitCommit),
            .gitCommit
        )
        XCTAssertEqual(
            ValidationProfileResolver.resolve(trigger: .ciFull),
            .ciFull
        )
    }

    func testConfigLoaderReadsSoloCodeSchemeAndNilTestPlan() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let descriptor = try ValidationConfigLoader.load(workspaceRoot: root)

        XCTAssertEqual(descriptor.workspace, "Solo Code.xcworkspace")
        XCTAssertEqual(descriptor.localScheme, "Solo Code-Debug")
        XCTAssertNil(descriptor.testPlan)
    }
}
