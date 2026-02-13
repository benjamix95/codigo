import Foundation

/// Esegue un comando in subprocess e restituisce l'output line-by-line
struct ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
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
        
        return AsyncThrowingStream { continuation in
            Task {
                var buffer = [UInt8]()
                do {
                    for try await byte in stdoutPipe.fileHandleForReading.bytes {
                        buffer.append(byte)
                        if byte == 10 {
                            let line = String(bytes: buffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            buffer.removeAll()
                            if !line.isEmpty {
                                continuation.yield(line)
                            }
                        }
                    }
                } catch {
                    if !buffer.isEmpty, let line = String(bytes: buffer, encoding: .utf8), !line.isEmpty {
                        continuation.yield(line)
                    }
                }
                process.waitUntilExit()
                continuation.finish()
            }
        }
    }

    /// Esegue un comando e restituisce tutte le linee di output più il codice di uscita
    static func runCollecting(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil
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
        if !buffer.isEmpty, let line = String(bytes: buffer, encoding: .utf8), !line.isEmpty {
            lines.append(line)
        }
        process.waitUntilExit()
        return (lines, process.terminationStatus)
    }
}

