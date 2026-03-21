import Foundation

extension CLIProfileProvisioner {
    static func bundledMCPServerSiblingPath() -> String? {
        guard let execURL = Bundle.main.executableURL else { return nil }
        return execURL.deletingLastPathComponent()
            .appendingPathComponent("coderide-mcp-server-rust")
            .path
    }

    static func mcpServerBinaryPath() -> String? {
        let overridePath = ProcessInfo.processInfo.environment[mcpServerPathOverrideEnv]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !overridePath.isEmpty, FileManager.default.isExecutableFile(atPath: overridePath) {
            return overridePath
        }

        if let siblingPath = bundledMCPServerSiblingPath(),
           FileManager.default.isExecutableFile(atPath: siblingPath) {
            return siblingPath
        }
        return nil
    }
}
