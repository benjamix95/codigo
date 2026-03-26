import XCTest
@testable import CoderEngine

final class DebugPipelineGateContractsTests: XCTestCase {

    // MARK: - Gate Stage Kinds Roundtrip

    func testGateStageKindsRoundTrip() throws {
        let gateStages: [DebugStageKind] = [.awaitReproduceGate, .awaitFixGate]
        for stage in gateStages {
            let data = try JSONEncoder().encode(stage)
            let decoded = try JSONDecoder().decode(DebugStageKind.self, from: data)
            XCTAssertEqual(stage, decoded, "Gate stage \(stage) should round-trip through JSON")
        }
    }

    // MARK: - Gate Stage Default Properties

    func testAwaitReproduceGateDefaults() {
        XCTAssertEqual(DebugStageKind.awaitReproduceGate.defaultPhase, .reproducing)
        XCTAssertEqual(DebugStageKind.awaitReproduceGate.defaultExecutionStyle, .mcpTool)
        XCTAssertNil(DebugStageKind.awaitReproduceGate.defaultAgentRole)
        XCTAssertFalse(DebugStageKind.awaitReproduceGate.isNativeStage)
    }

    func testAwaitFixGateDefaults() {
        XCTAssertEqual(DebugStageKind.awaitFixGate.defaultPhase, .verifying)
        XCTAssertEqual(DebugStageKind.awaitFixGate.defaultExecutionStyle, .mcpTool)
        XCTAssertNil(DebugStageKind.awaitFixGate.defaultAgentRole)
        XCTAssertFalse(DebugStageKind.awaitFixGate.isNativeStage)
    }

    func testHostReproduceGateAckDefaults() {
        XCTAssertEqual(DebugStageKind.hostReproduceGateAck.defaultPhase, .reproducing)
        XCTAssertEqual(DebugStageKind.hostReproduceGateAck.defaultExecutionStyle, .mcpTool)
        XCTAssertNil(DebugStageKind.hostReproduceGateAck.defaultAgentRole)
        XCTAssertFalse(DebugStageKind.hostReproduceGateAck.isNativeStage)
    }

    // MARK: - All Cases Includes Gates

    func testAllCasesIncludesGateStages() {
        let allCases = DebugStageKind.allCases
        XCTAssertTrue(allCases.contains(.awaitReproduceGate))
        XCTAssertTrue(allCases.contains(.awaitFixGate))
        XCTAssertTrue(allCases.contains(.hostReproduceGateAck))
    }

    // MARK: - Full Enum Roundtrip Still Works

    func testAllDebugStageKindsStillRoundTrip() throws {
        for stage in DebugStageKind.allCases {
            let data = try JSONEncoder().encode(stage)
            let decoded = try JSONDecoder().decode(DebugStageKind.self, from: data)
            XCTAssertEqual(stage, decoded, "Stage \(stage) should round-trip")
        }
    }
}
