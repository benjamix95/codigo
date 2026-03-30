import Foundation
import XCTest
@testable import CoderEngine
import Darwin

final class InstructionPolicyBundleTests: XCTestCase {
    func testPolicyRefDefaultsToPolicyHash() {
        let bundle = InstructionPolicyBundle(
            policyText: "body",
            policyHash: "abc123",
            requiredAckMarker: "policy_ack hash=abc123"
        )

        XCTAssertEqual(bundle.policyRef, "abc123")
    }

    func testHashForPolicyIsDeterministic() {
        let text = "line1\nline2\nline3"
        let h1 = InstructionPolicyBundle.hashForPolicy(text)
        let h2 = InstructionPolicyBundle.hashForPolicy(text)

        XCTAssertEqual(h1, h2)
        XCTAssertEqual(h1.count, 64)
    }

    func testLoadBuildsAckMarkerWhenPolicyExists() throws {
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("instruction-policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let agents = tmpRoot.appendingPathComponent("AGENTS.md")
        try "Parla italiano".write(to: agents, atomically: true, encoding: .utf8)

        let bundle = InstructionPolicyBundle.load(workspacePaths: [tmpRoot.path])
        XCTAssertTrue(bundle.hasPolicy)
        XCTAssertFalse(bundle.policyHash.isEmpty)
        XCTAssertEqual(bundle.requiredAckMarker, "policy_ack hash=\(bundle.policyHash)")
        XCTAssertTrue(bundle.policyText.contains("policy_ack"))
        XCTAssertTrue(bundle.policyText.contains("Do this silently and directly"))
    }

    func testLoadUsesCodexHomeOverrideForGlobalAgentsPath() throws {
        let codexHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("instruction-policy-codex-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: codexHome) }

        let globalAgents = codexHome.appendingPathComponent("AGENTS.md")
        try "global-override-content".write(to: globalAgents, atomically: true, encoding: .utf8)

        withEnvironmentVariable("CODEX_HOME", value: codexHome.path) {
            InstructionPolicyBundle.invalidateCache()
            let bundle = InstructionPolicyBundle.load(workspacePaths: [])
            XCTAssertTrue(bundle.policyText.contains("global-override-content"))
        }
    }

    func testInvalidateCacheForcesImmediatePolicyReload() throws {
        let codexHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("instruction-policy-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: codexHome) }

        let agents = codexHome.appendingPathComponent("AGENTS.md")
        try "version-one".write(to: agents, atomically: true, encoding: .utf8)

        try withEnvironmentVariable("CODEX_HOME", value: codexHome.path) {
            InstructionPolicyBundle.invalidateCache()
            let first = InstructionPolicyBundle.load(workspacePaths: [])
            XCTAssertTrue(first.policyText.contains("version-one"))

            try "version-two".write(to: agents, atomically: true, encoding: .utf8)
            let cachedSecond = InstructionPolicyBundle.load(workspacePaths: [])
            XCTAssertEqual(cachedSecond.policyHash, first.policyHash)

            InstructionPolicyBundle.invalidateCache()
            let reloaded = InstructionPolicyBundle.load(workspacePaths: [])
            XCTAssertTrue(reloaded.policyText.contains("version-two"))
            XCTAssertNotEqual(reloaded.policyHash, first.policyHash)
        }
    }

    func testLoadIgnoresProjectPoliciesOutsideWorkspaceRoot() throws {
        let parentRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("instruction-policy-parent-\(UUID().uuidString)")
        let workspace = parentRoot.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parentRoot) }

        let parentAgents = parentRoot.appendingPathComponent("AGENTS.md")
        try "outside-workspace-policy".write(to: parentAgents, atomically: true, encoding: .utf8)

        InstructionPolicyBundle.invalidateCache()
        let bundle = InstructionPolicyBundle.load(workspacePaths: [workspace.path])
        XCTAssertFalse(bundle.policyText.contains("outside-workspace-policy"))
    }

    func testLoadRejectsSymlinkedProjectPolicyFile() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("instruction-policy-symlink-\(UUID().uuidString)")
        let workspace = tempRoot.appendingPathComponent("workspace")
        let secretFile = tempRoot.appendingPathComponent("secret.txt")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try "do-not-leak".write(to: secretFile, atomically: true, encoding: .utf8)
        let agentsPath = workspace.appendingPathComponent("AGENTS.md").path
        XCTAssertEqual(symlink(secretFile.path, agentsPath), 0)

        InstructionPolicyBundle.invalidateCache()
        let bundle = InstructionPolicyBundle.load(workspacePaths: [workspace.path])
        XCTAssertFalse(bundle.policyText.contains("do-not-leak"))
    }

    func testWorkspaceContextUsesProvidedInstructionPolicyBundle() throws {
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("instruction-policy-context-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let bundle = InstructionPolicyBundle(
            policyText: "## Injected policy\nbody",
            policyHash: "hash-from-bundle",
            policyRef: "policy-ref-from-bundle",
            requiredAckMarker: "policy_ack hash=hash-from-bundle"
        )

        let context = WorkspaceContext(
            workspacePath: workspace,
            instructionPolicyBundle: bundle
        )

        XCTAssertTrue(context.contextPrompt().contains("## Injected policy"))
        XCTAssertEqual(context.requiredInstructionPolicyHash, "hash-from-bundle")
        XCTAssertEqual(context.instructionPolicyRef, "policy-ref-from-bundle")
        XCTAssertEqual(
            context.instructionPolicySessionDescriptor,
            InstructionPolicySessionDescriptor(
                policyRef: "policy-ref-from-bundle",
                policyHash: "hash-from-bundle",
                shouldReinjectPolicyText: true
            )
        )
    }


    func testSkillContentRejectsPathTraversalName() throws {
        let home = NSHomeDirectory()
        let skillsRoot = URL(fileURLWithPath: home).appendingPathComponent(".codex/skills")
        try FileManager.default.createDirectory(at: skillsRoot, withIntermediateDirectories: true)

        let escapedSkill = URL(fileURLWithPath: home)
            .appendingPathComponent("skill-escape-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: escapedSkill, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: escapedSkill) }

        let escapedSkillFile = escapedSkill.appendingPathComponent("SKILL.md")
        try "top-secret".write(to: escapedSkillFile, atomically: true, encoding: .utf8)

        XCTAssertNil(InstructionPolicyBundle.skillContent(for: "../../\(escapedSkill.lastPathComponent)"))
    }

    func testSkillContentLoadsValidLocalSkill() throws {
        let home = NSHomeDirectory()
        let skillName = "test-skill-\(UUID().uuidString.lowercased())"
        let skillDir = URL(fileURLWithPath: home)
            .appendingPathComponent(".codex/skills")
            .appendingPathComponent(skillName)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let skillFile = skillDir.appendingPathComponent("SKILL.md")
        try """
        ---
        name: test
        ---
        body-content
        """.write(to: skillFile, atomically: true, encoding: .utf8)

        XCTAssertEqual(InstructionPolicyBundle.skillContent(for: skillName), "body-content")
    }
    private func withEnvironmentVariable(_ key: String, value: String, operation: () throws -> Void) rethrows {
        let previous = getenv(key).map { String(cString: $0) }
        setenv(key, value, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        try operation()
    }
}
