import XCTest
@testable import CoderEngine

final class PatchSafetyStageTests: XCTestCase {
    func testFailsOnOutOfScopePath() async {
        let stage = PatchSafetyStage()
        let result = await stage.run(
            context: ValidationContext(
                trigger: .reviewPatchPreview,
                workspaceRoot: URL(fileURLWithPath: NSTemporaryDirectory()),
                touchedFiles: ["../Secrets.swift"]
            ),
            profile: .reviewPatchPreview,
            descriptor: makeDescriptor()
        )

        XCTAssertEqual(result.status, .failed)
    }

    func testPassesWhenWorkspaceAlreadyContainsPatch() async {
        let stage = PatchSafetyStage()
        let result = await stage.run(
            context: ValidationContext(
                trigger: .reviewPatchPreview,
                workspaceRoot: URL(fileURLWithPath: NSTemporaryDirectory()),
                touchedFiles: ["Engine/CoderEngine/Sources/Pipeline/Foo.swift"],
                workspaceContainsPatch: true
            ),
            profile: .reviewPatchPreview,
            descriptor: makeDescriptor()
        )

        XCTAssertEqual(result.status, .passed)
    }

    private func makeDescriptor() -> ProjectValidationDescriptor {
        ProjectValidationDescriptor(
            version: 1,
            workspace: "Solo Code.xcworkspace",
            localScheme: "Solo Code-Debug",
            releaseScheme: "Solo Code-Release",
            destination: "platform=macOS",
            testPlan: nil,
            codeFileGlobs: [],
            excludedCodePaths: [],
            securitySensitivePrefixes: [],
            testGroups: []
        )
    }
}
