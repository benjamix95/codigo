import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
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
}
