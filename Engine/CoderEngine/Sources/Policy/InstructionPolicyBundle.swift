import CryptoKit
import Foundation

public struct InstructionPolicyBundle: Sendable, Equatable {
    public let policyText: String
    public let policyHash: String
    public let requiredAckMarker: String

    public var hasPolicy: Bool {
        !policyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(policyText: String, policyHash: String, requiredAckMarker: String) {
        self.policyText = policyText
        self.policyHash = policyHash
        self.requiredAckMarker = requiredAckMarker
    }

    private struct CacheEntry {
        let bundle: InstructionPolicyBundle
        let createdAt: Date
    }

    private static let cacheTTL: TimeInterval = 5
    private static let cacheLock = NSLock()
    private static nonisolated(unsafe) var cacheByWorkspaceKey: [String: CacheEntry] = [:]

    public static func load(workspacePath: String?) -> InstructionPolicyBundle {
        load(workspacePaths: workspacePath.map { [$0] } ?? [])
    }

    public static func load(workspacePaths: [String]) -> InstructionPolicyBundle {
        let cacheKey = workspaceCacheKey(workspacePaths: workspacePaths)
        if let cached = cachedBundle(for: cacheKey) {
            return cached
        }

        let sections = collectPolicySections(workspacePaths: workspacePaths)
        let skillCatalog = collectSkillCatalogSummary()
        guard !sections.isEmpty
                || !skillCatalog.preferredSkills.isEmpty
                || !skillCatalog.additionalSources.isEmpty else {
            let empty = InstructionPolicyBundle(policyText: "", policyHash: "", requiredAckMarker: "")
            storeCachedBundle(empty, for: cacheKey)
            return empty
        }

        var lines: [String] = []
        lines.append("## Instruction sources")
        for section in sections {
            lines.append("### \(section.title) (\(section.displayPath))")
            lines.append("```md")
            lines.append(section.content)
            lines.append("```")
        }
        let skillLines = renderSkillCatalogLines(
            preferredSkills: skillCatalog.preferredSkills,
            additionalSources: skillCatalog.additionalSources
        )
        if !skillLines.isEmpty {
            lines.append(contentsOf: skillLines)
        }
        let policyBody = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !policyBody.isEmpty else {
            let empty = InstructionPolicyBundle(policyText: "", policyHash: "", requiredAckMarker: "")
            storeCachedBundle(empty, for: cacheKey)
            return empty
        }

        let hash = hashForPolicy(policyBody)
        let ackMarker = "policy_ack hash=\(hash)"
        let promptBlock = """
        ## Mandatory instruction policy (hard requirement)
        \(policyBody)

        You MUST acknowledge policy ingestion before any operational tool call.
        Use the `policy_ack` tool with hash=\(hash)
        """
        let bundle = InstructionPolicyBundle(policyText: promptBlock, policyHash: hash, requiredAckMarker: ackMarker)
        storeCachedBundle(bundle, for: cacheKey)
        return bundle
    }

    public static func promptBlock(workspacePaths: [String]) -> String {
        load(workspacePaths: workspacePaths).policyText
    }

    public static func invalidateCache() {
        cacheLock.lock()
        cacheByWorkspaceKey.removeAll()
        cacheLock.unlock()
    }

    static func hashForPolicy(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func workspaceCacheKey(workspacePaths: [String]) -> String {
        workspacePaths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "|")
    }

    private static func cachedBundle(for key: String) -> InstructionPolicyBundle? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let entry = cacheByWorkspaceKey[key] else { return nil }
        if Date().timeIntervalSince(entry.createdAt) <= cacheTTL {
            return entry.bundle
        }
        cacheByWorkspaceKey.removeValue(forKey: key)
        return nil
    }

    private static func storeCachedBundle(_ bundle: InstructionPolicyBundle, for key: String) {
        cacheLock.lock()
        cacheByWorkspaceKey[key] = CacheEntry(bundle: bundle, createdAt: Date())
        if cacheByWorkspaceKey.count > 64 {
            let staleThreshold = Date().addingTimeInterval(-cacheTTL)
            cacheByWorkspaceKey = cacheByWorkspaceKey.filter { _, entry in
                entry.createdAt >= staleThreshold
            }
        }
        cacheLock.unlock()
    }

    // MARK: - Collection

    private struct PolicySection {
        let title: String
        let sourcePath: String
        let displayPath: String
        let content: String
    }

    private static func collectPolicySections(workspacePaths: [String]) -> [PolicySection] {
        let home = NSHomeDirectory()
        var seen = Set<String>()
        var sections: [PolicySection] = []

        let projectCandidates: [(String, String)] = [
            ("AGENTS.md", "Project AGENTS"),
            ("AGENTS.override.md", "Project AGENTS Override"),
            ("CLAUDE.md", "Project CLAUDE"),
        ]

        for (fileName, title) in projectCandidates {
            if let filePath = firstProjectFile(named: fileName, workspacePaths: workspacePaths),
               seen.insert(filePath).inserted,
               let content = readPolicyFile(filePath) {
                sections.append(
                    PolicySection(
                        title: title,
                        sourcePath: filePath,
                        displayPath: filePath.replacingOccurrences(of: home, with: "~"),
                        content: content
                    )
                )
            }
        }

        let globalPath = CodexAgentsFile.globalPath
        if seen.insert(globalPath).inserted, let globalContent = readPolicyFile(globalPath) {
            sections.append(
                PolicySection(
                    title: "Global AGENTS",
                    sourcePath: globalPath,
                    displayPath: globalPath.replacingOccurrences(of: home, with: "~"),
                    content: globalContent
                )
            )
        }

        return sections
    }

    private static func collectSkillCatalogSummary() -> (
        preferredSkills: [String],
        additionalSources: [(label: String, count: Int)]
    ) {
        let home = NSHomeDirectory()
        let roots: [(label: String, path: String)] = [
            ("codex", "\(home)/.codex/skills"),
            ("agents", "\(home)/.agents/skills"),
            ("claude", "\(home)/.claude/skills"),
        ]

        var preferredSkills: [String] = []
        var additionalSources: [(label: String, count: Int)] = []
        for root in roots {
            let names = listDirectoryEntries(root.path)
                .filter { !$0.hasPrefix(".") }
                .sorted()
            if root.label == "codex" {
                preferredSkills = names
            } else if !names.isEmpty {
                additionalSources.append((label: root.label, count: names.count))
            }
        }
        return (preferredSkills: preferredSkills, additionalSources: additionalSources)
    }

    static func renderSkillCatalogLines(
        preferredSkills: [String],
        additionalSources: [(label: String, count: Int)]
    ) -> [String] {
        guard !preferredSkills.isEmpty || !additionalSources.isEmpty else { return [] }

        var lines: [String] = []
        if !preferredSkills.isEmpty {
            lines.append("### Preferred local skills")
            lines.append("Use these by default with the `skill` tool when the task matches.")
            lines.append("Invoke with `skill=<name> task=\"<what to do>\"`.")
            lines.append(preferredSkills.map { "`\($0)`" }.joined(separator: ", "))
        }
        if !additionalSources.isEmpty {
            lines.append("### Additional skill catalogs")
            lines.append("Explore these only when the preferred local skills are not enough:")
            for source in additionalSources where source.count > 0 {
                lines.append("- \(source.label): \(source.count) additional skills available on demand")
            }
        }
        return lines
    }

    private static func firstProjectFile(named fileName: String, workspacePaths: [String]) -> String? {
        for workspacePath in workspacePaths {
            guard !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard let workspaceRoot = workspaceDirectoryURL(for: workspacePath) else { continue }
            if let found = nearestUpwardFile(named: fileName, startingAt: workspacePath, workspaceRoot: workspaceRoot) {
                return found
            }
        }
        return nil
    }

    private static func nearestUpwardFile(named fileName: String, startingAt rawPath: String, workspaceRoot: URL) -> String? {
        let fm = FileManager.default
        var current = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath().standardizedFileURL
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: current.path, isDirectory: &isDir), !isDir.boolValue {
            current = current.deletingLastPathComponent()
        }

        guard isPath(current.path, insideRoot: workspaceRoot.path) else { return nil }

        while true {
            let candidate = current.appendingPathComponent(fileName)
            if let trustedPath = trustedProjectPolicyPath(candidate, workspaceRoot: workspaceRoot) {
                return trustedPath
            }
            if current.path == workspaceRoot.path { break }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    private static func workspaceDirectoryURL(for rawPath: String) -> URL? {
        let fm = FileManager.default
        var url = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath().standardizedFileURL
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
            url = url.deletingLastPathComponent()
        }
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return url
    }

    private static func trustedProjectPolicyPath(_ candidate: URL, workspaceRoot: URL) -> String? {
        let fm = FileManager.default
        guard !isSymlink(candidate) else { return nil }

        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard isPath(resolved.path, insideRoot: workspaceRoot.path) else { return nil }

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: resolved.path, isDirectory: &isDir), !isDir.boolValue else {
            return nil
        }
        return resolved.path
    }

    private static func isSymlink(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else { return false }
        return values.isSymbolicLink ?? false
    }

    private static func readPolicyFile(_ path: String) -> String? {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(20_000))
    }

    private static func listDirectoryEntries(_ path: String) -> [String] {
        guard FileManager.default.fileExists(atPath: path),
              let files = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return []
        }
        return files
    }

    /// Resolve skill name to full SKILL.md content (markdown body; frontmatter optional).
    public static func skillContent(for name: String) -> String? {
        let home = NSHomeDirectory()
        let roots = [
            "\(home)/.codex/skills",
            "\(home)/.agents/skills",
            "\(home)/.claude/skills",
        ]
        guard let normalized = normalizedSkillName(name) else { return nil }
        for root in roots {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL
            let candidates = [
                rootURL.appendingPathComponent(normalized).appendingPathComponent("SKILL.md"),
                rootURL.appendingPathComponent(".system").appendingPathComponent(normalized).appendingPathComponent("SKILL.md"),
            ]
            for candidate in candidates {
                let candidateURL = candidate.standardizedFileURL
                guard isPath(candidateURL.path, insideRoot: rootURL.path),
                      FileManager.default.fileExists(atPath: candidateURL.path),
                      let raw = try? String(contentsOf: candidateURL, encoding: .utf8)
                else { continue }
                var content = raw
                if raw.hasPrefix("---") {
                    if let end = raw.range(of: "\n---", range: raw.index(raw.startIndex, offsetBy: 3)..<raw.endIndex) {
                        content = String(raw[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                return String(content.prefix(30_000))
            }
        }
        return nil
    }

    private static func normalizedSkillName(_ name: String) -> String? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        guard !normalized.isEmpty,
              !normalized.contains("/"),
              !normalized.contains("\\\\"),
              !normalized.contains("..")
        else {
            return nil
        }

        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
        guard normalized.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            return nil
        }
        return normalized
    }

    private static func isPath(_ path: String, insideRoot rootPath: String) -> Bool {
        let normalizedRoot = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
        let rootPrefix = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"
        return path.hasPrefix(rootPrefix)
    }
}
