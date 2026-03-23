import XCTest
@testable import CoderIDE

final class CodexCustomModelProfileSyncTests: XCTestCase {
    func testSyncManagedBlockCommentsPresetWhenDisabled() throws {
        let directory = try makeTemporaryDirectory()
        let configPath = directory.appendingPathComponent("config.toml").path
        try """
        model = "gpt-5.4"
        model_context_window = 1000000
        model_auto_compact_token_limit = 900000
        """.write(toFile: configPath, atomically: true, encoding: .utf8)

        CodexCustomModelProfileSync.syncManagedBlock(at: configPath, enabled: true)
        var saved = try String(contentsOfFile: configPath, encoding: .utf8)
        XCTAssertTrue(saved.contains("# solocode_codex_gpt54_1m_start"))
        XCTAssertTrue(saved.contains("model_context_window = 1000000"))
        XCTAssertTrue(saved.contains("model_auto_compact_token_limit = 900000"))

        CodexCustomModelProfileSync.syncManagedBlock(at: configPath, enabled: false)
        saved = try String(contentsOfFile: configPath, encoding: .utf8)
        XCTAssertTrue(saved.contains("# model_context_window = 1000000"))
        XCTAssertTrue(saved.contains("# model_auto_compact_token_limit = 900000"))
        XCTAssertFalse(saved.contains("\nmodel_context_window = 1000000\n"))
        XCTAssertFalse(saved.contains("\nmodel_auto_compact_token_limit = 900000\n"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("codex-custom-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
