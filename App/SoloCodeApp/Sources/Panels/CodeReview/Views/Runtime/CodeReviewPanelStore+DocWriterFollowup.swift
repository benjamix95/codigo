import AppKit
import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    /// Dopo apply riuscito: attività + task negli appunti per `coderide_subagent_docWriter`.
    func enqueueDocWriterFollowupAfterPatchApplied(finding: CodeReviewFinding, sessionId: String) {
        guard finding.isEligibleForVerifiedBugOrSecurityWorkspace else { return }

        let domain = finding.reviewImmersiveDomainIsSecurity ? "security" : "bug"
        let task = """
        Documenta nel repo (docs / ADR / changelog) il \(domain) risolto con patch applicata e test verdi.
        Finding ID: \(finding.id)
        File: \(finding.filePath)
        Riepilogo: \(finding.message)
        Session review: \(sessionId)
        Includi: causa, fix applicato, esito verifica, eventuali follow-up.
        Strumento MCP: coderide_subagent_docWriter — argomento `task` = questo testo.
        """

        var payload: [String: String] = [
            "finding_id": finding.id,
            "session_id": sessionId,
            "doc_writer_tool": "coderide_subagent_docWriter",
            "review_domain": domain,
        ]
        if let cid = conversationId {
            payload["conversation_id"] = cid.uuidString.lowercased()
        }

        let activity = scopedTaskActivity(
            TaskActivity(
                type: "doc_writer_followup",
                title: "DocWriter — documenta il fix",
                detail: "Task copiato negli appunti: esegui coderide_subagent_docWriter nel chat.",
                payload: payload,
                phase: .planning,
                isRunning: false,
                groupId: "review-doc-\(finding.id.prefix(8))"
            )
        )
        taskActivityStore.addActivity(activity)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(task, forType: .string)

        appendPanelSystemMessage(
            "DocWriter: task di documentazione messo in coda (clipboard) per finding \(finding.id.prefix(8)).",
            kind: .statusNote
        )
    }
}
