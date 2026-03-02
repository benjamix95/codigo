import XCTest
@testable import CoderEngine

final class MCPSessionManagerTests: XCTestCase {
    func testRequireUniqueServerMatchReturnsSingleMatch() throws {
        let server = makeServer(
            source: "manual",
            origin: "manual",
            path: "/tmp/a.json",
            name: "alpha"
        )
        let resolved = try MCPSessionManager.requireUniqueServerMatch(
            matches: [server],
            notFoundMessage: "not found",
            ambiguityLabel: "resource"
        )
        XCTAssertEqual(resolved.id, server.id)
    }

    func testRequireUniqueServerMatchThrowsUnavailableForEmptyMatches() {
        XCTAssertThrowsError(
            try MCPSessionManager.requireUniqueServerMatch(
                matches: [],
                notFoundMessage: "MCP resource not found: file://x",
                ambiguityLabel: "resource"
            )
        ) { error in
            guard case ToolRuntimeError.mcpUnavailable(let message) = error else {
                return XCTFail("Expected mcpUnavailable, got: \(error)")
            }
            XCTAssertTrue(message.contains("MCP resource not found"))
        }
    }

    func testRequireUniqueServerMatchThrowsValidationForAmbiguity() {
        let first = makeServer(
            source: "manual",
            origin: "manual",
            path: "/tmp/a.json",
            name: "alpha"
        )
        let second = makeServer(
            source: "manual",
            origin: "manual",
            path: "/tmp/b.json",
            name: "beta"
        )

        XCTAssertThrowsError(
            try MCPSessionManager.requireUniqueServerMatch(
                matches: [first, second],
                notFoundMessage: "unused",
                ambiguityLabel: "MCP prompt 'debug_template'"
            )
        ) { error in
            guard case ToolRuntimeError.validation(let message) = error else {
                return XCTFail("Expected validation, got: \(error)")
            }
            XCTAssertTrue(message.contains("Ambiguous MCP prompt 'debug_template'"))
            XCTAssertTrue(message.contains("alpha"))
            XCTAssertTrue(message.contains("beta"))
        }
    }

    func testCallToolRichRecordsMetrics() async throws {
        guard let binaryPath = locateCoderideMCPServerBinary() else {
            throw XCTSkip("coderide-mcp-server binary not found in .build")
        }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-rich-metrics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let server = makeServer(
            source: "test",
            origin: "manual",
            path: "/tmp/mcp-metrics.json",
            name: "coderide-metrics",
            command: binaryPath,
            args: ["--workspace", workspace.path]
        )
        let manager = MCPSessionManager(serverResolver: { [server] })
        defer {
            Task {
                await manager.shutdownAll()
            }
        }

        let result = try await manager.callToolRich(
            serverId: server.id,
            toolName: "coderide_todo_read",
            arguments: [:],
            timeoutMs: 10_000,
            idleTTLSeconds: 60
        )
        XCTAssertFalse(result.isError)

        let metrics = await manager.serverMetrics(serverId: server.id)
        XCTAssertEqual(metrics.count, 1)
        XCTAssertGreaterThanOrEqual(metrics[0].totalCalls, 1)
    }

    private func makeServer(
        source: String,
        origin: String,
        path: String,
        name: String,
        command: String = "/bin/echo",
        args: [String] = []
    ) -> MCPConfigLoader.DetectedServer {
        let identity = MCPServerIdentity.make(
            source: source,
            name: name,
            origin: origin,
            sourcePath: path
        )
        return MCPConfigLoader.DetectedServer(
            id: identity.stableIdentifier,
            identity: identity,
            legacyID: "\(source)-\(name)",
            name: name,
            command: command,
            args: args,
            env: [:],
            source: source
        )
    }

    private func locateCoderideMCPServerBinary() -> String? {
        let testsFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testsFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildDir = packageRoot.appendingPathComponent(".build", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: buildDir,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == "coderide-mcp-server" else { continue }
            if FileManager.default.isExecutableFile(atPath: fileURL.path) {
                return fileURL.path
            }
        }
        return nil
    }
}
