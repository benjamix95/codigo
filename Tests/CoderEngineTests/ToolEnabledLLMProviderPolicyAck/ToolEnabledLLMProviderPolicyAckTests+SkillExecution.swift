import Foundation
import XCTest
@testable import CoderEngine

extension ToolEnabledLLMProviderPolicyAckTests {
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
                context: WorkspaceContext(workspacePath: workspace)
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
