import Foundation

extension CodexCLIProvider {
    static func applyGitHeadFallbackIfNeeded(
        payload: inout [String: String],
        workspacePath: String?
    ) {
        guard shouldUseGitHeadFallback(payload: payload) else { return }
        let rawPath = (payload["path"] ?? payload["file"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty else {
            payload["diff_source"] = "unavailable"
            return
        }

        guard let fallback = gitHeadFallback(path: rawPath, workspacePath: workspacePath) else {
            payload["diff_source"] = "unavailable"
            return
        }

        payload["linesAdded"] = "\(max(0, fallback.added))"
        payload["linesRemoved"] = "\(max(0, fallback.removed))"
        if let preview = fallback.diffPreview,
           !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["diffPreview"] = String(preview.prefix(12_000))
        }
        payload["diff_source"] = "git_head_fallback"
    }

    static func shouldUseGitHeadFallback(payload: [String: String]) -> Bool {
        let hasExplicitCounters = ["linesAdded", "linesRemoved", "additions", "deletions"]
            .contains { key in
                let raw = (payload[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return !raw.isEmpty
            }
        let hasDiffPreview = ["diffPreview", "diff", "patch", "unified_diff", "changes_preview"]
            .contains { key in
                let raw = (payload[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return !raw.isEmpty
            }
        return !hasExplicitCounters && !hasDiffPreview
    }

    static func gitHeadFallback(path: String, workspacePath: String?) -> (added: Int, removed: Int, diffPreview: String?)? {
        let workspace = (workspacePath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspace.isEmpty else { return nil }

        guard let gitRoot = try? runProcess(
            executable: "/usr/bin/git",
            arguments: ["-C", workspace, "rev-parse", "--show-toplevel"]
        ).trimmingCharacters(in: .whitespacesAndNewlines),
        !gitRoot.isEmpty else {
            return nil
        }

        guard let pathSpec = gitPathSpec(path: path, gitRoot: gitRoot), !pathSpec.isEmpty else {
            return nil
        }

        let numstat = (try? runProcess(
            executable: "/usr/bin/git",
            arguments: ["-C", gitRoot, "diff", "--numstat", "HEAD", "--", pathSpec]
        ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let diff = (try? runProcess(
            executable: "/usr/bin/git",
            arguments: ["-C", gitRoot, "diff", "--no-color", "--unified=3", "HEAD", "--", pathSpec]
        ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let parsedNumstat = parseNumstatLine(numstat)
        let inferredFromDiff = parsedNumstat == nil ? diffLineCounts(from: diff) : nil
        let added = parsedNumstat?.added ?? inferredFromDiff?.added ?? 0
        let removed = parsedNumstat?.removed ?? inferredFromDiff?.removed ?? 0
        let preview = diff.isEmpty ? nil : diff
        return (added: added, removed: removed, diffPreview: preview)
    }

    static func gitPathSpec(path: String, gitRoot: String) -> String? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        let standardizedRoot = URL(fileURLWithPath: gitRoot).standardizedFileURL.path
        let standardizedPath = URL(fileURLWithPath: trimmedPath).standardizedFileURL.path

        if (trimmedPath as NSString).isAbsolutePath {
            if standardizedPath == standardizedRoot {
                return nil
            }
            guard standardizedPath.hasPrefix(standardizedRoot + "/") else {
                return nil
            }
            let index = standardizedPath.index(standardizedPath.startIndex, offsetBy: standardizedRoot.count + 1)
            return String(standardizedPath[index...])
        }

        return trimmedPath
    }

    static func parseNumstatLine(_ raw: String) -> (added: Int, removed: Int)? {
        guard let first = raw.split(separator: "\n").first else { return nil }
        let parts = first.split(separator: "\t")
        guard parts.count >= 2 else { return nil }
        let added = Int(parts[0]) ?? 0
        let removed = Int(parts[1]) ?? 0
        return (added: max(0, added), removed: max(0, removed))
    }

    static func diffLineCounts(from diff: String) -> (added: Int, removed: Int)? {
        let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var added = 0
        var removed = 0
        for line in trimmed.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("+++")
                || line.hasPrefix("---")
                || line.hasPrefix("@@")
                || line.hasPrefix("diff --git")
                || line.hasPrefix("index ") {
                continue
            }
            if line.hasPrefix("+") {
                added += 1
            } else if line.hasPrefix("-") {
                removed += 1
            }
        }
        return (added: max(0, added), removed: max(0, removed))
    }

    static func runProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "CodexCLIProvider",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: err]
            )
        }
        return out
    }
}
