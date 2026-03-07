import Foundation

extension CLIProfileProvisioner {
    static func bundledMCPServerSiblingPath() -> String? {
        guard let execURL = Bundle.main.executableURL else { return nil }
        return execURL.deletingLastPathComponent()
            .appendingPathComponent("coderide-mcp-server")
            .path
    }

    static func mcpServerBinaryPath() -> String? {
        let overridePath = ProcessInfo.processInfo.environment[mcpServerPathOverrideEnv]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !overridePath.isEmpty, FileManager.default.isExecutableFile(atPath: overridePath) {
            return overridePath
        }

        if let bundled = Bundle.main.url(forResource: "coderide-mcp-server", withExtension: nil)?.path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }

        if let siblingPath = bundledMCPServerSiblingPath(),
           FileManager.default.isExecutableFile(atPath: siblingPath) {
            return siblingPath
        }

        let appSupportBuild = baseProfilesDir()
            .deletingLastPathComponent().deletingLastPathComponent() // up to App Support
            .appendingPathComponent("CoderEngine/.build", isDirectory: true)
        if let fromBuild = findMCPBinary(in: appSupportBuild) {
            return fromBuild
        }
        return nil
    }

    static func findMCPBinary(in buildRoot: URL) -> String? {
        guard FileManager.default.fileExists(atPath: buildRoot.path) else { return nil }

        let directCandidates = [
            buildRoot.appendingPathComponent("debug/coderide-mcp-server"),
            buildRoot.appendingPathComponent("arm64-apple-macosx/debug/coderide-mcp-server"),
            buildRoot.appendingPathComponent("x86_64-apple-macosx/debug/coderide-mcp-server"),
            buildRoot.appendingPathComponent("release/coderide-mcp-server"),
            buildRoot.appendingPathComponent("arm64-apple-macosx/release/coderide-mcp-server"),
            buildRoot.appendingPathComponent("x86_64-apple-macosx/release/coderide-mcp-server"),
        ]
        for candidate in directCandidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate.path
        }

        guard let enumerator = FileManager.default.enumerator(
            at: buildRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "coderide-mcp-server",
               FileManager.default.isExecutableFile(atPath: fileURL.path) {
                return fileURL.path
            }
        }
        return nil
    }
}
