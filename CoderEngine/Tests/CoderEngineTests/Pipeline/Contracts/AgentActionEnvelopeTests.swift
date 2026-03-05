import XCTest
@testable import CoderEngine

final class AgentActionEnvelopeTests: XCTestCase {

    // MARK: - Helpers

    private func makeEnvelope(
        agentName: String = "RefactorParser-coder",
        confidence: Double = 0.85,
        actions: [AgentAction]? = nil
    ) -> AgentActionEnvelope {
        AgentActionEnvelope(
            agentId: "agent_01",
            agentName: agentName,
            agentRole: .coder,
            jobId: "job_001",
            taskId: "T1",
            correlationId: "corr_01",
            actions: actions ?? [
                AgentAction(
                    type: .patchProposal,
                    file: "Sources/A.swift",
                    diff: "--- a\n+++ b\n@@ ...\n"
                )
            ],
            confidence: confidence
        )
    }

    // MARK: - Coding round-trip

    func testEnvelope_codingRoundTrip() throws {
        let envelope = makeEnvelope()
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(AgentActionEnvelope.self, from: data)
        XCTAssertEqual(envelope.agentId, decoded.agentId)
        XCTAssertEqual(envelope.agentName, decoded.agentName)
        XCTAssertEqual(envelope.agentRole, decoded.agentRole)
        XCTAssertEqual(envelope.actions.count, decoded.actions.count)
        XCTAssertEqual(envelope.confidence, decoded.confidence)
    }

    // MARK: - JSON key format

    func testEnvelope_jsonKeys() throws {
        let data = try JSONEncoder().encode(makeEnvelope())
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"agent_id\""))
        XCTAssertTrue(json.contains("\"agent_name\""))
        XCTAssertTrue(json.contains("\"agent_role\""))
        XCTAssertTrue(json.contains("\"job_id\""))
        XCTAssertTrue(json.contains("\"task_id\""))
        XCTAssertTrue(json.contains("\"correlation_id\""))
    }

    // MARK: - Validation

    func testEnvelope_validationPass() throws {
        XCTAssertNoThrow(try makeEnvelope().validate())
    }

    func testEnvelope_emptyAgentId_fails() {
        var env = makeEnvelope()
        env.agentId = ""
        XCTAssertThrowsError(try env.validate())
    }

    func testEnvelope_confidenceOutOfRange_fails() {
        let env = makeEnvelope(confidence: 1.5)
        XCTAssertThrowsError(try env.validate())
    }

    func testEnvelope_negativeConfidence_fails() {
        let env = makeEnvelope(confidence: -0.1)
        XCTAssertThrowsError(try env.validate())
    }

    func testEnvelope_emptyActions_fails() {
        let env = makeEnvelope(actions: [])
        XCTAssertThrowsError(try env.validate())
    }

    func testEnvelope_namingConventionViolation_fails() {
        let env = makeEnvelope(agentName: "NoHyphenHere")
        XCTAssertThrowsError(try env.validate()) { error in
            guard case PipelineValidationError.constraintViolation(let f, _, _) = error else {
                XCTFail("Wrong error type"); return
            }
            XCTAssertEqual(f, "agent_name")
        }
    }

    // MARK: - AgentAction types

    func testAgentAction_docUpdate() throws {
        let action = AgentAction(
            type: .docUpdate,
            file: "docs/API.md",
            diff: "some diff",
            docCategory: .apiReference
        )
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AgentAction.self, from: data)
        XCTAssertEqual(decoded.type, .docUpdate)
        XCTAssertEqual(decoded.docCategory, .apiReference)
    }

    func testAgentAction_docChangelog() throws {
        let action = AgentAction(
            type: .docChangelog,
            file: "CHANGELOG.md",
            scope: ["Sources/A.swift"],
            summary: "Refactored token logic"
        )
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AgentAction.self, from: data)
        XCTAssertEqual(decoded.type, .docChangelog)
        XCTAssertEqual(decoded.scope, ["Sources/A.swift"])
    }
}
