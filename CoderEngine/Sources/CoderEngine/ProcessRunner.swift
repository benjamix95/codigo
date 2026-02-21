import Foundation

/// Esegue un comando in subprocess e restituisce l'output line-by-line
struct ProcessRunner {
    private static let stdoutTailCapacity = 50

    struct ProcessRunnerError: LocalizedError {
        let exitCode: Int32
        let message: String
        let stdoutTail: String?

        var errorDescription: String? {
            var desc = "Processo terminato con exit code \(exitCode): \(message)"
            if let tail = stdoutTail, !tail.isEmpty {
                desc += "\n\nUltime righe stdout:\n\(tail)"
            }
            return desc
        }
    }

    static func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        executionController: ExecutionController? = nil,
        scope: ExecutionScope = .agent
    ) async throws -> AsyncThrowingStream<String, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd = workingDirectory {
            process.currentDirectoryURL = cwd
        }
        if let env = environment {
            process.environment = (ProcessInfo.processInfo.environment).merging(env) { _, new in new }
        }
        
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardInput = nil
        
        try process.run()
        executionController?.beginScope(scope)
        executionController?.setCurrentProcess(process)
        
        return AsyncThrowingStream { continuation in
            Task {
                defer { executionController?.clearCurrentProcess() }
                let stderrTask = Task { () -> String in
                    var stderrBuffer = [UInt8]()
                    var stderrLines: [String] = []
                    do {
                        for try await byte in stderrPipe.fileHandleForReading.bytes {
                            stderrBuffer.append(byte)
                            if byte == 10 {
                                let line = String(bytes: stderrBuffer, encoding: .utf8)?
                                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                stderrBuffer.removeAll()
                                if !line.isEmpty { stderrLines.append(line) }
                            }
                        }
                    } catch {
                        // In caso di stream interrotto, usa comunque quanto raccolto.
                    }
                    if !stderrBuffer.isEmpty,
                       let line = String(bytes: stderrBuffer, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !line.isEmpty {
                        stderrLines.append(line)
                    }
                    return stderrLines.suffix(10).joined(separator: "\n")
                }

                var buffer = [UInt8]()
                var stdoutTailBuffer: [String] = []
                do {
                    for try await byte in stdoutPipe.fileHandleForReading.bytes {
                        buffer.append(byte)
                        if byte == 10 {
                            let line = String(bytes: buffer, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            buffer.removeAll()
                            if !line.isEmpty {
                                continuation.yield(line)
                                stdoutTailBuffer.append(line)
                                if stdoutTailBuffer.count > Self.stdoutTailCapacity {
                                    stdoutTailBuffer.removeFirst()
                                }
                            }
                        }
                    }
                } catch {
                    if !buffer.isEmpty,
                       let line = String(bytes: buffer, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !line.isEmpty {
                        continuation.yield(line)
                        stdoutTailBuffer.append(line)
                        if stdoutTailBuffer.count > Self.stdoutTailCapacity {
                            stdoutTailBuffer.removeFirst()
                        }
                    }
                }
                if !buffer.isEmpty,
                   let line = String(bytes: buffer, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !line.isEmpty {
                    continuation.yield(line)
                    stdoutTailBuffer.append(line)
                    if stdoutTailBuffer.count > Self.stdoutTailCapacity {
                        stdoutTailBuffer.removeFirst()
                    }
                }

                process.waitUntilExit()
                let stderrTail = await stderrTask.value
                if process.terminationStatus == 0 {
                    continuation.finish()
                    return
                }
                if executionController?.runState == .stopping {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                let message = stderrTail.isEmpty ? "nessun output stderr disponibile" : stderrTail
                let stdoutTail: String? = stderrTail.isEmpty && !stdoutTailBuffer.isEmpty
                    ? stdoutTailBuffer.suffix(Self.stdoutTailCapacity).joined(separator: "\n")
                    : nil
                continuation.finish(throwing: ProcessRunnerError(exitCode: process.terminationStatus, message: message, stdoutTail: stdoutTail))
            }
        }
    }

    /// Esegue un comando e restituisce tutte le linee di output più il codice di uscita.
    /// Se executionController è fornito, il processo viene registrato e può essere terminato
    /// quando l'utente preme "Ferma" o quando il flusso si interrompe.
    static func runCollecting(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        executionController: ExecutionController? = nil,
        scope: ExecutionScope = .agent
    ) async throws -> (output: [String], terminationStatus: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd = workingDirectory {
            process.currentDirectoryURL = cwd
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = nil
        try process.run()

        executionController?.beginScope(scope)
        executionController?.setCurrentProcess(process)
        defer { executionController?.clearCurrentProcess() }

        var lines: [String] = []
        var buffer = [UInt8]()
        for try await byte in pipe.fileHandleForReading.bytes {
            buffer.append(byte)
            if byte == 10 {
                let line = String(bytes: buffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                buffer.removeAll()
                if !line.isEmpty { lines.append(line) }
            }
        }
        if !buffer.isEmpty,
           let line = String(bytes: buffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty {
            lines.append(line)
        }
        process.waitUntilExit()
        if executionController?.runState == .stopping {
            throw CancellationError()
        }
        return (lines, process.terminationStatus)
    }
}
