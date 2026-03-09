import Foundation

struct ValidationCommandResult: Sendable {
    let output: String
    let exitCode: Int32
    let command: String
}

enum ValidationCommandExecutor {
    static func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL
    ) async throws -> ValidationCommandResult {
        let collected = try await ProcessRunner.runCollecting(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
        let output = collected.output.joined(separator: "\n")
        return ValidationCommandResult(
            output: output,
            exitCode: collected.terminationStatus,
            command: ([executable] + arguments).joined(separator: " ")
        )
    }
}
