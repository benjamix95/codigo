import Foundation

/// Pure-function helpers shared between CoderIDEMCPServer and tests.
/// These have no MCP dependencies — only Foundation and SubagentRole.
public enum SubagentCLIConfig {

    /// Whether a subagent role should run in read-only sandbox mode.
    /// Explorer, reviewer, and securityAuditor only analyze — they never edit files.
    public static func isReadOnly(_ role: SubagentRole) -> Bool {
        switch role {
        case .explorer, .reviewer, .securityAuditor:
            return true
        case .coder, .debugger, .testWriter, .docWriter:
            return false
        }
    }

    /// Timeout in seconds: read-only roles get a shorter budget.
    public static func timeout(for role: SubagentRole) -> TimeInterval {
        // Keep subagent execution safely under common MCP tools/call deadlines (120s),
        // otherwise the client can time out before this process reports its own timeout.
        isReadOnly(role) ? 95 : 110
    }

    /// Build CLI arguments for a given backend (codex, claude, gemini).
    public static func buildCLIArgs(
        cliPath: String,
        prompt: String,
        workspacePath: String,
        readOnly: Bool
    ) -> [String] {
        let basename = URL(fileURLWithPath: cliPath).lastPathComponent.lowercased()

        switch basename {
        case "codex":
            var args = ["exec", "--full-auto"]
            if readOnly {
                args += ["--sandbox", "read-only"]
            } else {
                args += ["--sandbox", "workspace-write"]
            }
            args += ["--cd", workspacePath, prompt]
            return args

        case "claude":
            var args = ["-p", prompt, "--output-format", "text"]
            if readOnly {
                args.append(contentsOf: ["--allowedTools", "Read,Search,Glob,Grep"])
            }
            return args

        case "gemini":
            return ["-p", prompt]

        default:
            return [prompt]
        }
    }
}
