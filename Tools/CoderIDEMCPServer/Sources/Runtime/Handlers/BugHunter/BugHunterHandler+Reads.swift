import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handleBugHunterStatus(args: [String: String]) -> CallTool.Result {
        guard let snapshot = resolveBugHunterSnapshot(args: args) else {
            return bugHunterOK("No BugHunter run found.")
        }
        let effectiveStatus = bugHunterEffectiveStatus(snapshot)
        var lines = [
            "run_id: \(snapshot.runId)",
            "status: \(effectiveStatus.rawValue)",
            "source_kind: \(snapshot.sourceKind.rawValue)",
            "trigger_kind: \(snapshot.triggerKind.rawValue)",
            "git_root: \(snapshot.gitRoot)",
        ]
        if let reviewSessionId = snapshot.reviewSessionId {
            lines.append("review_session_id: \(reviewSessionId)")
            if let reviewStatus = MCPSharedState.readCodeReviewStatus(sessionId: reviewSessionId) {
                lines.append("review_phase: \(reviewStatus["phase"] ?? "unknown")")
                lines.append("review_summary: \(reviewStatus["summary"] ?? "n/a")")
            }
        }
        if let branchName = snapshot.branchName { lines.append("branch: \(branchName)") }
        if let primaryCommit = snapshot.primaryCommit { lines.append("primary_commit: \(primaryCommit)") }
        if !snapshot.relatedCommits.isEmpty {
            lines.append("related_commits: \(snapshot.relatedCommits.joined(separator: ","))")
        }
        if let lastMessage = snapshot.lastMessage { lines.append("message: \(lastMessage)") }
        return bugHunterOK(lines.joined(separator: "\n"))
    }

    static func handleBugHunterFindings(args: [String: String]) -> CallTool.Result {
        guard let snapshot = resolveBugHunterSnapshot(args: args),
              let reviewSessionId = snapshot.reviewSessionId else {
            return bugHunterOK("No linked review findings available for this BugHunter run.")
        }
        let kind = (args["kind"] ?? "verified").trimmingCharacters(in: .whitespacesAndNewlines)
        let findings = MCPSharedState.readCodeReviewFindings(
            sessionId: reviewSessionId,
            kind: kind,
            severity: args["severity"],
            status: args["status"],
            origin: "bugHunter",
            category: nil,
            file: nil,
            limit: 50,
            includeSensitiveDetails: false
        )
        if findings.isEmpty {
            return bugHunterOK("No BugHunter findings match the query.")
        }
        let lines = findings.enumerated().map { index, finding in
            let message = finding["message"] ?? finding["message_summary"] ?? "n/a"
            let file = finding["file_path"] ?? finding["file_label"] ?? "redacted"
            let line = finding["line_number"].map { ":\($0)" } ?? ""
            return "[\(index + 1)] [\(finding["severity"] ?? "?")] \(file)\(line) — \(message) (status: \(finding["status"] ?? "?"), id: \(finding["id"] ?? "?"))"
        }
        return bugHunterOK(lines.joined(separator: "\n"))
    }

    static func handleBugHunterRunHistory(args: [String: String]) -> CallTool.Result {
        let snapshots = MCPSharedState.readBugHunterSnapshots(
            conversationId: parseConversationId(args["conversation_id"])
        )
        guard !snapshots.isEmpty else { return bugHunterOK("No BugHunter runs found.") }
        let lines = snapshots.map { snapshot in
            "\(snapshot.runId) | \(bugHunterEffectiveStatus(snapshot).rawValue) | \(snapshot.sourceKind.rawValue) | review=\(snapshot.reviewSessionId ?? "n/a") | message=\(snapshot.lastMessage ?? "n/a")"
        }
        return bugHunterOK(lines.joined(separator: "\n"))
    }

    static func handleBugHunterExplainCluster(args: [String: String]) -> CallTool.Result {
        guard let snapshot = resolveBugHunterSnapshot(args: args),
              let reviewSessionId = snapshot.reviewSessionId,
              let reviewSnapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: reviewSessionId) else {
            return bugHunterError("Error: unable to resolve BugHunter cluster context")
        }
        let findings = reviewSnapshot.findings.filter { $0.origin == .bugHunter }
        guard !findings.isEmpty else { return bugHunterOK("No BugHunter cluster available.") }
        let grouped = Dictionary(grouping: findings) { finding in
            finding.message.split(separator: ".").first.map(String.init) ?? finding.message
        }
        guard let top = grouped.max(by: { $0.value.count < $1.value.count }) else {
            return bugHunterOK("No BugHunter cluster available.")
        }
        let files = Array(Set(top.value.map(\.filePath))).sorted()
        let avgConfidence = top.value.compactMap(\.confidence).reduce(0, +) / Double(max(top.value.compactMap(\.confidence).count, 1))
        let lines = [
            "cluster_title: \(top.key)",
            "cluster_size: \(top.value.count)",
            "files: \(files.joined(separator: ", "))",
            String(format: "avg_confidence: %.2f", avgConfidence),
            "primary_risk: \(top.value.first?.category.rawValue ?? "unknown")",
        ]
        return bugHunterOK(lines.joined(separator: "\n"))
    }

    private static func resolveBugHunterSnapshot(
        args: [String: String]
    ) -> MCPSharedBugHunterSnapshot? {
        let runId = (args["run_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !runId.isEmpty {
            return MCPSharedState.readBugHunterSnapshot(runId: runId)
        }
        return MCPSharedState.readBugHunterSnapshots(
            conversationId: parseConversationId(args["conversation_id"])
        ).first
    }

    private static func bugHunterEffectiveStatus(
        _ snapshot: MCPSharedBugHunterSnapshot
    ) -> MCPSharedBugHunterRunStatus {
        guard let reviewSessionId = snapshot.reviewSessionId,
              let reviewSnapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: reviewSessionId) else {
            return snapshot.status
        }
        switch reviewSnapshot.phase {
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .analyzing, .fixing, .testing, .reReviewing:
            return .running
        case .idle:
            return snapshot.status
        }
    }
}
