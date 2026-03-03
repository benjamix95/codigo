import Foundation

extension CLIProfileProvisioner {
    static func ensureCodexProfileFiles(at profileURL: URL, overwrite: Bool) {
        try? FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        seedCodexConfigToml(at: profileURL, overwrite: overwrite)
        seedCodexAgentsMd(at: profileURL, overwrite: overwrite)
        // Legacy compatibility for older profiles/tooling still looking for instructions.md.
        seedCodexInstructionsMd(at: profileURL, overwrite: overwrite)
    }

    static func seedCodexConfigToml(at profileURL: URL, overwrite: Bool) {
        let configURL = profileURL.appendingPathComponent("config.toml")
        if FileManager.default.fileExists(atPath: configURL.path), !overwrite {
            repairCodexConfigTomlIfNeeded(at: configURL)
            return
        }

        var configLines = [
            "# CoderIDE Codex Profile — auto-generated",
            "sandbox_mode = \"danger-full-access\"",
            "",
            "[sandbox_workspace_write]",
            "network_access = true",
        ]

        if let mcpPath = mcpServerBinaryPath() {
            configLines.append("")
            configLines.append(contentsOf: coderideMCPSectionLines(binaryPath: mcpPath))
        }

        configLines.append("")
        configLines.append(contentsOf: codexExperimentalFeaturesLines())

        let content = configLines.joined(separator: "\n") + "\n"
        try? content.write(to: configURL, atomically: true, encoding: .utf8)
    }

    static func repairCodexConfigTomlIfNeeded(at configURL: URL) {
        guard let existing = try? String(contentsOf: configURL, encoding: .utf8) else { return }

        var lines = existing.components(separatedBy: .newlines)
        if let mcpPath = mcpServerBinaryPath() {
            lines = upsertCoderideMCPSection(in: lines, binaryPath: mcpPath)
        }
        lines = upsertExperimentalFeaturesSection(in: lines)
        let normalizedExisting = existing.hasSuffix("\n") ? existing : existing + "\n"
        let normalizedUpdated = lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
        guard normalizedUpdated != normalizedExisting else { return }
        try? normalizedUpdated.write(to: configURL, atomically: true, encoding: .utf8)
    }

    static func upsertCoderideMCPSection(in lines: [String], binaryPath: String) -> [String] {
        let sectionHeader = "[mcp_servers.coderide]"
        let replacement = coderideMCPSectionLines(binaryPath: binaryPath)
        var output = lines

        if let start = output.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == sectionHeader }) {
            var end = start + 1
            while end < output.count {
                let trimmed = output[end].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    break
                }
                end += 1
            }
            var section = Array(output[start..<end])
            section = upsertTomlAssignment(in: section, key: "command", value: "\"\(binaryPath)\"")
            section = upsertTomlAssignment(in: section, key: "args", value: "[ \"--workspace\", \".\" ]")
            output.replaceSubrange(start..<end, with: section)
            return output
        }

        while let last = output.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            output.removeLast()
        }
        if !output.isEmpty {
            output.append("")
        }
        output.append(contentsOf: replacement)
        return output
    }

    static func upsertTomlAssignment(in sectionLines: [String], key: String, value: String) -> [String] {
        var updated = sectionLines
        if let lineIndex = updated.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("\(key)=")
                || (trimmed.hasPrefix("\(key) ") && trimmed.contains("="))
        }) {
            let existingLine = updated[lineIndex]
            let leadingWhitespace = String(existingLine.prefix { $0 == " " || $0 == "\t" })
            updated[lineIndex] = "\(leadingWhitespace)\(key) = \(value)"
            return updated
        }

        let insertIndex = max(1, updated.count)
        updated.insert("\(key) = \(value)", at: insertIndex)
        return updated
    }

    static func coderideMCPSectionLines(binaryPath: String) -> [String] {
        [
            "[mcp_servers.coderide]",
            "command = \"\(binaryPath)\"",
            "args = [ \"--workspace\", \".\" ]",
        ]
    }

    static func codexExperimentalFeaturesLines() -> [String] {
        [
            "[features]",
            "js_repl = true",
            "multi_agent = true",
            "apps = true",
            "prevent_idle_sleep = true",
        ]
    }

    static func upsertExperimentalFeaturesSection(in lines: [String]) -> [String] {
        let sectionHeader = "[features]"
        let requiredFeatures: [(key: String, value: String)] = [
            ("js_repl", "true"),
            ("multi_agent", "true"),
            ("apps", "true"),
            ("prevent_idle_sleep", "true"),
        ]
        var output = lines

        if let start = output.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == sectionHeader }) {
            var end = start + 1
            while end < output.count {
                let trimmed = output[end].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { break }
                end += 1
            }
            for (key, value) in requiredFeatures {
                let existsInSection = output[start..<end].contains { line in
                    let t = line.trimmingCharacters(in: .whitespaces)
                    return t.hasPrefix("\(key) ") || t.hasPrefix("\(key)=")
                }
                if !existsInSection {
                    output.insert("\(key) = \(value)", at: end)
                    end += 1
                }
            }
            return output
        }

        while let last = output.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            output.removeLast()
        }
        if !output.isEmpty { output.append("") }
        output.append(contentsOf: codexExperimentalFeaturesLines())
        return output
    }

    static func seedCodexAgentsMd(at profileURL: URL, overwrite: Bool) {
        let agentsURL = profileURL.appendingPathComponent("AGENTS.md")
        if !overwrite && FileManager.default.fileExists(atPath: agentsURL.path) {
            return
        }

        let content = codexInstructionsTemplate
        try? content.write(to: agentsURL, atomically: true, encoding: .utf8)
    }

    static func seedCodexInstructionsMd(at profileURL: URL, overwrite: Bool) {
        let instructionsURL = profileURL.appendingPathComponent("instructions.md")
        if !overwrite && FileManager.default.fileExists(atPath: instructionsURL.path) {
            return
        }

        let content = codexInstructionsTemplate
        try? content.write(to: instructionsURL, atomically: true, encoding: .utf8)
    }
}
