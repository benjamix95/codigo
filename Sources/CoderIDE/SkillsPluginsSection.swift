import CoderEngine
import SwiftUI

// MARK: - Detected Skill / Plugin

struct DetectedSkillItem: Identifiable {
    let id: String
    let name: String
    let source: SkillSource
    let kind: SkillKind
    let path: String

    enum SkillSource: String {
        case claude = "Claude"
        case codex = "Codex"
        case gemini = "Gemini"
        case mcp = "MCP"
    }

    enum SkillKind: String {
        case skill = "Skill"
        case plugin = "Plugin"
        case prompt = "Prompt"
        case command = "Command"
    }
}

// MARK: - View

struct SkillsPluginsSection: View {
    @State private var items: [DetectedSkillItem] = []
    @State private var isScanning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            hintBox("Skills e plugin vengono rilevati automaticamente da Claude, Codex, Gemini e MCP. Sono disponibili per tutti i provider AI.")

            if isScanning {
                ProgressView("Scansione in corso...")
                    .font(.caption)
                    .padding()
            } else if items.isEmpty {
                emptyState
            } else {
                itemsList
            }

            HStack {
                Button { scanAll() } label: {
                    Label("Aggiorna", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .onAppear { scanAll() }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Skills & Plugins").font(.title3.weight(.semibold))
                Text("Strumenti installati rilevati nel sistema").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "puzzlepiece")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Nessuno skill o plugin rilevato")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Installa skills in ~/.claude/skills/, ~/.codex/skills/ o configura server MCP.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var itemsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            let grouped = Dictionary(grouping: items, by: \.source)
            ForEach([DetectedSkillItem.SkillSource.claude, .codex, .gemini, .mcp], id: \.rawValue) { source in
                if let group = grouped[source], !group.isEmpty {
                    Text(source.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 6)

                    ForEach(group) { item in
                        skillRow(item)
                    }
                }
            }
        }
    }

    private func skillRow(_ item: DetectedSkillItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                    Text(item.kind.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(kindColor(item.kind).opacity(0.15), in: Capsule())
                        .foregroundStyle(kindColor(item.kind))
                }
                Text(item.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func kindColor(_ kind: DetectedSkillItem.SkillKind) -> Color {
        switch kind {
        case .skill: return .blue
        case .plugin: return .purple
        case .prompt: return .orange
        case .command: return .green
        }
    }

    private func hintBox(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary).font(.caption)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Scanning

    private func scanAll() {
        isScanning = true
        Task.detached {
            let results = SkillScanner.scan()
            await MainActor.run {
                items = results
                isScanning = false
            }
        }
    }
}

// MARK: - Scanner

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

    // MARK: Claude

    private static func scanClaudeSkills() -> [DetectedSkillItem] {
        let dir = "\(home)/.claude/skills"
        return scanDirectoryEntries(dir: dir, source: .claude, kind: .skill)
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

    // MARK: Codex

    private static func scanCodexSkills() -> [DetectedSkillItem] {
        let dir = "\(home)/.codex/skills"
        return scanDirectoryEntries(dir: dir, source: .codex, kind: .skill)
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

    // MARK: Gemini

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
                    results.append(DetectedSkillItem(
                        id: "gemini-\(name)",
                        name: name,
                        source: .gemini,
                        kind: .command,
                        path: "\(shortBase)/\(entry)"
                    ))
                }
            }
        }
        return results
    }

    // MARK: MCP

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

    // MARK: Helpers

    private static func scanDirectoryEntries(dir: String, source: DetectedSkillItem.SkillSource, kind: DetectedSkillItem.SkillKind) -> [DetectedSkillItem] {
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
