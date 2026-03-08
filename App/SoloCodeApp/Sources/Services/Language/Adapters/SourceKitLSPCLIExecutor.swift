import Foundation

struct SourceKitLSPRequest: Sendable {
    let method: String
    let paramsJSON: Data
    let workspaceRootPath: String?
    let openDocuments: [SourceKitOpenDocument]
}

struct SourceKitOpenDocument: Sendable {
    let filePath: String
    let languageId: String
    let text: String
}

protocol SourceKitLSPRequestExecuting: Sendable {
    func execute(executablePath: String, request: SourceKitLSPRequest) async throws -> Data
}

actor SourceKitLSPCLIExecutor: SourceKitLSPRequestExecuting {
    private let timeoutNanoseconds: UInt64 = 8_000_000_000

    func execute(executablePath: String, request: SourceKitLSPRequest) async throws -> Data {
        try await ensureBinaryReachable(executablePath: executablePath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executablePath]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw LanguageServiceError.unsupported("Unable to start '\(executablePath)': \(error.localizedDescription)")
        }

        let stdoutTask = Task.detached { stdoutPipe.fileHandleForReading.readDataToEndOfFile() }
        let stderrTask = Task.detached { stderrPipe.fileHandleForReading.readDataToEndOfFile() }

        do {
            let input = try makeSessionInput(request: request)
            stdinPipe.fileHandleForWriting.write(input)
            try stdinPipe.fileHandleForWriting.close()
        } catch {
            process.terminate()
            throw LanguageServiceError.unsupported("Failed to write SourceKit-LSP request: \(error.localizedDescription)")
        }

        try await waitForExit(process: process)

        let stdout = await stdoutTask.value
        let stderr = await stderrTask.value

        if process.terminationStatus != 0 {
            let stderrText = String(data: stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let suffix = stderrText.isEmpty ? "" : " (\(stderrText))"
            throw LanguageServiceError.unsupported("SourceKit-LSP exited with code \(process.terminationStatus)\(suffix)")
        }

        return try extractMethodResult(from: stdout, requestID: 2)
    }

    private func ensureBinaryReachable(executablePath: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", executablePath]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw LanguageServiceError.unsupported("Unable to verify '\(executablePath)': \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            throw LanguageServiceError.unsupported("SourceKit-LSP binary not found: \(executablePath)")
        }
    }

    private func waitForExit(process: Process) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while process.isRunning {
            if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
                process.terminate()
                throw LanguageServiceError.unsupported("SourceKit-LSP request timed out")
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    private func makeSessionInput(request: SourceKitLSPRequest) throws -> Data {
        let rootPath = request.workspaceRootPath ?? FileManager.default.currentDirectoryPath
        let rootURI = URL(fileURLWithPath: rootPath, isDirectory: true).absoluteString

        let initialize: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "processId": ProcessInfo.processInfo.processIdentifier,
                "clientInfo": ["name": "CoderIDE", "version": "1.0"],
                "rootUri": rootURI,
                "capabilities": [:]
            ]
        ]
        var payload = Data()
        payload.append(try frame(jsonObject: initialize))
        payload.append(try frame(jsonObject: ["jsonrpc": "2.0", "method": "initialized", "params": [:]]))

        for document in request.openDocuments {
            let didOpen = LSPDidOpenTextDocumentParams(
                textDocument: LSPTextDocumentItem(
                    uri: URL(fileURLWithPath: document.filePath).absoluteString,
                    languageId: document.languageId,
                    version: 1,
                    text: document.text
                )
            )
            let didOpenJSON = try JSONEncoder().encode(didOpen)
            let didOpenPayload = try jsonObject(from: didOpenJSON)
            let message: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "textDocument/didOpen",
                "params": didOpenPayload
            ]
            payload.append(try frame(jsonObject: message))
        }

        let methodParams = try jsonObject(from: request.paramsJSON)
        let methodRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 2,
            "method": request.method,
            "params": methodParams
        ]
        payload.append(try frame(jsonObject: methodRequest))
        payload.append(try frame(jsonObject: ["jsonrpc": "2.0", "id": 3, "method": "shutdown", "params": NSNull()]))
        payload.append(try frame(jsonObject: ["jsonrpc": "2.0", "method": "exit", "params": [:]]))
        return payload
    }

    private func frame(jsonObject: Any) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
        var data = Data("Content-Length: \(json.count)\r\n\r\n".utf8)
        data.append(json)
        return data
    }

    private func jsonObject(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private func extractMethodResult(from output: Data, requestID: Int) throws -> Data {
        let messages = try parseMessages(output)
        for message in messages {
            guard let id = message["id"] as? NSNumber, id.intValue == requestID else {
                continue
            }
            if let error = message["error"] {
                let errorData = try JSONSerialization.data(withJSONObject: error, options: [.fragmentsAllowed])
                let detail = String(data: errorData, encoding: .utf8) ?? "unknown"
                throw LanguageServiceError.unsupported("SourceKit-LSP error response: \(detail)")
            }
            guard let result = message["result"] else {
                return Data("null".utf8)
            }
            return try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])
        }
        throw LanguageServiceError.unsupported("SourceKit-LSP response did not include request id \(requestID)")
    }

    private func parseMessages(_ data: Data) throws -> [[String: Any]] {
        var index = 0
        var parsed: [[String: Any]] = []
        let bytes = [UInt8](data)

        while index < bytes.count {
            guard let headerEnd = findHeaderTerminator(in: bytes, from: index) else {
                break
            }
            let headerData = Data(bytes[index..<headerEnd])
            let header = String(data: headerData, encoding: .utf8) ?? ""
            let contentLength = try parseContentLength(header: header)
            let bodyStart = headerEnd + 4
            let bodyEnd = bodyStart + contentLength
            guard bodyEnd <= bytes.count else {
                throw LanguageServiceError.unsupported("Malformed SourceKit-LSP stream: truncated body")
            }

            let body = Data(bytes[bodyStart..<bodyEnd])
            let object = try JSONSerialization.jsonObject(with: body, options: [])
            if let dictionary = object as? [String: Any] {
                parsed.append(dictionary)
            }
            index = bodyEnd
        }
        return parsed
    }

    private func parseContentLength(header: String) throws -> Int {
        for line in header.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0].lowercased().trimmingCharacters(in: .whitespaces) == "content-length",
               let value = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                return value
            }
        }
        throw LanguageServiceError.unsupported("Malformed SourceKit-LSP stream: missing Content-Length header")
    }

    private func findHeaderTerminator(in bytes: [UInt8], from start: Int) -> Int? {
        var i = start
        while i + 3 < bytes.count {
            if bytes[i] == 13, bytes[i + 1] == 10, bytes[i + 2] == 13, bytes[i + 3] == 10 {
                return i
            }
            i += 1
        }
        return nil
    }
}
