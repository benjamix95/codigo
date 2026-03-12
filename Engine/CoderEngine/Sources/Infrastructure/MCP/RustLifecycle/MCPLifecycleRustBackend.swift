import Foundation

public actor MCPLifecycleRustBackend {
    private final class ManagedProcess {
        let process: Process
        let stdin: FileHandle
        let stdout: FileHandle
        var bufferedStdout = Data()

        init(process: Process, stdin: FileHandle, stdout: FileHandle) {
            self.process = process
            self.stdin = stdin
            self.stdout = stdout
        }
    }

    private var managedProcess: ManagedProcess?
    private var nextRequestID: UInt64 = 1
    private let binaryOverrideURL: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(binaryURL: URL? = nil) {
        self.binaryOverrideURL = binaryURL
    }

    func health(servers: [MCPConfigLoader.DetectedServer]) async throws -> [String: String] {
        let payload = try await request(
            op: "health",
            payload: ["servers": servers.map { MCPLifecycleRustServerConfig(server: $0).jsonObject }]
        ) as MCPLifecycleRustHealthPayload
        return payload.states
    }

    func listTools(server: MCPConfigLoader.DetectedServer) async throws -> [MCPToolDescriptor] {
        let payload = try await request(
            op: "list_tools",
            payload: ["server": MCPLifecycleRustServerConfig(server: server).jsonObject]
        ) as MCPLifecycleRustListToolsPayload
        return payload.tools.map { $0.asSessionToolDescriptor() }
    }

    func callTool(
        server: MCPConfigLoader.DetectedServer,
        toolName: String,
        arguments: [String: Any]
    ) async throws -> MCPLifecycleRustCallToolPayload {
        try await request(
            op: "call_tool",
            payload: [
                "server": MCPLifecycleRustServerConfig(server: server).jsonObject,
                "toolName": toolName,
                "arguments": arguments
            ]
        ) as MCPLifecycleRustCallToolPayload
    }

    func reconnect(server: MCPConfigLoader.DetectedServer) async throws {
        let _: MCPLifecycleRustServerActionPayload = try await request(
            op: "reconnect",
            payload: ["server": MCPLifecycleRustServerConfig(server: server).jsonObject]
        )
    }

    func restart(server: MCPConfigLoader.DetectedServer) async throws {
        let _: MCPLifecycleRustServerActionPayload = try await request(
            op: "restart_server",
            payload: ["server": MCPLifecycleRustServerConfig(server: server).jsonObject]
        )
    }

    func shutdownAll() async throws {
        let _: MCPLifecycleRustShutdownPayload = try await request(
            op: "shutdown_all",
            payload: [:]
        )
    }

    private func request<Response: Decodable>(
        op: String,
        payload: [String: Any]
    ) async throws -> Response {
        let process = try ensureProcess()
        let requestID = nextRequestID
        nextRequestID += 1

        let envelope: [String: Any] = [
            "id": String(requestID),
            "op": op,
            "payload": payload
        ]
        let encoded = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])

        do {
            try process.stdin.write(contentsOf: encoded)
            try process.stdin.write(contentsOf: Data([0x0A]))
            let responseObject = try readResponse(for: String(requestID), from: process)
            guard let ok = responseObject["ok"] as? Bool else {
                throw ToolRuntimeError.transport("MCPLifecycle backend returned malformed response")
            }
            if !ok {
                let message = responseObject["error"] as? String ?? "MCPLifecycle backend request failed"
                throw ToolRuntimeError.transport(message)
            }
            let payloadObject = responseObject["payload"] ?? [:]
            let payloadData = try JSONSerialization.data(withJSONObject: payloadObject, options: [.sortedKeys])
            return try decoder.decode(Response.self, from: payloadData)
        } catch {
            terminateBackendProcess()
            throw error
        }
    }

    private func ensureProcess() throws -> ManagedProcess {
        if let managedProcess, managedProcess.process.isRunning {
            return managedProcess
        }
        terminateBackendProcess()

        guard let binaryURL = binaryOverrideURL ?? MCPLifecycleRustBinaryLocator.resolveBinaryURL() else {
            throw ToolRuntimeError.transport("mcp-lifecycle-backend-rust non trovato")
        }

        let process = Process()
        process.executableURL = binaryURL
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()

        guard let stdin = (process.standardInput as? Pipe)?.fileHandleForWriting,
              let stdout = (process.standardOutput as? Pipe)?.fileHandleForReading else {
            throw ToolRuntimeError.transport("impossibile aprire gli stream del backend MCP Rust")
        }

        let managed = ManagedProcess(process: process, stdin: stdin, stdout: stdout)
        managedProcess = managed
        return managed
    }

    private func readResponse(
        for requestID: String,
        from process: ManagedProcess
    ) throws -> [String: Any] {
        while true {
            let line = try readLine(from: process)
            guard let data = line.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if object["id"] as? String != requestID {
                continue
            }
            return object
        }
    }

    private func readLine(from process: ManagedProcess) throws -> String {
        let newline = Data([0x0A])
        while true {
            if let range = process.bufferedStdout.range(of: newline) {
                let lineData = process.bufferedStdout.subdata(in: 0..<range.lowerBound)
                process.bufferedStdout.removeSubrange(0..<range.upperBound)
                return String(decoding: lineData, as: UTF8.self)
            }

            let chunk = try process.stdout.read(upToCount: 4096) ?? Data()
            if chunk.isEmpty {
                throw ToolRuntimeError.transport("mcp-lifecycle-backend-rust ha chiuso stdout")
            }
            process.bufferedStdout.append(chunk)
        }
    }

    private func terminateBackendProcess() {
        guard let managedProcess else { return }
        try? managedProcess.stdin.close()
        try? managedProcess.stdout.close()
        if managedProcess.process.isRunning {
            managedProcess.process.terminate()
            managedProcess.process.waitUntilExit()
        }
        self.managedProcess = nil
    }
}
