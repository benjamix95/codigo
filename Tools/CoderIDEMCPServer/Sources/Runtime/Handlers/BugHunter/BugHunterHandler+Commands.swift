import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handleBugHunterStart(args: [String: String]) -> CallTool.Result {
        if let bridged = rustBugHunterToolResult(name: "bughunter_start", args: args),
           bridged.isError == true {
            return bridged
        }
        let sourceKind = (args["source_kind"] ?? "uncommitted")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let validKinds: Set<String> = [
            MCPSharedBugHunterSourceKind.uncommitted.rawValue,
            MCPSharedBugHunterSourceKind.commit.rawValue,
            MCPSharedBugHunterSourceKind.commitWindow.rawValue,
            MCPSharedBugHunterSourceKind.branchWindow.rawValue,
        ]
        guard validKinds.contains(sourceKind) else {
            return bugHunterError("Error: invalid source_kind '\(sourceKind)'")
        }

        let gitRoot = (args["git_root"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if sourceKind != MCPSharedBugHunterSourceKind.uncommitted.rawValue && gitRoot.isEmpty {
            return bugHunterError("Error: 'git_root' is required for this BugHunter scope")
        }

        let runId = "bughunter-\(UUID().uuidString.lowercased())"
        _ = MCPSharedState.enqueueBugHunterCommand(
            action: "start",
            runId: runId,
            conversationId: parseConversationId(args["conversation_id"]),
            payload: args.merging(["source_kind": sourceKind, "git_root": gitRoot]) { _, new in new }
        )
        MCPSharedState.writeBugHunterSnapshot(
            MCPSharedBugHunterSnapshot(
                runId: runId,
                conversationId: parseConversationId(args["conversation_id"])?.uuidString.lowercased(),
                sourceKind: MCPSharedBugHunterSourceKind(rawValue: sourceKind) ?? .uncommitted,
                triggerKind: .manual,
                gitRoot: gitRoot,
                branchName: args["branch_name"],
                primaryCommit: args["primary_commit"],
                status: .queued,
                lastMessage: "Queued BugHunter run"
            )
        )
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
        if let bridged = rustBugHunterToolResult(name: "bughunter_\(action)", args: args),
           bridged.isError == true {
            return bridged
        }
        let runId = (args["run_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !runId.isEmpty else {
            return bugHunterError("Error: 'run_id' is required")
        }
        guard MCPSharedState.readBugHunterSnapshot(runId: runId) != nil else {
            return bugHunterError("Error: run_id '\(runId)' was not found")
        }
        _ = MCPSharedState.enqueueBugHunterCommand(
            action: action,
            runId: runId,
            conversationId: parseConversationId(args["conversation_id"]),
            payload: args
        )
        return bugHunterOK("OK — bugHunter command queued (action=\(action), run_id=\(runId))")
    }
}
