import Foundation

extension CLIProfileProvisioner {
    static func bundledMCPServerSiblingPath() -> String? {
        guard let execURL = Bundle.main.executableURL else { return nil }
        return execURL.deletingLastPathComponent()
            .appendingPathComponent("coderide-mcp-server-rust")
            .path
    }

    static func developmentMCPServerBinaryPaths(
        sourceFilePath: String = #filePath
    ) -> [String] {
        let sourceURL = URL(fileURLWithPath: sourceFilePath)
        let repoRoot = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return [
            repoRoot
                .appendingPathComponent("Native", isDirectory: true)
                .appendingPathComponent("target", isDirectory: true)
                .appendingPathComponent("debug", isDirectory: true)
                .appendingPathComponent("coderide-mcp-server-rust")
                .path,
            repoRoot
                .appendingPathComponent(".build", isDirectory: true)
                .appendingPathComponent("rust-mcp-server", isDirectory: true)
                .appendingPathComponent("debug", isDirectory: true)
                .appendingPathComponent("coderide-mcp-server-rust")
                .path,
        ]
    }

    static func firstExecutablePath(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func newestExecutablePath(_ candidates: [String]) -> String? {
        let fileManager = FileManager.default
        return candidates
            .filter { fileManager.isExecutableFile(atPath: $0) }
            .max { lhs, rhs in
                modificationDate(for: lhs, fileManager: fileManager) < modificationDate(for: rhs, fileManager: fileManager)
            }
    }

    private static func modificationDate(for path: String, fileManager: FileManager) -> Date {
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        return (attributes?[.modificationDate] as? Date) ?? .distantPast
    }

    static func mcpServerBinaryPath() -> String? {
        let overridePath = ProcessInfo.processInfo.environment[mcpServerPathOverrideEnv]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !overridePath.isEmpty, FileManager.default.isExecutableFile(atPath: overridePath) {
            return overridePath
        }

        // Prefer the Cargo-owned binary over the .build mirror: the latter can drift and
        // fail the Codex app-server MCP handshake even when Native/target is healthy.
        if let developmentBinary = firstExecutablePath(developmentMCPServerBinaryPaths()) {
            return developmentBinary
        }

        return firstExecutablePath([bundledMCPServerSiblingPath()].compactMap { $0 })
    }
}
