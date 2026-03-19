import CoderEngine
import Foundation
import MCP
@testable import CoderIDEMCPServer

extension CoderIDEMCPServerApp {
    static func handleBugHunterTool(
        name: String,
        args: [String: String]
    ) -> CallTool.Result? {
        let bugHunterTools: Set<String> = [
            "bughunter_start", "bughunter_status", "bughunter_findings",
            "bughunter_autofix_preview", "bughunter_autofix_apply", "bughunter_autofix_commit",
            "bughunter_commit_window", "bughunter_install_hook", "bughunter_uninstall_hook",
            "bughunter_run_history", "bughunter_explain_cluster", "bughunter_cancel_run",
        ]
        guard bugHunterTools.contains(name) else { return nil }
        switch name {
        case "bughunter_start": return handleBugHunterStart(args: args)
        case "bughunter_status": return handleBugHunterStatus(args: args)
        case "bughunter_findings": return handleBugHunterFindings(args: args)
        case "bughunter_autofix_preview": return queueBugHunterAction("autofix_preview", args: args)
        case "bughunter_autofix_apply": return queueBugHunterAction("autofix_apply", args: args)
        case "bughunter_autofix_commit": return queueBugHunterAction("autofix_commit", args: args)
        case "bughunter_commit_window": return handleBugHunterCommitWindow(args: args)
        case "bughunter_install_hook": return queueBugHunterAction("install_hook", args: args)
        case "bughunter_uninstall_hook": return queueBugHunterAction("uninstall_hook", args: args)
        case "bughunter_run_history": return handleBugHunterRunHistory(args: args)
        case "bughunter_explain_cluster": return handleBugHunterExplainCluster(args: args)
        case "bughunter_cancel_run": return queueBugHunterAction("cancel_run", args: args)
        default: return reviewError("Unknown bugHunter tool: \(name)")
        }
    }

    static func bugHunterOK(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(message)], isError: nil)
    }

    static func bugHunterError(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(message)], isError: true)
    }

    static func handleBugHunterStart(args: [String: String]) -> CallTool.Result {
        let sourceKind = (args["source_kind"] ?? "uncommitted")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let gitRoot = (args["git_root"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let runId = "bughunter-\(UUID().uuidString.lowercased())"
        let payload = args.merging([
            "run_id": runId,
            "source_kind": sourceKind,
            "git_root": gitRoot,
        ]) { _, new in new }

        guard let bridged = rustBugHunterToolResult(name: "bughunter_start", args: payload) else {
            return bugHunterError("Error: Rust review core unavailable for bughunter_start")
        }
        if bridged.isError == true {
            return bridged
        }
        guard MCPSharedState.enqueueBugHunterCommandRustOnly(
            action: "start",
            runId: runId,
            conversationId: parseConversationId(args["conversation_id"]),
            payload: payload
        ) != nil else {
            return bugHunterError("Error: Rust bugHunter queue unavailable for bughunter_start")
        }
        return bugHunterOK("OK — bugHunter start queued (run_id=\(runId), source_kind=\(sourceKind))")
    }

    static func handleBugHunterStatus(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustBugHunterToolResult(name: "bughunter_status", args: args) else {
            return bugHunterError("Error: Rust review core unavailable for bughunter_status")
        }
        return bridged
    }

    static func handleBugHunterFindings(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustBugHunterToolResult(name: "bughunter_findings", args: args) else {
            return bugHunterError("Error: Rust review core unavailable for bughunter_findings")
        }
        return bridged
    }

    static func handleBugHunterRunHistory(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustBugHunterToolResult(name: "bughunter_run_history", args: args) else {
            return bugHunterError("Error: Rust review core unavailable for bughunter_run_history")
        }
        return bridged
    }

    static func handleBugHunterExplainCluster(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustBugHunterToolResult(name: "bughunter_explain_cluster", args: args) else {
            return bugHunterError("Error: Rust review core unavailable for bughunter_explain_cluster")
        }
        return bridged
    }

    static func handleBugHunterCommitWindow(args: [String: String]) -> CallTool.Result {
        if let bridged = rustBugHunterToolResult(name: "bughunter_commit_window", args: args),
           bridged.isError == true {
            return bridged
        }
        guard let gitRoot = args["git_root"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !gitRoot.isEmpty,
              let primaryCommit = args["primary_commit"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !primaryCommit.isEmpty else {
            return bugHunterError("Error: 'git_root' and 'primary_commit' are required")
        }
        return handleBugHunterStart(
            args: args.merging([
                "source_kind": MCPSharedBugHunterSourceKind.commitWindow.rawValue,
                "git_root": gitRoot,
                "primary_commit": primaryCommit,
            ]) { _, new in new }
        )
    }

    static func queueBugHunterAction(
        _ action: String,
        args: [String: String]
    ) -> CallTool.Result {
        let toolName = "bughunter_\(action)"
        if let bridged = rustBugHunterToolResult(name: toolName, args: args) {
            if bridged.isError == true {
                return bridged
            }
            let runId = (args["run_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !runId.isEmpty else {
                return bugHunterError("Error: 'run_id' is required")
            }
            guard MCPSharedState.enqueueBugHunterCommandRustOnly(
                action: action,
                runId: runId,
                conversationId: parseConversationId(args["conversation_id"]),
                payload: args
            ) != nil else {
                return bugHunterError("Error: Rust bugHunter queue unavailable for \(toolName)")
            }
            return bridged
        }
        let runId = (args["run_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !runId.isEmpty else {
            return bugHunterError("Error: 'run_id' is required")
        }
        return bugHunterError("Error: Rust review core unavailable for \(toolName)")
    }
}
