import XCTest
@testable import CoderIDE
import CoderEngine
import Darwin

final class CLIProfileProvisionerInstructionSyncTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testSyncAgentsContentWritesManagedAndGlobalTargets() throws {
        let root = try makeTemporaryDirectory(prefix: "agents-sync-root")
        let managedRoot = root.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createDirectory(at: managedRoot, withIntermediateDirectories: true)

        let codexProfile = managedRoot.appendingPathComponent("codex/acc-1", isDirectory: true)
        let claudeProfile = managedRoot.appendingPathComponent("claude/acc-2", isDirectory: true)
        let geminiProfile = managedRoot.appendingPathComponent("gemini/acc-3", isDirectory: true)
        try FileManager.default.createDirectory(at: codexProfile, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeProfile, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: geminiProfile, withIntermediateDirectories: true)

        let codexGlobal = root.appendingPathComponent("global/codex", isDirectory: true)
        let claudeGlobal = root.appendingPathComponent("global/claude", isDirectory: true)
        let geminiGlobal = root.appendingPathComponent("global/gemini", isDirectory: true)

        let content = "custom-agents-content"
        let report = CLIProfileProvisioner.syncAgentsContentToManagedAndGlobalProfiles(
            content,
            managedProfilesRoot: managedRoot,
            codexGlobalDirectory: codexGlobal,
            claudeGlobalDirectory: claudeGlobal,
            geminiGlobalDirectory: geminiGlobal
        )

        XCTAssertTrue(report.failedPaths.isEmpty)
        XCTAssertFalse(report.writtenPaths.isEmpty)

        XCTAssertEqual(try read(codexProfile.appendingPathComponent("AGENTS.md")), content)
        XCTAssertEqual(try read(codexProfile.appendingPathComponent("instructions.md")), content)
        XCTAssertEqual(try read(claudeProfile.appendingPathComponent("AGENTS.md")), content)
        XCTAssertEqual(try read(claudeProfile.appendingPathComponent(".claude/CLAUDE.md")), content)
        XCTAssertEqual(try read(geminiProfile.appendingPathComponent("AGENTS.md")), content)

        XCTAssertEqual(try read(codexGlobal.appendingPathComponent("AGENTS.md")), content)
        XCTAssertEqual(try read(codexGlobal.appendingPathComponent("instructions.md")), content)
        XCTAssertEqual(try read(claudeGlobal.appendingPathComponent("AGENTS.md")), content)
        XCTAssertEqual(try read(claudeGlobal.appendingPathComponent("CLAUDE.md")), content)
        XCTAssertEqual(try read(geminiGlobal.appendingPathComponent("AGENTS.md")), content)
    }

    func testEffectiveAgentsContentUsesGlobalFileWhenPresent() throws {
        let codexHome = try makeTemporaryDirectory(prefix: "agents-sync-codex-home")
        let agents = codexHome.appendingPathComponent("AGENTS.md")
        try "from-global-file".write(to: agents, atomically: true, encoding: .utf8)

        withEnvironmentVariable("CODEX_HOME", value: codexHome.path) {
            XCTAssertEqual(CLIProfileProvisioner.effectiveAgentsContent(), "from-global-file")
        }
    }

    func testEffectiveAgentsContentFallsBackToTemplateWhenMissing() throws {
        let codexHome = try makeTemporaryDirectory(prefix: "agents-sync-empty-codex-home")

        withEnvironmentVariable("CODEX_HOME", value: codexHome.path) {
            XCTAssertEqual(
                CLIProfileProvisioner.effectiveAgentsContent(),
                CLIProfileProvisioner.codexInstructionsTemplate
            )
        }
    }

    func testCodexInstructionsTemplateIncludesUpdatedTodoWorkflowGuardrails() {
        let template = CLIProfileProvisioner.codexInstructionsTemplate

        XCTAssertTrue(template.contains("TODO WORKFLOW (USE ONLY WHEN TRULY NEEDED)"))
        XCTAssertTrue(template.contains("If the task is simple (single action or <=2 concrete operations), do NOT emit todo markers."))
        XCTAssertTrue(template.contains("never placeholder items like \"Task\", \"Analysis\", \"Step 1\", or \"Todo update\""))
        XCTAssertTrue(template.contains("Emit the first `coderide_todo_write` update BEFORE the first command/edit/tool action"))
        XCTAssertTrue(template.contains("Use `coderide_todo_read` only for resume/reconciliation, never as the default first action."))
        XCTAssertTrue(template.contains("`subagent_reviewer`"))
        XCTAssertTrue(template.contains("`subagent_testWriter`"))
        XCTAssertTrue(template.contains("If the context includes `[CODERIDE:policy_ack|hash=...]`, emit it once before any operational tool action."))
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
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
