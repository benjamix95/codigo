import Foundation

/// Gestione lettura/scrittura di CLAUDE.md (globale e progetto)
public enum ClaudeConfigLoader {
    private static var claudeHome: String {
        "\(NSHomeDirectory())/.claude"
    }

    /// Path del file globale ~/.claude/CLAUDE.md
    public static var globalClaudeMdPath: String {
        "\(claudeHome)/CLAUDE.md"
    }

    /// Legge CLAUDE.md globale
    public static func loadClaudeMd() -> String {
        (try? String(contentsOfFile: globalClaudeMdPath, encoding: .utf8)) ?? ""
    }

    /// Scrive CLAUDE.md globale
    public static func saveClaudeMd(_ content: String) {
        let dir = (globalClaudeMdPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? content.write(toFile: globalClaudeMdPath, atomically: true, encoding: .utf8)
    }

    /// Cerca CLAUDE.md nel progetto
    public static func loadProjectClaudeMd(workspacePath: String) -> String? {
        let fm = FileManager.default
        let candidates = [
            (workspacePath as NSString).appendingPathComponent(".claude/CLAUDE.md"),
            (workspacePath as NSString).appendingPathComponent("CLAUDE.md")
        ]
        for path in candidates {
            if fm.fileExists(atPath: path) {
                return try? String(contentsOfFile: path, encoding: .utf8)
            }
        }
        return nil
    }

    /// Scrive CLAUDE.md nella root del progetto
    public static func saveProjectClaudeMd(_ content: String, workspacePath: String) {
        let dir = (workspacePath as NSString).appendingPathComponent(".claude")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent("CLAUDE.md")
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
