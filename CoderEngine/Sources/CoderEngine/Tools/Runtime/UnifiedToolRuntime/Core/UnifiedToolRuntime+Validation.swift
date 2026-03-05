import Foundation

extension UnifiedToolRuntime {
    func validate(call: ToolCall, normalizedName: String) throws {
        switch normalizedName {
        case let name where SubagentRole.fromToolName(name) != nil:
            let task = (call.args["task"] ?? call.args["prompt"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if task.isEmpty {
                throw ToolRuntimeError.validation("'task' is required")
            }
        case "read", "write", "edit", "read_range", "list_dir", "read_json", "write_json", "tail_log",
             "str_replace", "create_file":
            let path = call.args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if path.isEmpty && normalizedName != "list_dir" {
                throw ToolRuntimeError.validation("path is required")
            }
        case "grep":
            let query = (call.args["query"] ?? call.args["pattern"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                throw ToolRuntimeError.validation("pattern (or query) is required")
            }
        case "find_symbol", "find_references":
            let query = (call.args["query"] ?? call.args["name"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                throw ToolRuntimeError.validation("query is required")
            }
        case "find_files":
            let query = (call.args["query"] ?? call.args["pattern"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                throw ToolRuntimeError.validation("pattern (or query) is required")
            }
        case "web_search", "search_symbols", "codebase_search", "rename_symbol", "semantic_search":
            let query = call.args["query"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if query.isEmpty {
                throw ToolRuntimeError.validation("query is required")
            }
        case "web_fetch":
            let url = call.args["url"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if url.isEmpty {
                throw ToolRuntimeError.validation("url is required")
            }
        case "browser_navigate":
            let url = call.args["url"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if url.isEmpty {
                throw ToolRuntimeError.validation("url is required")
            }
        case "browser_click":
            let selector = call.args["selector"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if selector.isEmpty {
                throw ToolRuntimeError.validation("selector is required")
            }
        case "browser_type":
            let selector = call.args["selector"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = call.args["text"] ?? ""
            if selector.isEmpty { throw ToolRuntimeError.validation("selector is required") }
            if text.isEmpty { throw ToolRuntimeError.validation("text is required") }
        case "browser_evaluate_js":
            let script = call.args["script"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if script.isEmpty {
                throw ToolRuntimeError.validation("script is required")
            }
        case "list_symbols", "file_outline", "dependency_graph":
            let path = call.args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if path.isEmpty {
                throw ToolRuntimeError.validation("path is required")
            }
        case "bash":
            let command = call.args["command"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if command.isEmpty {
                throw ToolRuntimeError.validation("command is required")
            }
        case "mcp_reconnect", "mcp_restart_server":
            let server = resolveMCPServerArg(from: call.args)
            if server.isEmpty {
                throw ToolRuntimeError.validation("server is required")
            }
        case "mcp", "mcp_call":
            _ = try buildMCPInvocation(call: call)
        case "mcp_batch":
            if (call.args["calls"] ?? "").isEmpty {
                throw ToolRuntimeError.validation("'calls' is required — JSON array of {server, tool, args}")
            }
        case "mcp_read_resource":
            if (call.args["uri"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ToolRuntimeError.validation("'uri' is required")
            }
        case "mcp_subscribe":
            if (call.args["uri"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ToolRuntimeError.validation("'uri' is required")
            }
            if resolveMCPServerArg(from: call.args).isEmpty {
                throw ToolRuntimeError.validation("'server' is required for subscribe")
            }
            let action = (call.args["action"] ?? "subscribe")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !["subscribe", "unsubscribe"].contains(action) {
                throw ToolRuntimeError.validation("Invalid action '\(action)'. Use subscribe or unsubscribe.")
            }
        case "mcp_logs":
            let action = (call.args["action"] ?? "read")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !["read", "set_level", "clear"].contains(action) {
                throw ToolRuntimeError.validation("Invalid action '\(action)'. Use read, set_level, or clear.")
            }
        case "mcp_get_prompt":
            if (call.args["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ToolRuntimeError.validation("'name' is required")
            }
        case "debug_mark":
            let path = (call.args["path"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty {
                throw ToolRuntimeError.validation("path is required")
            }
            let line = Int(call.args["line"] ?? "") ?? 0
            if line <= 0 {
                throw ToolRuntimeError.validation("valid line number is required")
            }
        default:
            break
        }
    }

    func resolveRequiredPath(_ rawPath: String?, context: ToolExecutionContext) throws -> String {
        let allPaths = context.workspaceContext.workspacePaths.map(\.path)
        let preferredRoot = context.workspaceContext.activeRootPath
        guard let path = resolvePath(rawPath, workspacePaths: allPaths, preferredRoot: preferredRoot, sandboxMode: context.policy.sandboxMode) else {
            throw ToolRuntimeError.sandboxViolation("Path is not allowed by sandbox policy")
        }
        return path
    }

    func resolvePath(_ rawPath: String?, workspacePaths: [String], preferredRoot: String?, sandboxMode: String) -> String? {
        let raw = (rawPath ?? ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let isAbsolute = (raw as NSString).isAbsolutePath

        if isAbsolute {
            let resolvedURL = URL(fileURLWithPath: raw).standardizedFileURL
            if sandboxMode == "danger-full-access" {
                return resolvedURL.path
            }
            for ws in workspacePaths {
                let wsURL = URL(fileURLWithPath: ws).standardizedFileURL
                let wsPath = wsURL.path.hasSuffix("/") ? wsURL.path : wsURL.path + "/"
                if resolvedURL.path == wsURL.path || resolvedURL.path.hasPrefix(wsPath) {
                    return resolvedURL.path
                }
            }
            return nil
        }

        let roots: [String]
        if let preferred = preferredRoot, workspacePaths.contains(preferred) {
            roots = [preferred] + workspacePaths.filter { $0 != preferred }
        } else {
            roots = workspacePaths
        }

        for ws in roots {
            let wsURL = URL(fileURLWithPath: ws).standardizedFileURL
            let resolvedURL = wsURL.appendingPathComponent(raw).standardizedFileURL
            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                if sandboxMode == "danger-full-access" {
                    return resolvedURL.path
                }
                let wsPath = wsURL.path.hasSuffix("/") ? wsURL.path : wsURL.path + "/"
                if resolvedURL.path == wsURL.path || resolvedURL.path.hasPrefix(wsPath) {
                    return resolvedURL.path
                }
            }
        }

        let primaryURL = URL(fileURLWithPath: roots[0]).standardizedFileURL
        let resolvedURL = primaryURL.appendingPathComponent(raw).standardizedFileURL
        if sandboxMode == "danger-full-access" {
            return resolvedURL.path
        }
        let primaryPath = primaryURL.path.hasSuffix("/") ? primaryURL.path : primaryURL.path + "/"
        if resolvedURL.path == primaryURL.path || resolvedURL.path.hasPrefix(primaryPath) {
            return resolvedURL.path
        }
        return nil
    }

    func validateShell(command: String, policy: ToolRuntimePolicy) throws {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ToolRuntimeError.validation("Empty command")
        }
        let lower = trimmed.lowercased()

        if !policy.allowDangerousShellPatterns {
            let blockedPatterns = [
                "rm -rf /", ":(){ :|:& };:", "sudo ", "> /dev/sd", "mkfs", "dd if=", "shutdown", "reboot", "kill -9 1"
            ]
            for pattern in blockedPatterns where lower.contains(pattern) {
                throw ToolRuntimeError.sandboxViolation("Command blocked by strict policy")
            }

            if lower.contains(" > /") || lower.contains(" >> /") {
                throw ToolRuntimeError.sandboxViolation("Absolute redirection blocked in strict mode")
            }

            let head = lower.split(separator: " ").first.map(String.init) ?? ""
            let allowlist: Set<String> = [
                "rg", "find", "git", "ls", "cat", "head", "tail", "sed", "awk", "wc", "echo", "pwd", "stat", "which",
                "swift", "ps", "du", "printf", "npm", "pnpm", "yarn", "node", "python", "python3",
                "cargo", "rustc", "go", "make", "cmake", "mkdir", "cp", "mv", "touch", "chmod",
                "curl", "tar", "unzip", "zip", "diff", "sort", "uniq", "xargs", "tee", "env",
                "xcodebuild", "xcrun", "swiftformat", "swiftlint", "prettier", "eslint",
                "fd", "tree", "jq", "gh", "brew", "pip", "pip3", "pod", "bundle", "ruby",
                "docker", "docker-compose", "kubectl", "terraform", "deno", "bun",
                "test", "[", "true", "false", "date", "basename", "dirname", "realpath", "readlink",
                "grep", "egrep", "fgrep", "tr", "cut", "paste", "column", "comm", "join",
            ]
            if !head.isEmpty && !allowlist.contains(head) {
                throw ToolRuntimeError.sandboxViolation("Command not allowed in strict mode: \(head)")
            }
        }
    }
}
