import Foundation
import XCTest
@testable import CoderEngine

final class ToolEnabledLLMProviderMCPWarmupTests: XCTestCase {
    func testSendPrewarmsCoderideToolsBeforeBuildingPrompt() async throws {
        guard let binaryPath = locateCoderideMCPServerBinary() else {
            throw XCTSkip("coderide-mcp-server-rust binary not found in .build")
        }

        let workspace = try makeTemporaryDirectory(prefix: "mcp-warmup-good")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let server = makeServer(
            source: "test",
            origin: "manual",
            path: "/tmp/mcp-warmup-good.json",
            name: "coderide",
            command: binaryPath,
            args: ["--workspace", workspace.path]
        )

        let manager = MCPSessionManager(serverResolver: { [server] })
        let runtime = UnifiedToolRuntime(mcpSessions: manager, workspacePaths: [workspace])
        let base = PromptCaptureProvider(responseText: "Warmup OK")
        let provider = ToolEnabledLLMProvider(base: base, runtime: runtime, maxToolRounds: 1)

        MCPNativeToolRegistry.shared.clear()
        defer {
            MCPNativeToolRegistry.shared.clear()
            Task {
                await manager.shutdownAll()
            }
        }

        let stream = try await provider.send(
            prompt: "Leggi un file e poi rispondi",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )
        _ = try await collectEvents(from: stream)

        let capturedPrompt = base.lastPrompt
        XCTAssertNotNil(capturedPrompt)
        XCTAssertTrue(
            capturedPrompt?.contains("coderide_read") == true,
            "Il prompt iniziale deve includere i tool MCP coderide registrati nativamente."
        )
    }

    func testSendDoesNotBlockWhenBackgroundMCPDiscoveryHangs() async throws {
        let workspace = try makeTemporaryDirectory(prefix: "mcp-warmup-hang")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let hangingScript = try makeTemporaryExecutable(
            named: "hanging-mcp-server.sh",
            contents: "#!/bin/sh\nsleep 3\n"
        )

        let server = makeServer(
            source: "test",
            origin: "manual",
            path: "/tmp/mcp-warmup-hang.json",
            name: "stuck-external",
            command: hangingScript.path
        )

        let manager = MCPSessionManager(serverResolver: { [server] })
        let runtime = UnifiedToolRuntime(mcpSessions: manager, workspacePaths: [workspace])
        let base = PromptCaptureProvider(responseText: "Prompt still sent")
        let provider = ToolEnabledLLMProvider(base: base, runtime: runtime, maxToolRounds: 1)

        MCPNativeToolRegistry.shared.clear()
        defer {
            MCPNativeToolRegistry.shared.clear()
            Task {
                await manager.shutdownAll()
            }
        }

        let startedAt = Date()
        let stream = try await provider.send(
            prompt: "Rispondi subito",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )
        let events = try await collectEvents(from: stream)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(
            elapsed,
            1.5,
            "La pipeline non deve attendere la discovery MCP globale prima di restituire lo stream."
        )
        XCTAssertTrue(base.lastPrompt?.contains("Rispondi subito") == true)
        let sawExpectedText = events.contains { event in
            if case .textDelta("Prompt still sent") = event {
                return true
            }
            return false
        }
        XCTAssertTrue(sawExpectedText)
    }

    private func collectEvents(
        from stream: AsyncThrowingStream<StreamEvent, Error>
    ) async throws -> [StreamEvent] {
        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
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
            guard fileURL.lastPathComponent == "coderide-mcp-server-rust" else { continue }
            if FileManager.default.isExecutableFile(atPath: fileURL.path) {
                return fileURL.path
            }
        }
        return nil
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeTemporaryExecutable(
        named fileName: String,
        contents: String
    ) throws -> URL {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(fileName)")
        try contents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }
}

private final class PromptCaptureProvider: LLMProvider, @unchecked Sendable {
    let id = "prompt-capture-provider"
    let displayName = "Prompt Capture Provider"

    private let responseText: String
    private let lock = NSLock()
    private var capturedPrompt: String?

    init(responseText: String) {
        self.responseText = responseText
    }

    var lastPrompt: String? {
        lock.withLock { capturedPrompt }
    }

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context _: WorkspaceContext,
        imageURLs _: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        lock.withLock {
            capturedPrompt = prompt
        }

        return AsyncThrowingStream { continuation in
            continuation.yield(.started)
            continuation.yield(.textDelta(responseText))
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}
