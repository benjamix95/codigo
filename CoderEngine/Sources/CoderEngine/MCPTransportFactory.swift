import Foundation
import MCP

#if canImport(System)
import System
#else
@preconcurrency import SystemPackage
#endif

/// Crea un trasporto MCP connesso a un subprocess
public enum MCPTransportFactory {
    /// Avvia un server MCP come subprocess e restituisce un trasporto connesso
    public static func connectToProcess(
        command: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil
    ) async throws -> (transport: StdioTransport, process: Process) {
        let (clientRead, serverWrite) = try FileDescriptor.pipe()
        let (serverRead, clientWrite) = try FileDescriptor.pipe()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardInput = FileHandle(fileDescriptor: serverRead.rawValue)
        process.standardOutput = FileHandle(fileDescriptor: serverWrite.rawValue)
        process.standardError = nil
        if let cwd = workingDirectory {
            process.currentDirectoryURL = cwd
        }
        try process.run()
        
        try serverRead.close()
        try serverWrite.close()
        
        let transport = StdioTransport(input: clientRead, output: clientWrite)
        try await transport.connect()
        
        return (transport, process)
    }
}
