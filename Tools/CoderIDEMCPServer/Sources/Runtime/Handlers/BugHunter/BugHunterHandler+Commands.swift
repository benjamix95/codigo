import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
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
