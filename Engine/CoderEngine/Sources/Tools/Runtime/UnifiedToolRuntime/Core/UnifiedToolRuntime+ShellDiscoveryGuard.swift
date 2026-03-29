import Foundation

extension UnifiedToolRuntime {
    func validateWorkspaceDiscoveryShellUsage(command: String) throws {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("git grep ") || lowered == "git grep" {
            throw ToolRuntimeError.validation(disallowedWorkspaceShellDiscoveryMessage)
        }

        guard let head = shellCommandHead(from: trimmed) else { return }
        let blockedHeads: Set<String> = ["grep", "egrep", "fgrep", "rg", "find", "fd", "cat", "ls", "tree"]
        guard blockedHeads.contains(head) else { return }

        throw ToolRuntimeError.validation(disallowedWorkspaceShellDiscoveryMessage)
    }

    private var disallowedWorkspaceShellDiscoveryMessage: String {
        "Workspace discovery via shell is disabled. Use coderide_semantic_search for intent search, " +
            "coderide_grep for instant text search, coderide_read/read_range for file reads, and " +
            "coderide_list_dir/find_files/glob for file discovery."
    }

    private func shellCommandHead(from command: String) -> String? {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }

        let wrapperTokens: Set<String> = [
            "env", "command", "builtin", "noglob", "time", "exec",
        ]
        for token in tokens {
            var trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            while trimmed.hasPrefix("\\") {
                trimmed.removeFirst()
            }
            guard !trimmed.isEmpty else { continue }
            if wrapperTokens.contains(trimmed.lowercased()) { continue }
            if trimmed.contains("="), !trimmed.hasPrefix("/"), !trimmed.hasPrefix("./") {
                continue
            }
            return URL(fileURLWithPath: trimmed).lastPathComponent.lowercased()
        }
        return nil
    }
}
