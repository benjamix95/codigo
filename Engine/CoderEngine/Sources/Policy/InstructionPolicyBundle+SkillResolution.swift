import Foundation

public extension InstructionPolicyBundle {
    /// Resolve skill name to full SKILL.md content (markdown body; frontmatter optional).
    /// - Parameter workspacePaths: Percorsi cartelle workspace; le skill di progetto hanno priorita' sulle globali.
    static func skillContent(for name: String, workspacePaths: [String] = []) -> String? {
        let home = NSHomeDirectory()
        let roots = [
            "\(home)/.codex/skills",
            "\(home)/.agents/skills",
            "\(home)/.claude/skills",
        ]
        let normalized = normalizedSkillToken(forSkillTool: name)
        guard let normalized else { return nil }
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
                if raw.hasPrefix("---"),
                   let end = raw.range(
                    of: "\n---",
                    range: raw.index(raw.startIndex, offsetBy: 3)..<raw.endIndex
                   ) {
                    content = String(raw[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return String(content.prefix(30_000))
            }
        }
        if let solo = SoloCodeSkillsPolicySource.skillMarkdown(
            forNormalizedName: normalized,
            workspacePaths: workspacePaths
        ) {
            return solo
        }
        return nil
    }
}

private extension InstructionPolicyBundle {
    static func normalizedSkillToken(forSkillTool name: String) -> String? {
        if let normalized = normalizedSkillName(name) {
            return normalized
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasSuffix(".md"), trimmed.count > 3 else { return nil }
        return normalizedSkillName(String(trimmed.dropLast(3)))
    }

    static func normalizedSkillName(_ name: String) -> String? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        guard !normalized.isEmpty,
              !normalized.contains("/"),
              !normalized.contains("\\"),
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
}
