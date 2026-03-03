import Foundation

extension CLIProfileProvisioner {
    /// Self-heal all managed CLI profiles.
    /// - Restores bundled `coderide-mcp-server` when missing.
    /// - Repairs Codex/Claude/Gemini managed profile configs to point to a valid MCP command.
    static func selfHealManagedProfiles() {
        // Test/debug overrides are intended for isolated profile provisioning calls.
        // Never fan out a global rewrite to all managed profiles with an override value.
        let overridePath = ProcessInfo.processInfo.environment[mcpServerPathOverrideEnv]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard overridePath.isEmpty else { return }

        _ = ensureBundledMCPServerBinaryIfNeeded()
        selfHealCodexProfiles()
        selfHealClaudeProfiles()
        selfHealGeminiProfiles()
    }

    static func ensureBundledMCPServerBinaryIfNeeded() -> Bool {
        guard let targetPath = bundledMCPServerSiblingPath() else { return false }
        if FileManager.default.isExecutableFile(atPath: targetPath) {
            return true
        }

        guard let sourcePath = mcpServerBinaryPath(),
              sourcePath != targetPath,
              FileManager.default.isExecutableFile(atPath: sourcePath)
        else {
            return false
        }

        let targetURL = URL(fileURLWithPath: targetPath)
        let targetDir = targetURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: targetPath) {
                try FileManager.default.removeItem(atPath: targetPath)
            }
            try FileManager.default.copyItem(atPath: sourcePath, toPath: targetPath)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: targetPath
            )
            return FileManager.default.isExecutableFile(atPath: targetPath)
        } catch {
            return false
        }
    }

    private static func selfHealCodexProfiles() {
        for profile in managedProfileDirectories(provider: .codex) {
            selfHealCodexProfile(at: profile)
        }
    }

    private static func selfHealClaudeProfiles() {
        for profile in managedProfileDirectories(provider: .claude) {
            ensureClaudeProfileFiles(at: profile)
        }
    }

    private static func selfHealGeminiProfiles() {
        for profile in managedProfileDirectories(provider: .gemini) {
            ensureGeminiMCPConfig(at: profile)
        }
    }

    private static func managedProfileDirectories(provider: CLIProviderKind) -> [URL] {
        let root = baseProfilesDir().appendingPathComponent(provider.rawValue, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }
}
