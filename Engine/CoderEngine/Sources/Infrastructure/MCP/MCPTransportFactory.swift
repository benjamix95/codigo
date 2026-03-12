import Foundation
import MCP
import os

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

#if canImport(System)
import System
#else
@preconcurrency import SystemPackage
#endif

/// Creates an MCP transport connected to a subprocess
public enum MCPTransportFactory {
    private static let logger = Logger(subsystem: "com.codigo.CoderEngine", category: "MCPTransportFactory")
    private static let ignoreSIGPIPE: Void = {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
        _ = signal(SIGPIPE, SIG_IGN)
        #endif
    }()

    /// Starts an MCP server as a subprocess and returns a connected transport
    public static func connectToProcess(
        command: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:],
        serverLabel: String? = nil,
        stderrBufferLimitBytes: Int = 65_536
    ) async throws -> (
        transport: StdioTransport,
        process: Process,
        resources: MCPTransportResources
    ) {
        _ = ignoreSIGPIPE
        let (clientRead, serverWrite) = try FileDescriptor.pipe()
        let (serverRead, clientWrite) = try FileDescriptor.pipe()
        let stderrPipe = Pipe()
        let stdinHandle = FileHandle(fileDescriptor: serverRead.rawValue, closeOnDealloc: true)
        let stdoutHandle = FileHandle(fileDescriptor: serverWrite.rawValue, closeOnDealloc: true)
        let stderrReadHandle = stderrPipe.fileHandleForReading
        let stderrWriteHandle = stderrPipe.fileHandleForWriting
        let resources = MCPTransportResources(
            input: clientRead,
            output: clientWrite,
            stderrReadHandle: stderrReadHandle
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardInput = stdinHandle
        process.standardOutput = stdoutHandle
        process.standardError = stderrPipe
        if !environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            env.merge(environment) { _, new in new }
            process.environment = env
        }
        if let cwd = workingDirectory {
            process.currentDirectoryURL = cwd
        }
        do {
            try process.run()
        } catch {
            try? stdinHandle.close()
            try? stdoutHandle.close()
            try? stderrWriteHandle.close()
            resources.closeAll()
            throw error
        }

        // The child inherited duplicates of these ends during spawn; the parent
        // must close its copies immediately to avoid exhausting file descriptors.
        try? stdinHandle.close()
        try? stdoutHandle.close()
        try? stderrWriteHandle.close()

        startStderrPump(
            fileHandle: stderrReadHandle,
            serverLabel: serverLabel ?? command,
            bufferLimitBytes: max(4_096, stderrBufferLimitBytes)
        )

        let transport = StdioTransport(input: clientRead, output: clientWrite)
        do {
            try await transport.connect()
        } catch {
            // Clean up leaked resources on connection failure
            cleanupFailedConnection(process: process, resources: resources)
            throw error
        }

        return (transport, process, resources)
    }

    static func cleanupFailedConnection(
        process: Process,
        resources: MCPTransportResources
    ) {
        terminateProcess(process, waitForExit: false)
        resources.closeAll()
    }

    static func terminateProcess(
        _ process: Process,
        waitForExit: Bool
    ) {
        if process.isRunning {
            process.terminate()
        }
        if waitForExit {
            process.waitUntilExit()
        }
    }

    private static func startStderrPump(
        fileHandle: FileHandle,
        serverLabel: String,
        bufferLimitBytes: Int
    ) {
        Task.detached(priority: .utility) {
            var rollingBuffer = Data()
            var windowStart = Date()
            var loggedInWindow = 0
            var suppressedInWindow = 0
            let maxLinesPerSecond = 20

            func flushSuppressedIfNeeded() {
                guard suppressedInWindow > 0 else { return }
                Self.logger.error(
                    "MCP stderr[\(serverLabel, privacy: .private)] suppressed \(suppressedInWindow, privacy: .public) noisy line(s) in last second"
                )
                suppressedInWindow = 0
            }

            func rotateWindowIfNeeded(now: Date) {
                if now.timeIntervalSince(windowStart) < 1.0 { return }
                flushSuppressedIfNeeded()
                windowStart = now
                loggedInWindow = 0
            }

            while true {
                let chunk: Data
                do {
                    chunk = try fileHandle.read(upToCount: 4096) ?? Data()
                } catch {
                    let message = "MCP stderr read failure server=\(serverLabel) error=\(error.localizedDescription)"
                    Self.logger.error("\(message, privacy: .private)")
                    break
                }
                if chunk.isEmpty { break }
                rollingBuffer.append(chunk)
                if rollingBuffer.count > bufferLimitBytes {
                    rollingBuffer.removeFirst(rollingBuffer.count - bufferLimitBytes)
                }

                while let newlineRange = rollingBuffer.firstRange(of: Data([0x0A])) {
                    let lineData = rollingBuffer.subdata(in: 0..<newlineRange.lowerBound)
                    rollingBuffer.removeSubrange(0...newlineRange.lowerBound)
                    if Self.hasNonWhitespaceContent(lineData) {
                        let now = Date()
                        rotateWindowIfNeeded(now: now)
                        if loggedInWindow < maxLinesPerSecond {
                            Self.logger.error(
                                "MCP stderr[\(serverLabel, privacy: .private)] produced output line"
                            )
                            loggedInWindow += 1
                        } else {
                            suppressedInWindow += 1
                        }
                    }
                }
            }

            if !rollingBuffer.isEmpty {
                if Self.hasNonWhitespaceContent(rollingBuffer) {
                    Self.logger.error(
                        "MCP stderr[\(serverLabel, privacy: .private)] produced output line"
                    )
                }
            }
            flushSuppressedIfNeeded()
            try? fileHandle.close()
        }
    }

    private static func hasNonWhitespaceContent(_ data: Data) -> Bool {
        let raw = String(data: data, encoding: .utf8) ?? ""
        let filteredScalars = raw.unicodeScalars.filter { scalar in
            scalar.value == 0x09 || scalar.value >= 0x20
        }
        return !String(String.UnicodeScalarView(filteredScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }
}
