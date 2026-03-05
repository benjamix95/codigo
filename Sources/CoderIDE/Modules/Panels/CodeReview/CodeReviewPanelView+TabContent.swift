import SwiftUI
import CoderEngine

extension CodeReviewPanelView {
    // MARK: - Findings Tab

    @ViewBuilder
    var findingsTab: some View {
        let findings = taskActivityStore.codeReviewFindings

        if let selectedId = selectedFindingId,
           let finding = findings.first(where: { $0.id == selectedId }) {
            findingDetailView(
                finding,
                onApplyFix: { id in
                    onRunSlashCommand("Apply the suggested fix for finding \(id)")
                },
                onDismiss: { id in
                    onRunSlashCommand("Dismiss finding \(id)")
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
                            onRunSlashCommand("Apply all suggested fixes for open findings")
                        },
                        onDismissAll: {
                            onRunSlashCommand("Dismiss all open findings")
                        },
                        onReReview: {
                            onRunSlashCommand("/review-uncommitted")
                        },
                        onExport: {
                            onRunSlashCommand("Export all code review findings as a markdown summary")
                        }
                    )
                }
            }
        }
    }

    // MARK: - Timeline Tab

    var timelineTab: some View {
        timelineView(taskActivityStore.codeReviewEvents)
    }
}
