import XCTest
@testable import CoderEngine

final class DebugPipelineContractsTests: XCTestCase {
    func testDebugPipelineEnumsRoundTrip() throws {
        for phase in DebugPipelinePhase.allCases {
            let data = try JSONEncoder().encode(phase)
            let decoded = try JSONDecoder().decode(DebugPipelinePhase.self, from: data)
            XCTAssertEqual(phase, decoded)
        }

        for policy in DebugBackendPolicy.allCases {
            let data = try JSONEncoder().encode(policy)
            let decoded = try JSONDecoder().decode(DebugBackendPolicy.self, from: data)
            XCTAssertEqual(policy, decoded)
        }

        for stage in DebugStageKind.allCases {
            let data = try JSONEncoder().encode(stage)
            let decoded = try JSONDecoder().decode(DebugStageKind.self, from: data)
            XCTAssertEqual(stage, decoded)
        }
    }

    func testDebugStageDefaultsExposePipelineSemantics() {
        XCTAssertEqual(DebugStageKind.sessionStart.defaultPhase, .describing)
        XCTAssertEqual(DebugStageKind.sessionStart.defaultExecutionStyle, .mcpTool)
        XCTAssertNil(DebugStageKind.sessionStart.defaultAgentRole)

        XCTAssertEqual(DebugStageKind.gatherContext.defaultPhase, .describing)
        XCTAssertEqual(DebugStageKind.gatherContext.defaultExecutionStyle, .singleAgent)
        XCTAssertEqual(DebugStageKind.gatherContext.defaultAgentRole, .explorer)

        XCTAssertEqual(DebugStageKind.hypothesize.defaultPhase, .fixing)
        XCTAssertEqual(DebugStageKind.hypothesize.defaultAgentRole, .debugger)
        XCTAssertEqual(DebugStageKind.verify.defaultPhase, .verifying)
        XCTAssertEqual(DebugStageKind.verify.defaultAgentRole, .testWriter)
        XCTAssertEqual(DebugStageKind.timeline.defaultPhase, .resolved)

        XCTAssertTrue(DebugStageKind.nativeStepOver.isNativeStage)
        XCTAssertEqual(DebugStageKind.nativeStepOver.defaultExecutionStyle, .nativeCommand)
    }

    func testDebugPipelineSessionContextRoundTrip() throws {
        let session = DebugPipelineSessionContext(
            initialPhase: .reproducing,
            backendPolicy: .appleHybrid,
            errorSummary: "Crash on launch",
            targetPath: "/Applications/Codigo.app",
            arguments: ["--uitest"],
            workspaceHints: ["App/SoloCodeApp/Sources/Debug"],
            metadata: ["origin": "tests"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        let decoded = try JSONDecoder().decode(DebugPipelineSessionContext.self, from: data)
        XCTAssertEqual(session, decoded)
    }

    func testDebugPipelineSessionContextRejectsEmptyExplicitTargetPath() {
        let session = DebugPipelineSessionContext(targetPath: "   ")
        XCTAssertThrowsError(try session.validate())
    }
}
