import Foundation
import XCTest
@testable import CoderEngine

final class CodexAppServerMCPWireIntegrationTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testHealthyStubReportsReadyAndExposesCoderideTools() throws {
        let codexPath = try requireCodexExecutable()
        let authSource = try requireCodexAuthFile()
        let tempRoot = try makeTemporaryDirectory(prefix: "codex-app-server-wire-ready")
        let workspace = CodexAppServerWireHarness.repoRoot(filePath: #filePath)
        let codexHome = tempRoot.appendingPathComponent("codex-home", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: authSource, to: codexHome.appendingPathComponent("auth.json"))

        let stub = try CodexAppServerWireHarness.writeHealthyStubServer(in: tempRoot)
        try CodexAppServerWireHarness.writeCodexConfig(at: codexHome, command: stub.path)

        let summary = try CodexAppServerWireHarness.runHarness(
            codexPath: codexPath,
            codexHome: codexHome,
            workspace: workspace,
            root: tempRoot
        )

        XCTAssertEqual(summary.startupStatus, "ready")
        XCTAssertNil(summary.startupError)
        XCTAssertTrue(summary.threadStarted, "thread/start deve riuscire con profilo autenticato")
        XCTAssertTrue(summary.toolNames.contains("coderide_read"))
        XCTAssertTrue(summary.toolNames.contains("coderide_grep"))
    }

    func testFailingStubReportsFailedAndLeavesToolCatalogEmpty() throws {
        let codexPath = try requireCodexExecutable()
        let authSource = try requireCodexAuthFile()
        let tempRoot = try makeTemporaryDirectory(prefix: "codex-app-server-wire-failed")
        let workspace = CodexAppServerWireHarness.repoRoot(filePath: #filePath)
        let codexHome = tempRoot.appendingPathComponent("codex-home", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: authSource, to: codexHome.appendingPathComponent("auth.json"))

        let stub = try CodexAppServerWireHarness.writeFailingStubServer(in: tempRoot)
        try CodexAppServerWireHarness.writeCodexConfig(at: codexHome, command: stub.path)

        let summary = try CodexAppServerWireHarness.runHarness(
            codexPath: codexPath,
            codexHome: codexHome,
            workspace: workspace,
            root: tempRoot
        )

        XCTAssertEqual(summary.startupStatus, "failed")
        XCTAssertTrue(summary.startupError?.contains("initialize response") == true)
        XCTAssertFalse(summary.threadStarted, "Con `required = true`, thread/start deve fallire quando il server MCP chiude l'handshake.")
        XCTAssertTrue(summary.toolNames.isEmpty)
    }

    private func requireCodexExecutable() throws -> String {
        guard let codexPath = CodexDetector.findCodexPath(customPath: nil) else {
            throw XCTSkip("Codex CLI non trovato")
        }
        return codexPath
    }

    private func requireCodexAuthFile() throws -> URL {
        let candidates = [
            URL(fileURLWithPath: "\(NSHomeDirectory())/.codex/auth.json"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/Solo Code/CLIProfiles/codex/_default/auth.json"),
        ]
        guard let auth = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("Auth Codex non disponibile per test app-server reale")
        }
        return auth
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }
}
