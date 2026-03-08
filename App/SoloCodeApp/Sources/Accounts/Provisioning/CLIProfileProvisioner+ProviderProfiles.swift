import Foundation

extension CLIProfileProvisioner {
    static func ensureClaudeProfileFiles(at profileURL: URL) {
        try? FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        let claudeHome = profileURL.appendingPathComponent(".claude", isDirectory: true)
        try? FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
        seedInstructionIfMissing(
            at: profileURL.appendingPathComponent("AGENTS.md"),
            content: effectiveAgentsContent()
        )
        seedInstructionIfMissing(
            at: claudeHome.appendingPathComponent("CLAUDE.md"),
            content: effectiveAgentsContent()
        )

        guard let mcpPath = mcpServerBinaryPath() else { return }
        let settingsURL = claudeHome.appendingPathComponent("settings.json")
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = existing
        }

        let mcpConfig: [String: Any] = [
            "command": mcpPath,
            "args": ["--workspace", "."],
        ]
        var mcpServers = (settings["mcpServers"] as? [String: Any]) ?? [:]
        mcpServers["coderide"] = mcpConfig
        settings["mcpServers"] = mcpServers
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    static func ensureGeminiMCPConfig(at profileURL: URL) {
        seedInstructionIfMissing(
            at: profileURL.appendingPathComponent("AGENTS.md"),
            content: effectiveAgentsContent()
        )
        guard let mcpPath = mcpServerBinaryPath() else { return }
        let settingsURL = profileURL.appendingPathComponent("settings.json")
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = existing
        }
        let mcpConfig: [String: Any] = [
            "command": mcpPath,
            "args": ["--workspace", "."],
        ]
        var mcpServers = (settings["mcpServers"] as? [String: Any]) ?? [:]
        mcpServers["coderide"] = mcpConfig
        settings["mcpServers"] = mcpServers
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    private static func seedInstructionIfMissing(at url: URL, content: String) {
        if FileManager.default.fileExists(atPath: url.path) {
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}
