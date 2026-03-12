import Foundation

enum MCPLifecycleRustBinaryLocator {
    private static let binaryName = "mcp-lifecycle-backend-rust"

    static func resolveBinaryURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["SOLOCODE_RUST_MCP_LIFECYCLE_BINARY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        for candidate in candidateURLs() {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func candidateURLs() -> [URL] {
        var candidates: [URL] = []

        let currentExecutable = URL(fileURLWithPath: CommandLine.arguments[0])
        candidates.append(
            currentExecutable
                .deletingLastPathComponent()
                .appendingPathComponent(binaryName)
        )

        if let repoRoot = repositoryRoot() {
            candidates.append(
                repoRoot
                    .appendingPathComponent("Native/target/debug")
                    .appendingPathComponent(binaryName)
            )
            candidates.append(
                repoRoot
                    .appendingPathComponent("Native/target/release")
                    .appendingPathComponent(binaryName)
            )
            candidates.append(
                repoRoot
                    .appendingPathComponent(".build/rust-mcp-lifecycle/debug")
                    .appendingPathComponent(binaryName)
            )
            candidates.append(
                repoRoot
                    .appendingPathComponent(".build/rust-mcp-lifecycle/release")
                    .appendingPathComponent(binaryName)
            )
        }

        return candidates
    }

    private static func repositoryRoot() -> URL? {
        var current = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        while current.path != "/" {
            let workspace = current.appendingPathComponent("Solo Code.xcworkspace")
            let cargoRoot = current.appendingPathComponent("Native/Cargo.toml")
            if FileManager.default.fileExists(atPath: workspace.path),
               FileManager.default.fileExists(atPath: cargoRoot.path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        return nil
    }
}
