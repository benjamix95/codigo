import CoderEngine
import Foundation

enum CodexCustomModelProfileSync {
    static let settingsKey = "codex_custom_gpt54_1m_enabled"
    static let slug = "gpt-5.4"
    static let displayName = "GPT-5.4 1M"
    static let modelContextWindow = 1_000_000
    static let autoCompactTokenLimit = 900_000

    private static let blockStart = "# solocode_codex_gpt54_1m_start"
    private static let blockEnd = "# solocode_codex_gpt54_1m_end"
    private static let managedKeys = ["model_context_window", "model_auto_compact_token_limit"]

    static func allCodexHomes(accounts: [CLIAccount]) -> [String] {
        let homes = [CodexConfigLoader.codexHome] + accounts
            .filter { $0.provider == .codex }
            .map(\.profilePath)

        var seen = Set<String>()
        return homes.compactMap { rawHome in
            let normalized = URL(fileURLWithPath: rawHome)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
            guard seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    static func sync(config: CodexConfig, codexHomes: [String], enabled: Bool) {
        for codexHome in codexHomes {
            let path = CodexConfigLoader.configPath(forCodexHome: codexHome)
            CodexConfigLoader.save(config, to: path)
            syncManagedBlock(at: path, enabled: enabled)
        }
    }

    static func featureEnabledFromDisk(codexHomes: [String]) -> Bool {
        codexHomes.contains { codexHome in
            let path = CodexConfigLoader.configPath(forCodexHome: codexHome)
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
            return hasEnabledPreset(in: content)
        }
    }

    static func shouldShowInjectedModel() -> Bool {
        if UserDefaults.standard.bool(forKey: settingsKey) {
            return true
        }
        let config = CodexConfigLoader.load()
        if config.model?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == slug {
            return true
        }
        guard let content = try? String(contentsOfFile: CodexConfigLoader.configPath, encoding: .utf8) else {
            return false
        }
        return hasEnabledPreset(in: content)
    }

    static func applyPresetIfEnabled(
        to config: CodexConfig,
        enabled: Bool,
        modelOverride: String
    ) -> CodexConfig {
        var updated = config
        guard enabled else { return updated }
        updated.model = slug
        updated.modelReasoningEffort = "high"
        updated.modelVerbosity = "high"
        if updated.fastMode == nil {
            updated.fastMode = true
        }
        if modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.model = slug
        }
        return updated
    }

    static func syncManagedBlock(at path: String, enabled: Bool) {
        let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let updated = applyManagedBlock(to: existing, enabled: enabled)
        guard updated != existing else { return }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? updated.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func hasEnabledPreset(in content: String) -> Bool {
        let lines = content.components(separatedBy: .newlines)
        let hasContext = lines.contains { isActiveManagedAssignment($0, key: "model_context_window", value: "\(modelContextWindow)") }
        let hasAutoCompact = lines.contains {
            isActiveManagedAssignment($0, key: "model_auto_compact_token_limit", value: "\(autoCompactTokenLimit)")
        }
        return hasContext && hasAutoCompact
    }

    private static func applyManagedBlock(to content: String, enabled: Bool) -> String {
        let lines = content.isEmpty ? [] : content.components(separatedBy: .newlines)
        var filtered: [String] = []
        var insideManagedBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == blockStart {
                insideManagedBlock = true
                continue
            }
            if trimmed == blockEnd {
                insideManagedBlock = false
                continue
            }
            if insideManagedBlock || ownsManagedAssignment(line) {
                continue
            }
            filtered.append(line)
        }

        while filtered.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            filtered.removeLast()
        }
        let blockLines = managedBlockLines(enabled: enabled)
        let firstSectionIndex = filtered.firstIndex(where: {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("[") && t.hasSuffix("]")
        }) ?? filtered.count

        var insertAt = firstSectionIndex
        if insertAt > 0, !filtered[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            filtered.insert("", at: insertAt)
            insertAt += 1
        }
        filtered.insert(contentsOf: blockLines, at: insertAt)
        if insertAt + blockLines.count < filtered.count {
            let nextLine = filtered[insertAt + blockLines.count]
            if !nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                filtered.insert("", at: insertAt + blockLines.count)
            }
        }

        return filtered.joined(separator: "\n") + "\n"
    }

    private static func managedBlockLines(enabled: Bool) -> [String] {
        let prefix = enabled ? "" : "# "
        return [
            blockStart,
            "# Preset GPT-5.4 1M gestito da Solo Code Settings",
            "\(prefix)model_context_window = \(modelContextWindow)",
            "\(prefix)model_auto_compact_token_limit = \(autoCompactTokenLimit)",
            blockEnd,
        ]
    }

    private static func ownsManagedAssignment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let uncommented = trimmed.hasPrefix("#")
            ? trimmed.drop(while: { $0 == "#" || $0 == " " || $0 == "\t" })
            : Substring(trimmed)
        guard let equalIndex = uncommented.firstIndex(of: "=") else { return false }
        let key = uncommented[..<equalIndex].trimmingCharacters(in: .whitespaces)
        return managedKeys.contains(key)
    }

    private static func isActiveManagedAssignment(_ line: String, key: String, value: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#") else { return false }
        return trimmed == "\(key) = \(value)"
    }
}
