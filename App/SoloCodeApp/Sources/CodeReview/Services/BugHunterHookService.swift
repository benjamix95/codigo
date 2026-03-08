import CoderEngine
import Foundation

struct BugHunterHookService {
    private let marker = "# CoderIDE BugHunter hook"

    func installPostCommitHook(gitRoot: String) throws {
        let hooksDirectory = URL(fileURLWithPath: gitRoot)
            .appendingPathComponent(".git")
            .appendingPathComponent("hooks")
        try FileManager.default.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)

        let hookScriptURL = hooksDirectory.appendingPathComponent("post-commit.coderide")
        let launcherURL = hooksDirectory.appendingPathComponent("post-commit")
        let eventsPath = MCPSharedState.bugHunterHookEventsFilePath.path
        let sanitizedPath = shellEscape(eventsPath)

        let hookScript = """
        #!/bin/sh
        git_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
        head_sha="$(git rev-parse HEAD 2>/dev/null)" || exit 0
        mkdir -p "$(dirname \(sanitizedPath))"
        printf '%s\\t%s\\t%s\\n' "$(date +%s)" "$git_root" "$head_sha" >> \(sanitizedPath)
        """
        try hookScript.write(to: hookScriptURL, atomically: true, encoding: .utf8)
        try setExecutable(hookScriptURL.path)

        let launcherContent: String
        if let existing = try? String(contentsOf: launcherURL, encoding: .utf8),
           existing.contains("post-commit.coderide") {
            launcherContent = existing
        } else {
            let shebang = "#!/bin/sh\n"
            let prefix = (try? String(contentsOf: launcherURL, encoding: .utf8)) ?? shebang
            let normalizedPrefix = prefix.hasPrefix("#!") ? prefix : shebang + prefix
            launcherContent = normalizedPrefix + "\n\(marker)\nsh \"$(dirname \"$0\")/post-commit.coderide\"\n"
        }

        try launcherContent.write(to: launcherURL, atomically: true, encoding: .utf8)
        try setExecutable(launcherURL.path)
    }

    func uninstallPostCommitHook(gitRoot: String) throws {
        let hooksDirectory = URL(fileURLWithPath: gitRoot)
            .appendingPathComponent(".git")
            .appendingPathComponent("hooks")
        let hookScriptURL = hooksDirectory.appendingPathComponent("post-commit.coderide")
        let launcherURL = hooksDirectory.appendingPathComponent("post-commit")

        try? FileManager.default.removeItem(at: hookScriptURL)
        guard let content = try? String(contentsOf: launcherURL, encoding: .utf8) else { return }
        let filtered = content
            .components(separatedBy: .newlines)
            .filter { !$0.contains(marker) && !$0.contains("post-commit.coderide") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if filtered == "#!/bin/sh" || filtered.isEmpty {
            try? FileManager.default.removeItem(at: launcherURL)
        } else {
            try filtered.appending("\n").write(to: launcherURL, atomically: true, encoding: .utf8)
            try setExecutable(launcherURL.path)
        }
    }

    /// Wraps a string in single quotes for safe shell interpolation,
    /// escaping any embedded single quotes with the `'\''` idiom.
    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func setExecutable(_ path: String) throws {
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: Int16(0o755))]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: path)
    }
}
