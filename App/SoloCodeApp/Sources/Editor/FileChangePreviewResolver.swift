import Foundation

enum FileChangePreviewResult: Equatable {
    case diff(String)
    case fileContent(String)
    case metadataOnly(String)

    var text: String {
        switch self {
        case .diff(let value), .fileContent(let value), .metadataOnly(let value):
            return value
        }
    }

    var label: String {
        switch self {
        case .diff: return "Diff"
        case .fileContent: return "File"
        case .metadataOnly: return "Details"
        }
    }
}

actor FileChangePreviewResolver {
    static let shared = FileChangePreviewResolver()

    private let gitService = GitService()
    private let maxPreviewCharacters = 12_000
    private var cache: [UUID: FileChangePreviewResult] = [:]

    func cachedPreview(for eventId: UUID) -> FileChangePreviewResult? {
        cache[eventId]
    }

    func resolvePreview(for change: ToolTraceFileChange, workspaceHints: [String]) async -> FileChangePreviewResult {
        if let cached = cache[change.eventId] {
            return cached
        }

        let result = resolvePreviewUncached(for: change, workspaceHints: workspaceHints)
        cache[change.eventId] = result
        return result
    }

    private func resolvePreviewUncached(
        for change: ToolTraceFileChange,
        workspaceHints: [String]
    ) -> FileChangePreviewResult {
        if let payloadDiff = nonEmpty(change.diffPreview) {
            return .diff(truncated(payloadDiff))
        }

        let absolutePath = Self.resolveAbsolutePath(rawPath: change.path, workspaceHints: workspaceHints)
        if let diff = resolveGitDiff(change: change, absolutePath: absolutePath, workspaceHints: workspaceHints) {
            return diff
        }

        if change.kind == .created || shouldTryFileContent(path: absolutePath) {
            if let absolutePath,
               let content = readFileContent(at: absolutePath)
            {
                return .fileContent(truncated(content))
            }
        }

        return .metadataOnly(metadataSummary(for: change, absolutePath: absolutePath))
    }

    nonisolated static func resolveAbsolutePath(rawPath: String?, workspaceHints: [String]) -> String? {
        guard let rawPath else { return nil }
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fileManager = FileManager.default
        if (trimmed as NSString).isAbsolutePath {
            return URL(fileURLWithPath: trimmed).standardizedFileURL.path
        }

        let hints = workspaceHints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for hint in hints {
            let base = baseDirectory(for: hint, fileManager: fileManager)
            let candidate = URL(fileURLWithPath: base)
                .appendingPathComponent(trimmed)
                .standardizedFileURL
                .path
            if fileManager.fileExists(atPath: candidate) {
                return candidate
            }
        }

        if let first = hints.first {
            let base = baseDirectory(for: first, fileManager: fileManager)
            return URL(fileURLWithPath: base)
                .appendingPathComponent(trimmed)
                .standardizedFileURL
                .path
        }

        return nil
    }

    nonisolated static func resolveOpenPath(for change: ToolTraceFileChange, workspaceHints: [String]) -> String? {
        if let absolute = resolveAbsolutePath(rawPath: change.path, workspaceHints: workspaceHints) {
            return absolute
        }
        let raw = change.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private func resolveGitDiff(
        change: ToolTraceFileChange,
        absolutePath: String?,
        workspaceHints: [String]
    ) -> FileChangePreviewResult? {
        guard let context = resolveGitContext(change: change, absolutePath: absolutePath, workspaceHints: workspaceHints) else {
            return nil
        }

        do {
            let diff = try gitService.fileDiff(
                gitRoot: context.gitRoot,
                path: context.relativePath,
                baseline: .head
            )
            if diff.isBinary {
                return .metadataOnly(metadataSummary(for: change, absolutePath: absolutePath, note: "Binary file."))
            }

            let diffText = renderDiff(diff)
            if !diffText.isEmpty {
                return .diff(truncated(diffText))
            }

            if change.kind == .created || isUntracked(path: context.relativePath, gitRoot: context.gitRoot) {
                let absolute = absolutePath ?? URL(fileURLWithPath: context.gitRoot)
                    .appendingPathComponent(context.relativePath)
                    .standardizedFileURL
                    .path
                if let content = readFileContent(at: absolute) {
                    return .fileContent(truncated(content))
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    private func resolveGitContext(
        change: ToolTraceFileChange,
        absolutePath: String?,
        workspaceHints: [String]
    ) -> (gitRoot: String, relativePath: String)? {
        if let absolutePath {
            let startDirectory = (absolutePath as NSString).deletingLastPathComponent
            if let gitRoot = try? gitService.resolveGitRoot(from: startDirectory) {
                if let relative = relativePath(for: absolutePath, gitRoot: gitRoot) {
                    return (gitRoot, relative)
                }
                if let raw = nonEmpty(change.path) {
                    return (gitRoot, raw)
                }
            }
        }

        for hint in workspaceHints {
            let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let base = Self.baseDirectory(for: trimmed, fileManager: .default)
            guard let gitRoot = try? gitService.resolveGitRoot(from: base) else { continue }

            if let absolutePath,
               let relative = relativePath(for: absolutePath, gitRoot: gitRoot)
            {
                return (gitRoot, relative)
            }
            if let raw = nonEmpty(change.path) {
                return (gitRoot, raw)
            }
        }

        return nil
    }

    private func relativePath(for absolutePath: String, gitRoot: String) -> String? {
        let root = URL(fileURLWithPath: gitRoot).standardizedFileURL.path
        let file = URL(fileURLWithPath: absolutePath).standardizedFileURL.path

        guard file == root || file.hasPrefix(root + "/") else {
            return nil
        }
        if file == root {
            return nil
        }
        let index = file.index(file.startIndex, offsetBy: root.count + 1)
        return String(file[index...])
    }

    private func isUntracked(path: String, gitRoot: String) -> Bool {
        guard let changed = try? gitService.changedFiles(gitRoot: gitRoot) else {
            return false
        }
        let normalizedPath = normalizeRepoPath(path)
        return changed.contains { file in
            normalizeRepoPath(file.path) == normalizedPath && file.status == "??"
        }
    }

    private func renderDiff(_ diff: GitFileDiff) -> String {
        var lines: [String] = []
        for chunk in diff.chunks {
            if !chunk.header.isEmpty {
                lines.append(chunk.header)
            }
            lines.append(contentsOf: chunk.lines)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readFileContent(at absolutePath: String) -> String? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: absolutePath) else { return nil }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: absolutePath), options: [.mappedIfSafe])
            if isBinary(data: data) {
                return nil
            }
            if let utf8 = String(data: data, encoding: .utf8) {
                return utf8
            }
            if let utf16 = String(data: data, encoding: .utf16) {
                return utf16
            }
            return nil
        } catch {
            return nil
        }
    }

    private func shouldTryFileContent(path: String?) -> Bool {
        guard let path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private func metadataSummary(for change: ToolTraceFileChange, absolutePath: String?, note: String? = nil) -> String {
        var lines: [String] = ["\(change.kind.displayTitle) \(change.basename)"]
        if let path = nonEmpty(change.path) {
            lines.append("Path: \(path)")
        } else if let absolutePath {
            lines.append("Path: \(absolutePath)")
        }
        lines.append("Lines: +\(max(0, change.added)) -\(max(0, change.removed))")

        if let note = nonEmpty(note) {
            lines.append(note)
        }

        if let raw = nonEmpty(change.rawOutput) {
            lines.append("")
            lines.append("Output:")
            lines.append(truncated(raw))
        }

        return lines.joined(separator: "\n")
    }

    private func truncated(_ text: String) -> String {
        guard text.count > maxPreviewCharacters else { return text }
        let end = text.index(text.startIndex, offsetBy: maxPreviewCharacters)
        return String(text[..<end])
            + "\n\n... output truncated (\(text.count - maxPreviewCharacters) characters hidden)"
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizeRepoPath(_ path: String) -> String {
        path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "./"))
    }

    private func isBinary(data: Data) -> Bool {
        data.prefix(1024).contains(0)
    }

    private static func baseDirectory(for rawPath: String, fileManager: FileManager) -> String {
        let standardized = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        var isDirectory = ObjCBool(false)
        if fileManager.fileExists(atPath: standardized, isDirectory: &isDirectory), !isDirectory.boolValue {
            return (standardized as NSString).deletingLastPathComponent
        }
        return standardized
    }
}
