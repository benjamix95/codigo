import Foundation

/// Skill Markdown piatte in `~/.solocode/skills/*.md` gestite dall’app Solo Code.
/// Inserite nel `InstructionPolicyBundle` come istruzioni **sempre attive** (come AGENTS), non solo come elenco opzionale.
public enum SoloCodeSkillsPolicySource {
    private static let maxCharsPerFile = 24_000
    private static var skillsDirectory: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".solocode/skills")
    }

    public struct InstructionItem: Sendable {
        public let title: String
        public let sourcePath: String
        public let displayPath: String
        public let content: String
    }

    /// Sezioni da fondere nel policy bundle (full text, obbligatorio per il modello).
    public static func instructionPolicyItems() -> [InstructionItem] {
        let fm = FileManager.default
        let dir = skillsDirectory
        guard fm.fileExists(atPath: dir),
              let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }

        let home = NSHomeDirectory()
        return files
            .filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }
            .sorted()
            .compactMap { fileName -> InstructionItem? in
                guard !isDisabled(fileName: fileName) else { return nil }
                let path = "\(dir)/\(fileName)"
                guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let body = String(trimmed.prefix(maxCharsPerFile))
                return InstructionItem(
                    title: "Solo Code skill (always apply): \(fileName)",
                    sourcePath: path,
                    displayPath: path.replacingOccurrences(of: home, with: "~"),
                    content: body
                )
            }
    }

    /// Voci per l’elenco «Detected local skills» (discovery).
    public static func skillCatalogLines() -> [String] {
        let fm = FileManager.default
        let dir = skillsDirectory
        guard fm.fileExists(atPath: dir),
              let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        return files
            .filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }
            .sorted()
            .filter { !isDisabled(fileName: $0) }
            .map { fileName in
                let stem = (fileName as NSString).deletingPathExtension
                return "solocode: \(stem) (file \(fileName); content always in policy above)"
            }
    }

    /// Corpo skill per il tool `skill` / esecuzione, nome normalizzato senza estensione (es. `doc-review`).
    public static func skillMarkdown(forNormalizedName normalized: String) -> String? {
        let stem = normalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !stem.isEmpty, !stem.contains("/"), !stem.contains("..") else { return nil }

        let fileName = stem.hasSuffix(".md") ? stem : "\(stem).md"
        let path = "\(skillsDirectory)/\(fileName)"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard !isDisabled(fileName: fileName) else { return nil }
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

    private static func isDisabled(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: "\(skillsDirectory)/.\(fileName).disabled")
    }
}
