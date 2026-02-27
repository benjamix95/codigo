import Foundation
import MCP
import os

#if canImport(System)
import System
#else
@preconcurrency import SystemPackage
#endif

/// Crea un trasporto MCP connesso a un subprocess
public enum MCPTransportFactory {
    private static let logger = Logger(subsystem: "com.codigo.CoderEngine", category: "MCPTransportFactory")

    /// Avvia un server MCP come subprocess e restituisce un trasporto connesso
    public static func connectToProcess(
        command: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:],
        serverLabel: String? = nil,
        stderrBufferLimitBytes: Int = 65_536
    ) async throws -> (transport: StdioTransport, process: Process) {
        let (clientRead, serverWrite) = try FileDescriptor.pipe()
        let (serverRead, clientWrite) = try FileDescriptor.pipe()
        let stderrPipe = Pipe()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardInput = FileHandle(fileDescriptor: serverRead.rawValue)
        process.standardOutput = FileHandle(fileDescriptor: serverWrite.rawValue)
        process.standardError = stderrPipe
        if !environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            env.merge(environment) { _, new in new }
            process.environment = env
        }
        if let cwd = workingDirectory {
            process.currentDirectoryURL = cwd
        }
        try process.run()

        startStderrPump(
            fileHandle: stderrPipe.fileHandleForReading,
            serverLabel: serverLabel ?? command,
            bufferLimitBytes: max(4_096, stderrBufferLimitBytes)
        )
        
        try serverRead.close()
        try serverWrite.close()
        
        let transport = StdioTransport(input: clientRead, output: clientWrite)
        try await transport.connect()
        
        return (transport, process)
    }

    private static func startStderrPump(
        fileHandle: FileHandle,
        serverLabel: String,
        bufferLimitBytes: Int
    ) {
        Task.detached(priority: .utility) {
            var rollingBuffer = Data()
            while true {
                let chunk: Data
                do {
                    chunk = try fileHandle.read(upToCount: 4096) ?? Data()
                } catch {
                    let message = "MCP stderr read failure server=\(serverLabel) error=\(error.localizedDescription)"
                    Self.logger.error("\(message, privacy: .public)")
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
                    let line = Self.sanitizedLine(from: lineData)
                    if !line.isEmpty {
                        Self.logger.error("MCP stderr[\(serverLabel, privacy: .public)] \(line, privacy: .public)")
                    }
                }
            }

            if !rollingBuffer.isEmpty {
                let line = Self.sanitizedLine(from: rollingBuffer)
                if !line.isEmpty {
                    Self.logger.error("MCP stderr[\(serverLabel, privacy: .public)] \(line, privacy: .public)")
                }
            }
            try? fileHandle.close()
        }
    }

    private static func sanitizedLine(from data: Data) -> String {
        let raw = String(data: data, encoding: .utf8) ?? ""
        let filteredScalars = raw.unicodeScalars.filter { scalar in
            scalar.value == 0x09 || scalar.value >= 0x20
        }
        return String(String.UnicodeScalarView(filteredScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
