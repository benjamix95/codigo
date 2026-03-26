import Foundation

/// Skill Markdown in `~/.solocode/skills` (**globale**) e in **`<progetto>/.solocode/skills`** (per workspace).
/// Fuse nel `InstructionPolicyBundle`: prima le skill di progetto (una cartella per root workspace), poi le globali.
public enum SoloCodeSkillsPolicySource {
    private static let maxCharsPerFile = 24_000

    public static var globalSkillsDirectoryPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".solocode/skills")
    }

    public static func projectSkillsDirectoryPath(forProjectRoot projectRoot: String) -> String {
        let trimmed = projectRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed as NSString).appendingPathComponent(".solocode/skills")
    }

    /// Crea `~/.solocode/skills` se assente.
    public static func ensureSkillsDirectoryExists() {
        let dir = globalSkillsDirectoryPath
        guard !FileManager.default.fileExists(atPath: dir) else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    /// Crea `<root>/.solocode/skills` se assente.
    public static func ensureProjectSkillsDirectory(forProjectRoot root: String) {
        let trimmed = root.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let dir = projectSkillsDirectoryPath(forProjectRoot: trimmed)
        guard !FileManager.default.fileExists(atPath: dir) else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    public static func ensureProjectSkillsDirectories(forWorkspacePaths paths: [String]) {
        for r in projectSkillRoots(from: paths) {
            ensureProjectSkillsDirectory(forProjectRoot: r)
        }
    }

    public struct InstructionItem: Sendable {
        public let title: String
        public let sourcePath: String
        public let displayPath: String
        public let content: String
    }

    // MARK: - Policy merge

    public static func instructionPolicyItems(workspacePaths: [String] = []) -> [InstructionItem] {
        ensureSkillsDirectoryExists()
        var out: [InstructionItem] = []
        for root in projectSkillRoots(from: workspacePaths) {
            ensureProjectSkillsDirectory(forProjectRoot: root)
            let dir = projectSkillsDirectoryPath(forProjectRoot: root)
            let label = shortPathLabel(root)
            out.append(contentsOf: loadInstructionItems(skillsDirectory: dir, kind: "project", locationLabel: label))
        }
        out.append(contentsOf: loadInstructionItems(
            skillsDirectory: globalSkillsDirectoryPath,
            kind: "global",
            locationLabel: "~/.solocode/skills"
        ))
        return out
    }

    public static func skillCatalogLines(workspacePaths: [String] = []) -> [String] {
        ensureSkillsDirectoryExists()
        var lines: [String] = []
        for root in projectSkillRoots(from: workspacePaths) {
            ensureProjectSkillsDirectory(forProjectRoot: root)
            let dir = projectSkillsDirectoryPath(forProjectRoot: root)
            let label = shortPathLabel(root)
            lines.append(contentsOf: catalogLines(skillsDirectory: dir, prefix: "solocode-project (\(label))"))
        }
        lines.append(contentsOf: catalogLines(skillsDirectory: globalSkillsDirectoryPath, prefix: "solocode-global"))
        return lines
    }

    /// Progetto prima, poi globale (shadowing: file omonimo nel progetto vince).
    public static func skillMarkdown(forNormalizedName normalized: String, workspacePaths: [String] = []) -> String? {
        ensureSkillsDirectoryExists()
        let stem = normalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !stem.isEmpty, !stem.contains("/"), !stem.contains("..") else { return nil }

        let fileName = stem.hasSuffix(".md") ? stem : "\(stem).md"

        for root in projectSkillRoots(from: workspacePaths) {
            ensureProjectSkillsDirectory(forProjectRoot: root)
            let dir = projectSkillsDirectoryPath(forProjectRoot: root)
            if let body = readSkillBody(fileName: fileName, skillsDirectory: dir) {
                return body
            }
        }
        return readSkillBody(fileName: fileName, skillsDirectory: globalSkillsDirectoryPath)
    }

    // MARK: - Internals

    private static func projectSkillRoots(from workspacePaths: [String]) -> [String] {
        var roots: [String] = []
        var seen = Set<String>()
        let fm = FileManager.default
        for raw in workspacePaths {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            var url = URL(fileURLWithPath: trimmed).resolvingSymlinksInPath().standardizedFileURL
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                url = url.deletingLastPathComponent()
            }
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let path = url.path
            guard seen.insert(path).inserted else { continue }
            roots.append(path)
        }
        return roots
    }

    private static func shortPathLabel(_ absoluteRoot: String) -> String {
        let home = NSHomeDirectory()
        let shortened = absoluteRoot.replacingOccurrences(of: home, with: "~")
        return URL(fileURLWithPath: shortened).lastPathComponent
    }

    private static func loadInstructionItems(skillsDirectory dir: String, kind: String, locationLabel: String) -> [InstructionItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir),
              let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        return files
            .filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }
            .sorted()
            .compactMap { fileName -> InstructionItem? in
                guard !isDisabled(fileName: fileName, skillsDirectory: dir) else { return nil }
                let path = "\(dir)/\(fileName)"
                guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let body = String(trimmed.prefix(maxCharsPerFile))
                return InstructionItem(
                    title: "Solo Code skill (\(kind), always apply): \(fileName)",
                    sourcePath: path,
                    displayPath: "\(locationLabel)/\(fileName)",
                    content: body
                )
            }
    }

    private static func catalogLines(skillsDirectory dir: String, prefix: String) -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir),
              let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        return files
            .filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }
            .sorted()
            .filter { !isDisabled(fileName: $0, skillsDirectory: dir) }
            .map { fileName in
                let stem = (fileName as NSString).deletingPathExtension
                return "\(prefix): \(stem) (\(fileName); in policy)"
            }
    }

    private static func readSkillBody(fileName: String, skillsDirectory dir: String) -> String? {
        guard !isDisabled(fileName: fileName, skillsDirectory: dir) else { return nil }
        let path = "\(dir)/\(fileName)"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var content = trimmed
        if trimmed.hasPrefix("---"),
           let end = trimmed.range(of: "\n---", range: trimmed.index(trimmed.startIndex, offsetBy: 3)..<trimmed.endIndex) {
            content = String(trimmed[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(content.prefix(30_000))
    }

    private static func isDisabled(fileName: String, skillsDirectory dir: String) -> Bool {
        FileManager.default.fileExists(atPath: "\(dir)/.\(fileName).disabled")
    }
}
