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
        let skills = collectSkillCatalog()
        guard !sections.isEmpty || !skills.isEmpty else {
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
        if !skills.isEmpty {
            lines.append("### Detected local skills")
            lines.append("Invoke with the `skill` tool: skill=<name>, task=<what to do>. Example: skill=doc task=\"create user guide.docx\"")
            for skill in skills {
                lines.append("- \(skill)")
            }
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

    private static func collectSkillCatalog() -> [String] {
        let home = NSHomeDirectory()
        let roots: [(label: String, path: String)] = [
            ("codex", "\(home)/.codex/skills"),
            ("agents", "\(home)/.agents/skills"),
            ("claude", "\(home)/.claude/skills"),
        ]

        var entries: [String] = []
        for root in roots {
            let names = listDirectoryEntries(root.path)
                .filter { !$0.hasPrefix(".") }
                .sorted()
            for name in names {
                entries.append("\(root.label): \(name)")
            }
        }
        return entries
    }

    private static func firstProjectFile(named fileName: String, workspacePaths: [String]) -> String? {
        for workspacePath in workspacePaths {
            guard !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let found = nearestUpwardFile(named: fileName, startingAt: workspacePath) {
                return found
            }
        }
        return nil
    }

    private static func nearestUpwardFile(named fileName: String, startingAt rawPath: String) -> String? {
        let fm = FileManager.default
        var current = URL(fileURLWithPath: rawPath)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: current.path, isDirectory: &isDir), !isDir.boolValue {
            current = current.deletingLastPathComponent()
        }

        while true {
            let candidate = current.appendingPathComponent(fileName).path
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
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
        let roots: [(label: String, path: String)] = [
            ("codex", "\(home)/.codex/skills"),
            ("agents", "\(home)/.agents/skills"),
            ("claude", "\(home)/.claude/skills"),
        ]
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        guard !normalized.isEmpty else { return nil }
        for root in roots {
            let candidates = [
                "\(root.path)/\(normalized)/SKILL.md",
                "\(root.path)/.system/\(normalized)/SKILL.md",
            ]
            for candidate in candidates {
                let url = URL(fileURLWithPath: candidate)
                guard FileManager.default.fileExists(atPath: candidate),
                      let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
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
}
