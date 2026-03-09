import XCTest
@testable import CoderEngine

final class ValidationOrchestratorTests: XCTestCase {
    func testStopsAtFirstFailure() async throws {
        let orchestrator = ValidationOrchestrator(
            configLoader: { _ in self.descriptor() },
            stageFactory: { _ in
                [
                    ValidationOrchestratorTestStage(id: .patchSafety, status: .passed),
                    ValidationOrchestratorTestStage(id: .build, status: .failed),
                    ValidationOrchestratorTestStage(id: .targetedTests, status: .passed),
                ]
            }
        )

        let result = try await orchestrator.run(
            context: ValidationContext(
                trigger: .gitCommit,
                workspaceRoot: URL(fileURLWithPath: NSTemporaryDirectory()),
                touchedFiles: ["Engine/CoderEngine/Sources/Pipeline/Foo.swift"]
            )
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.stageResults.count, 2)
        XCTAssertEqual(result.failure?.stage, .build)
    }

    private func descriptor() -> ProjectValidationDescriptor {
        ProjectValidationDescriptor(
            version: 1,
            workspace: "Solo Code.xcworkspace",
            localScheme: "Solo Code-Debug",
            releaseScheme: "Solo Code-Release",
            destination: "platform=macOS",
            testPlan: nil,
            codeFileGlobs: ["Engine/**/*.swift"],
            excludedCodePaths: [],
            securitySensitivePrefixes: [],
            testGroups: []
        )
    }
}

private struct ValidationOrchestratorTestStage: ValidationStage {
    let id: ValidationStageID
    let status: ValidationStageStatus

    func run(
        context: ValidationContext,
        profile: ValidationProfile,
        descriptor: ProjectValidationDescriptor
    ) async -> ValidationStageResult {
        ValidationStageResult(stage: id, status: status, summary: id.rawValue)
    }
}
