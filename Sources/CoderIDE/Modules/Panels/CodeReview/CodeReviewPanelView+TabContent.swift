import SwiftUI
import CoderEngine

extension CodeReviewPanelView {
    // MARK: - Findings Tab

    @ViewBuilder
    var findingsTab: some View {
        let sessionId = taskActivityStore.selectedCodeReviewSessionId(for: conversationId)
        let findings = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        )?.findings ?? taskActivityStore.codeReviewFindings(for: conversationId)

        if let selectedId = selectedFindingId,
           let finding = findings.first(where: { $0.id == selectedId }) {
            findingDetailView(
                finding,
                onApplyFix: { id in
                    guard let sessionId else { return }
                    onDispatchAction(.applyFix(sessionId: sessionId, findingId: id))
                },
                onDismiss: { id in
                    guard let sessionId else { return }
                    onDispatchAction(
                        .dismissFinding(
                            sessionId: sessionId,
                            findingId: id,
                            reason: "dismissed"
                        )
                    )
                },
                onOpenFile: { path in
                    onOpenFile(path)
                },
                onBack: {
                    selectedFindingId = nil
                }
            )
        } else {
            VStack(spacing: 0) {
                findingsListView(findings, selectedFindingId: $selectedFindingId)

                if !findings.isEmpty {
                    Divider().opacity(0.2)
                    reviewActionsBar(
                        findings: findings,
                        onApplyAll: {
                            guard let sessionId else { return }
                            let findingIds = findings
                                .filter { $0.status == .open && $0.suggestedFix != nil }
                                .map(\.id)
                            onDispatchAction(.applyAllFixes(sessionId: sessionId, findingIds: findingIds))
                        },
                        onDismissAll: {
                            guard let sessionId else { return }
                            let findingIds = findings
                                .filter { $0.status == .open }
                                .map(\.id)
                            onDispatchAction(
                                .dismissAll(
                                    sessionId: sessionId,
                                    findingIds: findingIds,
                                    reason: "dismissed"
                                )
                            )
                        },
                        onReReview: {
                            guard let sessionId else { return }
                            onDispatchAction(.rerunSession(sessionId: sessionId))
                        },
                        onExport: {
                            guard let sessionId else { return }
                            onDispatchAction(.exportSummary(sessionId: sessionId))
                        }
                    )
                }
            }
        }
    }

    // MARK: - Timeline Tab

    var timelineTab: some View {
        let events = taskActivityStore.codeReviewSnapshot(
            sessionId: taskActivityStore.selectedCodeReviewSessionId(for: conversationId),
            conversationId: conversationId
        )?.events ?? taskActivityStore.codeReviewEvents(for: conversationId)
        return timelineView(events)
    }
}
