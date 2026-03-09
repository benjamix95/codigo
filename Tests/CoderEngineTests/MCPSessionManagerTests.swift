import XCTest
@testable import CoderEngine
import Darwin
import MCP

#if canImport(System)
import System
#else
@preconcurrency import SystemPackage
#endif

final class MCPSessionManagerTests: XCTestCase {
    func testMCPLogStoreWarnAliasUsesWarningThreshold() async {
        let store = MCPLogStore(maxEntries: 50)
        await store.append(MCPLogEntry(
            timestamp: .now,
            level: "info",
            message: "info",
            serverId: "s1",
            serverName: "Server 1",
            logger: nil
        ))
        await store.append(MCPLogEntry(
            timestamp: .now,
            level: "warning",
            message: "warning",
            serverId: "s1",
            serverName: "Server 1",
            logger: nil
        ))
        await store.append(MCPLogEntry(
            timestamp: .now,
            level: "error",
            message: "error",
            serverId: "s1",
            serverName: "Server 1",
            logger: nil
        ))

        let filtered = await store.logs(severity: "warn", limit: 10)
        let levels = Set(filtered.map(\.level))

        XCTAssertEqual(levels, Set(["warning", "error"]))
        XCTAssertFalse(levels.contains("info"))
    }

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

    func testSubagentExplorerToolReturnsImmediateAck() async throws {
        guard let binaryPath = locateCoderideMCPServerBinary() else {
            throw XCTSkip("coderide-mcp-server binary not found in .build")
        }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-subagent-ack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let server = makeServer(
            source: "test",
            origin: "manual",
            path: "/tmp/mcp-subagent-ack.json",
            name: "coderide-subagent-ack",
            command: binaryPath,
            args: ["--workspace", workspace.path]
        )
        let manager = MCPSessionManager(serverResolver: { [server] })
        defer {
            Task {
                await manager.shutdownAll()
            }
        }

        let startedAt = Date()
        let result = try await manager.callToolRich(
            serverId: server.id,
            toolName: "coderide_subagent_explorer",
            arguments: ["task": "Inspect the review chat pipeline"],
            timeoutMs: 3_000,
            idleTTLSeconds: 60
        )
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)

        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.content, "OK — subagent Explorer launched")
        XCTAssertLessThan(elapsedMs, 3_000, "Subagent MCP tools should acknowledge before the client timeout")
    }

    func testReconnectClearsNativeToolRegistry() async throws {
        guard let binaryPath = locateCoderideMCPServerBinary() else {
            throw XCTSkip("coderide-mcp-server binary not found in .build")
        }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-reconnect-registry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let server = makeServer(
            source: "test",
            origin: "manual",
            path: "/tmp/mcp-reconnect-registry.json",
            name: "coderide",
            command: binaryPath,
            args: ["--workspace", workspace.path]
        )
        let manager = MCPSessionManager(serverResolver: { [server] })
        defer {
            Task {
                await manager.shutdownAll()
                MCPNativeToolRegistry.shared.clear()
            }
        }

        _ = try await manager.listTools(serverId: server.id, idleTTLSeconds: 0)

        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        XCTAssertTrue(registry.register(tools: [
            MCPToolDescriptor(
                name: "coderide_subagent_explorer",
                description: "stale",
                schema: #"{"type":"object","properties":{}}"#,
                serverId: server.id,
                serverName: server.name
            )
        ]))
        XCTAssertTrue(registry.hasTools())

        try await manager.reconnect(serverId: server.id)
        XCTAssertFalse(registry.hasTools())
    }

    func testRestartServerClearsNativeToolRegistry() async throws {
        guard let binaryPath = locateCoderideMCPServerBinary() else {
            throw XCTSkip("coderide-mcp-server binary not found in .build")
        }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-restart-registry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let server = makeServer(
            source: "test",
            origin: "manual",
            path: "/tmp/mcp-restart-registry.json",
            name: "coderide",
            command: binaryPath,
            args: ["--workspace", workspace.path]
        )
        let manager = MCPSessionManager(serverResolver: { [server] })
        defer {
            Task {
                await manager.shutdownAll()
                MCPNativeToolRegistry.shared.clear()
            }
        }

        _ = try await manager.listTools(serverId: server.id, idleTTLSeconds: 0)

        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        XCTAssertTrue(registry.register(tools: [
            MCPToolDescriptor(
                name: "coderide_subagent_explorer",
                description: "stale",
                schema: #"{"type":"object","properties":{}}"#,
                serverId: server.id,
                serverName: server.name
            )
        ]))
        XCTAssertTrue(registry.hasTools())

        try await manager.restartServer(serverId: server.id)
        XCTAssertFalse(registry.hasTools())
    }

    func testResetSessionTerminatesSpawnedProcess() async throws {
        guard let binaryPath = locateCoderideMCPServerBinary() else {
            throw XCTSkip("coderide-mcp-server binary not found in .build")
        }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-reset-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let server = makeServer(
            source: "test",
            origin: "manual",
            path: "/tmp/mcp-reset-process.json",
            name: "coderide-reset-process",
            command: binaryPath,
            args: ["--workspace", workspace.path]
        )
        let manager = MCPSessionManager(serverResolver: { [server] })
        defer {
            Task {
                await manager.shutdownAll()
            }
        }

        let session = try await manager.session(for: server)
        let pid = session.process.processIdentifier
        XCTAssertTrue(Self.processExists(pid))

        try await manager.resetSession(server.id)
        try await Self.assertProcessEventuallyExits(pid)
    }

    func testSessionReconnectDisposesTransportResourcesForExitedSession() async throws {
        let server = makeServer(
            source: "test",
            origin: "manual",
            path: "/tmp/mcp-stale-session.json",
            name: "stale-session-server",
            command: "/definitely/missing/mcp-binary"
        )
        let manager = MCPSessionManager(serverResolver: { [server] })

        let (inputRead, inputWrite) = try FileDescriptor.pipe()
        let (outputRead, outputWrite) = try FileDescriptor.pipe()
        let stderrPipe = Pipe()

        let staleProcess = Process()
        staleProcess.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try staleProcess.run()
        staleProcess.waitUntilExit()

        let staleSession = MCPServerSession(
            serverId: server.id,
            serverName: server.name,
            client: Client(
                name: "stale-session-test-client",
                version: "1.0.0",
                configuration: .default
            ),
            transport: StdioTransport(input: inputRead, output: outputWrite),
            process: staleProcess,
            transportResources: MCPTransportResources(
                input: inputRead,
                output: outputWrite,
                stderrReadHandle: stderrPipe.fileHandleForReading
            ),
            lastUsedAt: Date(timeIntervalSince1970: 0),
            cachedTools: [],
            cachedToolsTimestamp: nil
        )

        let inputFD = inputRead.rawValue
        let outputFD = outputWrite.rawValue
        let stderrFD = stderrPipe.fileHandleForReading.fileDescriptor

        await manager._insertTestSession(staleSession)

        do {
            _ = try await manager.session(for: server)
            XCTFail("Expected reconnect to fail for missing executable")
        } catch {}

        XCTAssertTrue(Self.descriptorIsClosed(inputFD))
        XCTAssertTrue(Self.descriptorIsClosed(outputFD))
        XCTAssertTrue(Self.descriptorIsClosed(stderrFD))
        let hasSession = await manager._hasSession(server.id)
        XCTAssertFalse(hasSession)

        try? inputWrite.close()
        try? outputRead.close()
        try? stderrPipe.fileHandleForWriting.close()
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

    private static func processExists(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno != ESRCH
    }

    private static func assertProcessEventuallyExits(
        _ pid: Int32,
        timeoutMs: UInt64 = 2_000
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + (timeoutMs * 1_000_000)
        while processExists(pid) && DispatchTime.now().uptimeNanoseconds < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(processExists(pid), "Expected process \(pid) to exit after session reset")
    }

    private static func descriptorIsClosed(_ descriptor: Int32) -> Bool {
        errno = 0
        return fcntl(descriptor, F_GETFD) == -1 && errno == EBADF
    }

}

private extension MCPSessionManager {
    func _insertTestSession(_ session: MCPServerSession) {
        sessions[session.serverId] = session
    }

    func _hasSession(_ serverId: String) -> Bool {
        sessions[serverId] != nil
    }
}
