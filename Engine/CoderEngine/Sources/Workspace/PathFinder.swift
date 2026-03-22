import Foundation

public enum PathFinder {
    public static func find(executable: String) -> String? {
        find(
            executable: executable,
            pathEnv: ProcessInfo.processInfo.environment["PATH"] ?? "",
            allowInteractiveShellLookup: true,
            includeDefaultCandidates: true
        )
    }

    public static func find(
        executable: String,
        pathEnv: String,
        allowInteractiveShellLookup: Bool,
        includeDefaultCandidates: Bool
    ) -> String? {
        if let fromProcessEnv = findInPath(
            executable: executable,
            pathEnv: pathEnv
        ) {
            return fromProcessEnv
        }

        if allowInteractiveShellLookup,
           let fromShell = findUsingInteractiveShell(executable: executable) {
            return fromShell
        }

        if includeDefaultCandidates {
            for defaultPath in defaultExecutableCandidates(named: executable) {
                if FileManager.default.isExecutableFile(atPath: defaultPath) {
                    return defaultPath
                }
            }
        }
        return nil
    }

    private static func findInPath(executable: String, pathEnv: String) -> String? {
        let paths = pathEnv.split(separator: ":").map(String.init)
        for dir in paths where !dir.isEmpty {
            let fullPath = "\(dir)/\(executable)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }

    private static func findUsingInteractiveShell(executable: String) -> String? {
        // Never block the main thread with Process.waitUntilExit(). During app
        // startup SwiftUI/AttributeGraph can pump the run loop and abort.
        guard !Thread.isMainThread else { return nil }

        do {
            let result = try ProcessSupervisor.runCollectingSync(
                executable: "/bin/zsh",
                arguments: ["-lc", "command -v \(shellEscape(executable)) 2>/dev/null | head -n 1"],
                timeout: 1.5
            )
            guard result.terminationStatus == 0,
                  let text = result.stdout
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty,
                  !text.isEmpty,
                  FileManager.default.isExecutableFile(atPath: text) else {
                return nil
            }
            return text
        } catch {
            return nil
        }
    }

    private static func defaultExecutableCandidates(named executable: String) -> [String] {
        var candidates = [
            "/opt/homebrew/bin/\(executable)",
            "/usr/local/bin/\(executable)",
            "\(NSHomeDirectory())/.npm/bin/\(executable)",
            "\(NSHomeDirectory())/.local/bin/\(executable)",
            "\(NSHomeDirectory())/.yarn/bin/\(executable)",
            "\(NSHomeDirectory())/.bun/bin/\(executable)",
        ]

        // Claude Code is bundled inside Claude Desktop App with a versioned path.
        // Find the most recent installed version dynamically.
        if executable == "claude" {
            if let desktopPath = findClaudeDesktopBinary() {
                candidates.insert(desktopPath, at: 0)
            }
        }

        return candidates
    }

    /// Searches `~/Library/Application Support/Claude/claude-code/` for the latest
    /// versioned Claude Code binary bundled with the Claude Desktop App.
    private static func findClaudeDesktopBinary() -> String? {
        let baseDir = "\(NSHomeDirectory())/Library/Application Support/Claude/claude-code"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: baseDir) else {
            return nil
        }
        // Sort descending to pick the latest version first.
        let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        for version in sorted {
            let candidate = "\(baseDir)/\(version)/claude.app/Contents/MacOS/claude"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func shellEscape(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9._/-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
