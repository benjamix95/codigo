import XCTest
@testable import CoderEngine

final class TargetedTestsSelectorTests: XCTestCase {
    func testSelectorMapsPipelineAndCodeReviewPaths() {
        let groups = TargetedTestsSelector.select(
            files: [
                "Engine/CoderEngine/Sources/Pipeline/Patching/PatchApplyTransaction.swift",
                "Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/ReviewPipelineCoordinator.swift",
                "Engine/CoderEngine/Sources/AgentPipeline/Bridge/PipelineFacade.swift",
            ],
            descriptor: makeDescriptor()
        )

        XCTAssertEqual(groups.map(\.id), ["engine-pipeline", "engine-code-review"])
    }

    func testSelectorMapsGitRuntimeAndToolsPaths() {
        let groups = TargetedTestsSelector.select(
            files: [
                "App/SoloCodeApp/Sources/Git/Services/GitService+Commits.swift",
                "App/SoloCodeApp/Sources/Chat/Support/PipelineRuntime/PipelineIntegrationService.swift",
                "Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+PatchWorkflow.swift",
            ],
            descriptor: makeDescriptor()
        )

        XCTAssertEqual(groups.map(\.id), ["engine-tools", "app-git", "app-runtime"])
    }

    func testSelectorFallsBackToBundleWhenPathIsAmbiguous() {
        let groups = TargetedTestsSelector.select(
            files: ["App/SoloCodeApp/Sources/Unknown/Foo.swift"],
            descriptor: makeDescriptor()
        )

        XCTAssertEqual(groups.map(\.bundle), ["SoloCodeAppTests"])
    }

    private func makeDescriptor() -> ProjectValidationDescriptor {
        ProjectValidationDescriptor(
            version: 1,
            workspace: "Solo Code.xcworkspace",
            localScheme: "Solo Code-Debug",
            releaseScheme: "Solo Code-Release",
            destination: "platform=macOS",
            testPlan: nil,
            codeFileGlobs: ["App/**/*.swift", "Engine/**/*.swift", "Tools/**/*.swift"],
            excludedCodePaths: [],
            securitySensitivePrefixes: [],
            testGroups: [
                ValidationTestGroup(id: "engine-pipeline", bundle: "CoderEngineTests", pathPrefixes: ["Engine/CoderEngine/Sources/Pipeline/", "Engine/CoderEngine/Sources/AgentPipeline/"], onlyTesting: ["CoderEngineTests/Pipeline"]),
                ValidationTestGroup(id: "engine-code-review", bundle: "CoderEngineTests", pathPrefixes: ["Engine/CoderEngine/Sources/CodeReview/"], onlyTesting: ["CoderEngineTests/CodeReview"]),
                ValidationTestGroup(id: "engine-tools", bundle: "CoderEngineTests", pathPrefixes: ["Tools/CoderIDEMCPServer/Sources/"], onlyTesting: ["CoderEngineTests/UnifiedToolRuntime"]),
                ValidationTestGroup(id: "app-git", bundle: "SoloCodeAppTests", pathPrefixes: ["App/SoloCodeApp/Sources/Git/"], onlyTesting: ["SoloCodeAppTests/GitServiceTests"]),
                ValidationTestGroup(id: "app-runtime", bundle: "SoloCodeAppTests", pathPrefixes: ["App/SoloCodeApp/Sources/Runtime/", "App/SoloCodeApp/Sources/Chat/Support/PipelineRuntime/"], onlyTesting: ["SoloCodeAppTests/PipelineIntegrationServiceTests"]),
            ]
        )
    }
}
