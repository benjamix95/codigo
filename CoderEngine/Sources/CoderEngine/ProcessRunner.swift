import Foundation

/// Runs a command in a subprocess and returns the output line-by-line.
///
/// Uses `readabilityHandler` for stdout so that lines are emitted
/// immediately as the process writes them, without waiting for the
/// Pipe / FileHandle.bytes Foundation buffer.
struct ProcessRunner {
    private static let stdoutTailCapacity = 50
    private static let lineFeed: UInt8 = 10
    private static let carriageReturn: UInt8 = 13

    struct ProcessRunnerError: LocalizedError {
        let exitCode: Int32
        let message: String
        let stdoutTail: String?

        var errorDescription: String? {
            var desc = "Process terminated with exit code \(exitCode): \(message)"
            if let tail = stdoutTail, !tail.isEmpty {
                desc += "\n\nLast stdout lines:\n\(tail)"
            }
            return desc
        }
    }

    // MARK: - Shared mutable state for readabilityHandler callbacks

    /// Thread-safe holder for the mutable buffers accessed from readabilityHandler callbacks.
    /// readabilityHandler fires on a dispatch queue — all access is serialised by that queue,
    /// so the `@unchecked Sendable` conformance is safe.
    private final class StdoutReadState: @unchecked Sendable {
        var lineBuffer: [UInt8] = []
        var tailBuffer: [String] = []
        var firstChunkReceived = false
    }

    // MARK: - run (streaming, real-time)

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

                // ---------- stderr: collect in background (unchanged) ----------
                let stderrTask = Task { () -> String in
                    var stderrBuffer = [UInt8]()
                    var stderrLines: [String] = []
                    do {
                        for try await byte in stderrPipe.fileHandleForReading.bytes {
                            consumeLineByte(byte, buffer: &stderrBuffer) { line in
                                stderrLines.append(line)
                            }
                        }
                    } catch {
                        // Stream interrupted — use what was collected.
                    }
                    flushLineBuffer(&stderrBuffer) { line in
                        stderrLines.append(line)
                    }
                    return stderrLines.suffix(10).joined(separator: "\n")
                }

                // ---------- stdout: readabilityHandler for REAL-TIME delivery ----------
                // readabilityHandler fires on a serial dispatch queue immediately when the
                // kernel detects data in the pipe buffer (kevent/kqueue). This bypasses any
                // internal buffering that FileHandle.bytes might apply.
                let state = StdoutReadState()
                let tailCap = stdoutTailCapacity

                await withCheckedContinuation { (stdoutDone: CheckedContinuation<Void, Never>) in
                    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if data.isEmpty {
                            // EOF — pipe closed (process exited or closed stdout).
                            NSLog("[ProcessRunner] stdout EOF — total lines yielded: %d", state.tailBuffer.count)
                            flushLineBuffer(&state.lineBuffer) { line in
                                continuation.yield(line)
                                state.tailBuffer.append(line)
                                if state.tailBuffer.count > tailCap {
                                    state.tailBuffer.removeFirst()
                                }
                            }
                            handle.readabilityHandler = nil
                            stdoutDone.resume()
                            return
                        }
                        if !state.firstChunkReceived {
                            state.firstChunkReceived = true
                            NSLog("[ProcessRunner] first stdout chunk: %d bytes", data.count)
                        }
                        // Process every byte in the chunk — yields lines on \n or \r.
                        for byte in data {
                            consumeLineByte(byte, buffer: &state.lineBuffer) { line in
                                continuation.yield(line)
                                state.tailBuffer.append(line)
                                if state.tailBuffer.count > tailCap {
                                    state.tailBuffer.removeFirst()
                                }
                            }
                        }
                    }
                }

                // ---------- Process termination ----------
                process.waitUntilExit()
                let stderrTail = await stderrTask.value

                if process.terminationStatus == 0 {
                    continuation.finish()
                    return
                }
                // SIGTERM (15) is often used for intentional stop from the controller/UI.
                if process.terminationStatus == 15 {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                if executionController?.runState == .stopping {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                let message = stderrTail.isEmpty ? "no stderr output available" : stderrTail
                let stdoutTail: String? = stderrTail.isEmpty && !state.tailBuffer.isEmpty
                    ? state.tailBuffer.suffix(Self.stdoutTailCapacity).joined(separator: "\n")
                    : nil
                continuation.finish(throwing: ProcessRunnerError(
                    exitCode: process.terminationStatus,
                    message: message,
                    stdoutTail: stdoutTail
                ))
            }
        }
    }

    // MARK: - runCollecting (non-streaming)

    /// Runs a command and returns all output lines plus the exit code.
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
            consumeLineByte(byte, buffer: &buffer) { line in
                lines.append(line)
            }
        }
        flushLineBuffer(&buffer) { line in
            lines.append(line)
        }
        process.waitUntilExit()
        if executionController?.runState == .stopping {
            throw CancellationError()
        }
        return (lines, process.terminationStatus)
    }

    // MARK: - Line Parsing Helpers

    private static func consumeLineByte(
        _ byte: UInt8,
        buffer: inout [UInt8],
        onLine: (String) -> Void
    ) {
        if byte == lineFeed || byte == carriageReturn {
            flushLineBuffer(&buffer, onLine: onLine)
            return
        }
        buffer.append(byte)
    }

    private static func flushLineBuffer(
        _ buffer: inout [UInt8],
        onLine: (String) -> Void
    ) {
        guard !buffer.isEmpty else { return }
        defer { buffer.removeAll(keepingCapacity: true) }
        guard let line = String(bytes: buffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !line.isEmpty
        else { return }
        onLine(line)
    }
}
