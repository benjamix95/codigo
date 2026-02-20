import Foundation

public struct CoderRuleDocument: Sendable {
    public let name: String
    public let path: String
    public let content: String

    public init(name: String, path: String, content: String) {
        self.name = name
        self.path = path
        self.content = content
    }
}

/// Gestione rules stile Cursor:
/// - globali: ~/.codigo/rules/global/*.md
/// - progetto: <workspace>/.codigo/rules/project/*.md
public enum CoderRulesFile {
    private static var homeDir: String { NSHomeDirectory() }

    public static var globalRulesDir: String {
        (homeDir as NSString).appendingPathComponent(".codigo/rules/global")
    }

    public static func projectRulesDir(workspacePath: String) -> String {
        (workspacePath as NSString).appendingPathComponent(".codigo/rules/project")
    }

    public static func ensureGlobalRulesDir() {
        ensureDirectory(globalRulesDir)
    }

    public static func ensureProjectRulesDir(workspacePath: String) {
        ensureDirectory(projectRulesDir(workspacePath: workspacePath))
    }

    public static func loadGlobalRules() -> [CoderRuleDocument] {
        loadRules(fromDir: globalRulesDir)
    }

    public static func loadProjectRules(workspacePath: String) -> [CoderRuleDocument] {
        loadRules(fromDir: projectRulesDir(workspacePath: workspacePath))
    }

    public static func saveGlobalRule(name: String, content: String) {
        ensureGlobalRulesDir()
        saveRule(at: (globalRulesDir as NSString).appendingPathComponent(sanitizeName(name)), content: content)
    }

    public static func saveProjectRule(name: String, content: String, workspacePath: String) {
        ensureProjectRulesDir(workspacePath: workspacePath)
        let path = (projectRulesDir(workspacePath: workspacePath) as NSString).appendingPathComponent(sanitizeName(name))
        saveRule(at: path, content: content)
    }

    public static func deleteGlobalRule(name: String) {
        let path = (globalRulesDir as NSString).appendingPathComponent(sanitizeName(name))
        try? FileManager.default.removeItem(atPath: path)
    }

    public static func deleteProjectRule(name: String, workspacePath: String) {
        let path = (projectRulesDir(workspacePath: workspacePath) as NSString).appendingPathComponent(sanitizeName(name))
        try? FileManager.default.removeItem(atPath: path)
    }

    public static func rulesPrompt(workspacePath: String?) -> String {
        let global = loadGlobalRules()
        let project = workspacePath.map(loadProjectRules(workspacePath:)) ?? []
        guard !global.isEmpty || !project.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("## Rules attive")
        if !global.isEmpty {
            lines.append("### Global rules (.codigo/rules/global)")
            for rule in global {
                lines.append("- \(rule.name)")
                lines.append("```md")
                lines.append(rule.content)
                lines.append("```")
            }
        }
        if !project.isEmpty {
            lines.append("### Project rules (.codigo/rules/project)")
            for rule in project {
                lines.append("- \(rule.name)")
                lines.append("```md")
                lines.append(rule.content)
                lines.append("```")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func loadRules(fromDir dir: String) -> [CoderRuleDocument] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir),
              let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }

        return files
            .filter { $0.lowercased().hasSuffix(".md") }
            .sorted()
            .compactMap { fileName in
                let path = (dir as NSString).appendingPathComponent(fileName)
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
                return CoderRuleDocument(name: fileName, path: path, content: content)
            }
    }

    private static func sanitizeName(_ raw: String) -> String {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "rule" }
        if !base.lowercased().hasSuffix(".md") { base += ".md" }
        return base.replacingOccurrences(of: "/", with: "-")
    }

    private static func ensureDirectory(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private static func saveRule(at path: String, content: String) {
        let dir = (path as NSString).deletingLastPathComponent
        ensureDirectory(dir)
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
