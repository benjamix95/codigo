import Darwin
import Foundation

@main
struct CoderIDEMCPServerExecutableMain {
    static func main() async throws {
        let targetURL = resolveRustBinaryURL()
        guard FileManager.default.isExecutableFile(atPath: targetURL.path) else {
            FileHandle.standardError.write(
                Data("coderide-mcp-server-rust not found at \(targetURL.path)\n".utf8)
            )
            Foundation.exit(70)
        }

        var cArguments = CommandLine.arguments.map { strdup($0) }
        defer {
            for argument in cArguments {
                free(argument)
            }
        }

        let executable = strdup(targetURL.path)
        defer { free(executable) }
        cArguments[0] = executable
        cArguments.append(nil)

        execv(targetURL.path, cArguments)
        let message = String(cString: strerror(errno))
        FileHandle.standardError.write(
            Data("failed to exec coderide-mcp-server-rust: \(message)\n".utf8)
        )
        Foundation.exit(71)
    }

    private static func resolveRustBinaryURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["SOLOCODE_RUST_MCP_SERVER_BINARY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let currentExecutable = URL(fileURLWithPath: CommandLine.arguments[0])
        return currentExecutable
            .deletingLastPathComponent()
            .appendingPathComponent("coderide-mcp-server-rust")
    }
}
