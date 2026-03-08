import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static let bugHunterTools: Set<String> = [
        "bughunter_start", "bughunter_status", "bughunter_findings",
        "bughunter_autofix_preview", "bughunter_autofix_apply", "bughunter_autofix_commit",
        "bughunter_commit_window", "bughunter_install_hook", "bughunter_uninstall_hook",
        "bughunter_run_history", "bughunter_explain_cluster",
    ]

    static func handleBugHunterTool(
        name: String,
        args: [String: String]
    ) -> CallTool.Result? {
        guard bugHunterTools.contains(name) else { return nil }
        switch name {
        case "bughunter_start":
            return handleBugHunterStart(args: args)
        case "bughunter_status":
            return handleBugHunterStatus(args: args)
        case "bughunter_findings":
            return handleBugHunterFindings(args: args)
        case "bughunter_autofix_preview":
            return queueBugHunterAction("autofix_preview", args: args)
        case "bughunter_autofix_apply":
            return queueBugHunterAction("autofix_apply", args: args)
        case "bughunter_autofix_commit":
            return queueBugHunterAction("autofix_commit", args: args)
        case "bughunter_commit_window":
            return handleBugHunterCommitWindow(args: args)
        case "bughunter_install_hook":
            return queueBugHunterAction("install_hook", args: args)
        case "bughunter_uninstall_hook":
            return queueBugHunterAction("uninstall_hook", args: args)
        case "bughunter_run_history":
            return handleBugHunterRunHistory(args: args)
        case "bughunter_explain_cluster":
            return handleBugHunterExplainCluster(args: args)
        default:
            return reviewError("Unknown bugHunter tool: \(name)")
        }
    }

    static func bugHunterOK(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(message)], isError: nil)
    }

    static func bugHunterError(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(message)], isError: true)
    }
}
