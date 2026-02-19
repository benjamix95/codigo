import Foundation

/// Gestione lettura/scrittura di AGENTS.md per Codex CLI
public enum CodexAgentsFile {
    private static var codexHome: String {
        ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(NSHomeDirectory())/.codex"
    }

    /// Path del file globale ~/.codex/AGENTS.md
    public static var globalPath: String {
        "\(codexHome)/AGENTS.md"
    }

    /// Legge il contenuto di AGENTS.md globale
    public static func loadGlobal() -> String {
        (try? String(contentsOfFile: globalPath, encoding: .utf8)) ?? ""
    }

    /// Scrive il contenuto di AGENTS.md globale
    public static func saveGlobal(_ content: String) {
        let dir = (globalPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? content.write(toFile: globalPath, atomically: true, encoding: .utf8)
    }

    /// Cerca AGENTS.md nel progetto (dalla root git risalendo)
    public static func loadProject(workspacePath: String) -> String? {
        let fm = FileManager.default
        var dir = workspacePath
        while dir != "/" {
            let candidate = (dir as NSString).appendingPathComponent("AGENTS.md")
            if fm.fileExists(atPath: candidate) {
                return try? String(contentsOfFile: candidate, encoding: .utf8)
            }
            let override = (dir as NSString).appendingPathComponent("AGENTS.override.md")
            if fm.fileExists(atPath: override) {
                return try? String(contentsOfFile: override, encoding: .utf8)
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Scrive AGENTS.md nella root del progetto
    public static func saveProject(_ content: String, workspacePath: String) {
        let path = (workspacePath as NSString).appendingPathComponent("AGENTS.md")
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
