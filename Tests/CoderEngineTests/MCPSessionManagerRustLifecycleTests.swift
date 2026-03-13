import XCTest
@testable import CoderEngine

final class MCPSessionManagerRustLifecycleTests: XCTestCase {
    func testListToolsAndCallToolRichUseRustLifecycleBackend() async throws {
        guard let lifecycleBinaryPath = locateRustLifecycleBinary(named: "mcp-lifecycle-backend-rust"),
              let fakeServerBinaryPath = locateRustLifecycleBinary(named: "fake-mcp-server") else {
            throw XCTSkip("Rust lifecycle backend binaries not found")
        }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-rust-lifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let bootCountFile = workspace.appendingPathComponent("boot-count.txt")
        let server = makeServer(
            source: "test",
            origin: "manual",
            path: "/tmp/mcp-rust-lifecycle.json",
            name: "fake-mcp",
            command: fakeServerBinaryPath,
            args: [bootCountFile.path]
        )
        let manager = MCPSessionManager(
            serverResolver: { [server] },
            rustLifecycleBackend: MCPLifecycleRustBackend(
                binaryURL: URL(fileURLWithPath: lifecycleBinaryPath)
            )
        )
        defer {
            Task {
                await manager.shutdownAll()
            }
        }

        let tools = try await manager.listTools(serverId: server.id, idleTTLSeconds: 0)
        XCTAssertTrue(tools.contains(where: { $0.name == "echo" }))

        let echoed = try await manager.callToolRich(
            serverId: server.id,
            toolName: "echo",
            arguments: ["message": "ciao"],
            timeoutMs: 5_000,
            idleTTLSeconds: 0
        )
        XCTAssertEqual(echoed.content, "ciao")
        XCTAssertFalse(echoed.isError)

        let states = await manager.health(serverId: server.id)
        XCTAssertEqual(states[server.id], "ready")

        try await manager.restartServer(serverId: server.id)

        let bootCount = try await manager.callToolRich(
            serverId: server.id,
            toolName: "boot_count",
            arguments: [:],
            timeoutMs: 5_000,
            idleTTLSeconds: 0
        )
        XCTAssertEqual(bootCount.content, "2")
    }

    private func makeServer(
        source: String,
        origin: String,
        path: String,
        name: String,
        command: String,
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

    private func locateRustLifecycleBinary(named fileName: String) -> String? {
        let testsFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testsFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidateURLs = [
            packageRoot.appendingPathComponent("Native/target/debug/\(fileName)"),
            packageRoot.appendingPathComponent("Native/target/release/\(fileName)"),
            packageRoot.appendingPathComponent(".build/rust-mcp-lifecycle/debug/\(fileName)"),
            packageRoot.appendingPathComponent(".build/rust-mcp-lifecycle/release/\(fileName)")
        ]

        for candidate in candidateURLs where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }
}
