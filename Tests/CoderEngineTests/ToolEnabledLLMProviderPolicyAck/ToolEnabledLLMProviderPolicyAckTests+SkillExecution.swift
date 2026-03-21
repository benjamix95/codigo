import Foundation
import XCTest
@testable import CoderEngine

extension ToolEnabledLLMProviderPolicyAckTests {
    final class SkillLiveEventProvider: LLMProvider, @unchecked Sendable {
        let id = "skill-live-event-provider"
        let displayName = "Skill Live Event Provider"

        func isAuthenticated() -> Bool { true }

        func send(
            prompt _: String,
            context _: WorkspaceContext,
            imageURLs _: [URL]?
        ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(.started)
                continuation.yield(.raw(type: "agent", payload: [
                    "title": "Inner agent event",
                    "detail": "forwarded",
                    "status": "running",
                    "swarm_id": "inner-swarm",
                    "group_id": "inner-group",
                ]))
                continuation.yield(.raw(type: "subagent_text", payload: [
                    "text": "Skill progress update",
                    "status": "running",
                    "swarm_id": "inner-swarm",
                    "group_id": "inner-group",
                ]))
                continuation.yield(.textDelta("Skill execution output"))
                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }

    func testExecuteSkillToolFailsFastWhenSubagentStreamStalls() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-timeout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let skillName = "test-skill-\(UUID().uuidString.lowercased())"
        let skillDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/skills")
            .appendingPathComponent(skillName)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let skillFile = skillDir.appendingPathComponent("SKILL.md")
        try "Inspect the repository and report findings.".write(
            to: skillFile,
            atomically: true,
            encoding: .utf8
        )

        let provider = ToolEnabledLLMProvider(
            base: TextOnlyProvider(),
            maxToolRounds: 1,
            subagentProviderFactory: { SilentSubagentProvider(delayMs: 2_000) }
        )

        let marker = CoderIDEMarker(
            kind: "tool_call_suggested",
            payload: [
                "id": "skill-timeout",
                "skill": skillName,
                "task": "Audit the code review pipeline.",
            ]
        )

        let events = try await withEnvironmentVariable("CODEX_SKILL_TIMEOUT_SECONDS", value: "1") {
            await provider.executeSkillTool(
                marker: marker,
                context: nonPolicyContext(workspace: workspace)
            )
        }

        let resultPayload = events.compactMap { event -> [String: String]? in
            guard case .raw(let type, let payload) = event, type == "tool_result" else {
                return nil
            }
            return payload
        }.last

        XCTAssertEqual(resultPayload?["status"], "failed")
        XCTAssertEqual(resultPayload?["name"], "skill")
        XCTAssertTrue(resultPayload?["detail"]?.contains("timed out after 1s") == true)
    }

    func testExecuteSkillToolPreservesLiveEventScopeWhileRewritingSkillSwarmIdentity() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-live-scope-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let skillName = "test-skill-live-\(UUID().uuidString.lowercased())"
        let skillDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/skills")
            .appendingPathComponent(skillName)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let skillFile = skillDir.appendingPathComponent("SKILL.md")
        try "Stream live events for regression coverage.".write(
            to: skillFile,
            atomically: true,
            encoding: .utf8
        )

        let provider = ToolEnabledLLMProvider(
            base: TextOnlyProvider(),
            maxToolRounds: 1,
            subagentProviderFactory: { SkillLiveEventProvider() }
        )

        let marker = CoderIDEMarker(
            kind: "tool_call_suggested",
            payload: [
                "id": "skill-live-call",
                "skill": skillName,
                "task": "Emit live events.",
                "conversation_id": "11111111-1111-1111-1111-111111111111",
            ]
        )

        let events = await provider.executeSkillTool(
            marker: marker,
            context: nonPolicyContext(workspace: workspace)
        )

        let startedPayload = try XCTUnwrap(events.compactMap { event -> [String: String]? in
            guard case .raw(let type, let payload) = event, type == "agent", payload["status"] == "started" else {
                return nil
            }
            return payload
        }.first)
        XCTAssertEqual(startedPayload["conversation_id"], "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(startedPayload["subagent_stage"], "launching_backend")
        let wrapperSwarmId = try XCTUnwrap(startedPayload["swarm_id"])
        let wrapperGroupId = try XCTUnwrap(startedPayload["group_id"])

        let forwardedAgentPayload = try XCTUnwrap(events.compactMap { event -> [String: String]? in
            guard case .raw(let type, let payload) = event, type == "agent", payload["title"] == "Inner agent event" else {
                return nil
            }
            return payload
        }.first)
        XCTAssertEqual(forwardedAgentPayload["tool_call_id"], "skill-live-call")
        XCTAssertEqual(
            forwardedAgentPayload["conversation_id"],
            "11111111-1111-1111-1111-111111111111"
        )
        XCTAssertEqual(forwardedAgentPayload["swarm_id"], wrapperSwarmId)
        XCTAssertEqual(forwardedAgentPayload["group_id"], wrapperGroupId)
        XCTAssertNotEqual(forwardedAgentPayload["swarm_id"], "inner-swarm")
        XCTAssertNotEqual(forwardedAgentPayload["group_id"], "inner-group")

        let forwardedTextPayload = try XCTUnwrap(events.compactMap { event -> [String: String]? in
            guard case .raw(let type, let payload) = event, type == "subagent_text" else {
                return nil
            }
            return payload
        }.first)
        XCTAssertEqual(forwardedTextPayload["tool_call_id"], "skill-live-call")
        XCTAssertEqual(
            forwardedTextPayload["conversation_id"],
            "11111111-1111-1111-1111-111111111111"
        )
        XCTAssertEqual(forwardedTextPayload["swarm_id"], wrapperSwarmId)
        XCTAssertEqual(forwardedTextPayload["group_id"], wrapperGroupId)

        let completedPayload = try XCTUnwrap(events.compactMap { event -> [String: String]? in
            guard case .raw(let type, let payload) = event, type == "agent", payload["status"] == "completed" else {
                return nil
            }
            return payload
        }.last)
        XCTAssertEqual(completedPayload["conversation_id"], "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(completedPayload["subagent_stage"], "completed")
        XCTAssertEqual(completedPayload["swarm_id"], wrapperSwarmId)
        XCTAssertEqual(completedPayload["group_id"], wrapperGroupId)
    }

    private func withEnvironmentVariable<T>(
        _ key: String,
        value: String,
        operation: () async throws -> T
    ) async rethrows -> T {
        let previous = getenv(key).map { String(cString: $0) }
        setenv(key, value, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        return try await operation()
    }
}
