import CoderEngine
import Foundation

enum SkillScanner {
    private static let home = NSHomeDirectory()

    static func scan() -> [DetectedSkillItem] {
        var all: [DetectedSkillItem] = []
        all += scanClaudeSkills()
        all += scanClaudePlugins()
        all += scanCodexSkills()
        all += scanCodexPrompts()
        all += scanGeminiConfig()
        all += scanMCPServers()
        return all
    }

    private static func scanClaudeSkills() -> [DetectedSkillItem] {
        scanDirectoryEntries(
            dir: "\(home)/.claude/skills",
            source: .claude,
            kind: .skill
        )
    }

    private static func scanClaudePlugins() -> [DetectedSkillItem] {
        let manifestPath = "\(home)/.claude/plugins/installed_plugins.json"
        let fm = FileManager.default
        guard fm.fileExists(atPath: manifestPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugins"] as? [String: Any] else { return [] }

        return plugins.keys.sorted().map { key in
            let name = key.components(separatedBy: "@").first ?? key
            return DetectedSkillItem(
                id: "claude-plugin-\(key)",
                name: name,
                source: .claude,
                kind: .plugin,
                path: "~/.claude/plugins (\(key))"
            )
        }
    }

    private static func scanCodexSkills() -> [DetectedSkillItem] {
        scanDirectoryEntries(
            dir: "\(home)/.codex/skills",
            source: .codex,
            kind: .skill
        )
    }

    private static func scanCodexPrompts() -> [DetectedSkillItem] {
        let dir = "\(home)/.codex/prompts"
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir),
              let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        return files.sorted().filter { $0.hasSuffix(".md") }.map { file in
            let name = file.replacingOccurrences(of: ".md", with: "")
            return DetectedSkillItem(
                id: "codex-prompt-\(name)",
                name: name,
                source: .codex,
                kind: .prompt,
                path: "~/.codex/prompts/\(file)"
            )
        }
    }

    private static func scanGeminiConfig() -> [DetectedSkillItem] {
        let paths = [
            "\(home)/.config/gemini",
            "\(home)/.gemini"
        ]
        var results: [DetectedSkillItem] = []
        let fm = FileManager.default

        for base in paths {
            guard fm.fileExists(atPath: base),
                  let entries = try? fm.contentsOfDirectory(atPath: base) else { continue }
            for entry in entries.sorted() {
                let full = (base as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: full, isDirectory: &isDir)
                if isDir.boolValue || entry.hasSuffix(".md") || entry.hasSuffix(".json") {
                    let name = entry.replacingOccurrences(of: ".md", with: "").replacingOccurrences(of: ".json", with: "")
                    let shortBase = base.replacingOccurrences(of: home, with: "~")
                    results.append(
                        DetectedSkillItem(
                            id: "gemini-\(name)",
                            name: name,
                            source: .gemini,
                            kind: .command,
                            path: "\(shortBase)/\(entry)"
                        )
                    )
                }
            }
        }
        return results
    }

    private static func scanMCPServers() -> [DetectedSkillItem] {
        MCPConfigLoader.loadDetectedServers().map { server in
            DetectedSkillItem(
                id: "mcp-\(server.id)",
                name: server.name,
                source: .mcp,
                kind: .skill,
                path: "\(server.command) \(server.args.joined(separator: " "))"
            )
        }
    }

    private static func scanDirectoryEntries(
        dir: String,
        source: DetectedSkillItem.SkillSource,
        kind: DetectedSkillItem.SkillKind
    ) -> [DetectedSkillItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir),
              let entries = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        let shortDir = dir.replacingOccurrences(of: home, with: "~")
        return entries.sorted()
            .filter { !$0.hasPrefix(".") }
            .map { entry in
                DetectedSkillItem(
                    id: "\(source.rawValue.lowercased())-\(kind.rawValue.lowercased())-\(entry)",
                    name: entry,
                    source: source,
                    kind: kind,
                    path: "\(shortDir)/\(entry)"
                )
            }
    }
}
