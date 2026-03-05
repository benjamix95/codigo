import XCTest
@testable import CoderEngine

final class CodexConfigLoaderTests: XCTestCase {
    func testParseReadsFastModeFromTopLevelConfig() {
        let parsed = CodexConfigLoader.parse(
            """
            sandbox_mode = "danger-full-access"
            fast_mode = true
            model = "gpt-5-codex"
            """
        )

        XCTAssertEqual(parsed.sandboxMode, "danger-full-access")
        XCTAssertEqual(parsed.fastMode, true)
        XCTAssertEqual(parsed.model, "gpt-5-codex")
    }

    func testSavePreservesUnknownKeysAndSections() throws {
        let directory = try makeTemporaryDirectory()
        let configPath = directory.appendingPathComponent("config.toml").path
        try """
        model = "gpt-5-codex"
        model_context_window = 1000000
        model_auto_compact_token_limit = 900000

        [sandbox_workspace_write]
        network_access = true

        [mcp_servers.coderide]
        command = "/tmp/coderide"
        args = [ "--workspace", "." ]
        """.write(toFile: configPath, atomically: true, encoding: .utf8)

        var updated = CodexConfigLoader.load(from: configPath)
        updated.model = "gpt-5.4"
        updated.fastMode = true
        CodexConfigLoader.save(updated, to: configPath)

        let saved = try String(contentsOfFile: configPath, encoding: .utf8)
        XCTAssertTrue(saved.contains("model = \"gpt-5.4\""))
        XCTAssertTrue(saved.contains("fast_mode = true"))
        XCTAssertTrue(saved.contains("model_context_window = 1000000"))
        XCTAssertTrue(saved.contains("model_auto_compact_token_limit = 900000"))
        XCTAssertTrue(saved.contains("[mcp_servers.coderide]"))
        XCTAssertTrue(saved.contains("command = \"/tmp/coderide\""))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("codex-config-loader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
