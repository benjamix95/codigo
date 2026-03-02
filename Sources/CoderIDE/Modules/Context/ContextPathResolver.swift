import Foundation

enum ContextPathResolutionResult {
    case resolved(String)
    case notFound
    case ambiguous([String])
}

enum ContextPathResolver {
    static func resolve(reference: String, context: ProjectContext) -> ContextPathResolutionResult {
        let cleaned = sanitize(reference)
        guard !cleaned.isEmpty else { return .notFound }

        if (cleaned as NSString).isAbsolutePath {
            return FileManager.default.fileExists(atPath: cleaned) ? .resolved(cleaned) : .notFound
        }

        if let activeRoot = context.activeFolderPath {
            let activeMatch = (activeRoot as NSString).appendingPathComponent(cleaned)
            if FileManager.default.fileExists(atPath: activeMatch) {
                return .resolved(activeMatch)
            }
        }

        var candidates: [String] = []

        for root in context.folderPaths {
            let candidate = (root as NSString).appendingPathComponent(cleaned)
            guard FileManager.default.fileExists(atPath: candidate) else { continue }
            if !candidates.contains(candidate) {
                candidates.append(candidate)
            }
        }

        if candidates.isEmpty { return .notFound }
        if candidates.count == 1, let first = candidates.first { return .resolved(first) }
        return .ambiguous(candidates)
    }

    private static func sanitize(_ value: String) -> String {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw.split(separator: ":")
        if parts.count >= 2, Int(parts.last ?? "") != nil {
            return parts.dropLast().joined(separator: ":")
        }
        return raw
    }
}
