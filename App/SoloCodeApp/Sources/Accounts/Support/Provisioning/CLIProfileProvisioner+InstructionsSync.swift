import Foundation
import CoderEngine

struct CLIInstructionsSyncReport: Sendable {
    let writtenPaths: [String]
    let failedPaths: [String]

    var hasFailures: Bool {
        !failedPaths.isEmpty
    }
}

extension CLIProfileProvisioner {
    /// Content used when creating/seeding instruction files.
    /// If a global AGENTS file exists, its content is always used (including empty).
    /// If no global file exists, fall back to the bundled template.
    static func effectiveAgentsContent() -> String {
        let globalPath = CodexAgentsFile.globalPath
        if FileManager.default.fileExists(atPath: globalPath) {
            return (try? String(contentsOfFile: globalPath, encoding: .utf8)) ?? ""
        }
        return codexInstructionsTemplate
    }

    static func syncAgentsContentToManagedAndGlobalProfiles(_ content: String) -> CLIInstructionsSyncReport {
        syncAgentsContentToManagedAndGlobalProfiles(
            content,
            managedProfilesRoot: baseProfilesDir(),
            codexGlobalDirectory: codexGlobalDirectory(),
            claudeGlobalDirectory: claudeGlobalDirectory(),
            geminiGlobalDirectory: geminiGlobalDirectory()
        )
    }

    static func syncAgentsContentToManagedAndGlobalProfiles(
        _ content: String,
        managedProfilesRoot: URL,
        codexGlobalDirectory: URL,
        claudeGlobalDirectory: URL,
        geminiGlobalDirectory: URL
    ) -> CLIInstructionsSyncReport {
        var targets: [String: String] = [:]

        for profile in managedProfileDirectories(provider: .codex, managedProfilesRoot: managedProfilesRoot) {
            addCodexTargets(into: &targets, rootDirectory: profile.path, content: content)
        }
        for profile in managedProfileDirectories(provider: .claude, managedProfilesRoot: managedProfilesRoot) {
            addClaudeManagedTargets(into: &targets, rootDirectory: profile.path, content: content)
        }
        for profile in managedProfileDirectories(provider: .gemini, managedProfilesRoot: managedProfilesRoot) {
            addGeminiTargets(into: &targets, rootDirectory: profile.path, content: content)
        }

        addCodexTargets(into: &targets, rootDirectory: codexGlobalDirectory.path, content: content)
        addClaudeGlobalTargets(into: &targets, rootDirectory: claudeGlobalDirectory.path, content: content)
        addGeminiTargets(into: &targets, rootDirectory: geminiGlobalDirectory.path, content: content)

        let sortedTargets = targets.keys.sorted().map { ($0, targets[$0] ?? "") }
        var writtenPaths: [String] = []
        var failedPaths: [String] = []

        for (path, targetContent) in sortedTargets {
            do {
                try writeAtomically(content: targetContent, path: path)
                writtenPaths.append(path)
            } catch {
                failedPaths.append("\(path): \(error.localizedDescription)")
            }
        }

        return CLIInstructionsSyncReport(writtenPaths: writtenPaths, failedPaths: failedPaths)
    }

    private static func addCodexTargets(into targets: inout [String: String], rootDirectory: String, content: String) {
        insertTarget(into: &targets, path: "\(rootDirectory)/AGENTS.md", content: content)
        insertTarget(into: &targets, path: "\(rootDirectory)/instructions.md", content: content)
    }

    private static func addClaudeManagedTargets(
        into targets: inout [String: String],
        rootDirectory: String,
        content: String
    ) {
        insertTarget(into: &targets, path: "\(rootDirectory)/AGENTS.md", content: content)
        insertTarget(into: &targets, path: "\(rootDirectory)/.claude/CLAUDE.md", content: content)
    }

    private static func addClaudeGlobalTargets(
        into targets: inout [String: String],
        rootDirectory: String,
        content: String
    ) {
        insertTarget(into: &targets, path: "\(rootDirectory)/AGENTS.md", content: content)
        insertTarget(into: &targets, path: "\(rootDirectory)/CLAUDE.md", content: content)
    }

    private static func addGeminiTargets(into targets: inout [String: String], rootDirectory: String, content: String) {
        insertTarget(into: &targets, path: "\(rootDirectory)/AGENTS.md", content: content)
    }

    private static func insertTarget(into targets: inout [String: String], path: String, content: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        let normalized = URL(fileURLWithPath: expandedPath).standardizedFileURL.path
        targets[normalized] = content
    }

    private static func writeAtomically(content: String, path: String) throws {
        let fileURL = URL(fileURLWithPath: path)
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func managedProfileDirectories(provider: CLIProviderKind, managedProfilesRoot: URL) -> [URL] {
        let root = managedProfilesRoot.appendingPathComponent(provider.rawValue, isDirectory: true)
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

    private static func codexGlobalDirectory() -> URL {
        let path = (CodexAgentsFile.globalPath as NSString).deletingLastPathComponent
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func claudeGlobalDirectory() -> URL {
        let raw = ProcessInfo.processInfo.environment["CLAUDE_HOME"] ?? "\(NSHomeDirectory())/.claude"
        let expanded = (raw as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private static func geminiGlobalDirectory() -> URL {
        let raw = ProcessInfo.processInfo.environment["GEMINI_CONFIG_DIR"] ?? "\(NSHomeDirectory())/.gemini"
        let expanded = (raw as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
}
