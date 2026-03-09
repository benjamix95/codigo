import Foundation

extension ProcessRunner {
    static func runCollectingSync(
        executable: String,
        arguments: [String],
        workingDirectory: URL
    ) throws -> (output: String, terminationStatus: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        process.waitUntilExit()
        return (output, process.terminationStatus)
    }
}
