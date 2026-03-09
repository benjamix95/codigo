import XCTest
@testable import CoderEngine

final class ValidationPerformanceTests: XCTestCase {
    func testSelectorPerformanceOnLargeFileList() {
        let descriptor = ProjectValidationDescriptor(
            version: 1,
            workspace: "Solo Code.xcworkspace",
            localScheme: "Solo Code-Debug",
            releaseScheme: "Solo Code-Release",
            destination: "platform=macOS",
            testPlan: nil,
            codeFileGlobs: ["Engine/**/*.swift"],
            excludedCodePaths: [],
            securitySensitivePrefixes: [],
            testGroups: [
                ValidationTestGroup(id: "engine-pipeline", bundle: "CoderEngineTests", pathPrefixes: ["Engine/CoderEngine/Sources/Pipeline/"], onlyTesting: ["CoderEngineTests/Pipeline"]),
            ]
        )
        let files = (0..<1000).map { "Engine/CoderEngine/Sources/Pipeline/File\($0).swift" }

        measure {
            _ = TargetedTestsSelector.select(files: files, descriptor: descriptor)
        }
    }
}
