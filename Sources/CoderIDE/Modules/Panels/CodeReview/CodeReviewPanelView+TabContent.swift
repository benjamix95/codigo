import SwiftUI
import CoderEngine

extension CodeReviewPanelView {
    // MARK: - Findings Tab

    @ViewBuilder
    var findingsTab: some View {
        let findings = taskActivityStore.codeReviewFindings(for: conversationId)

        if let selectedId = selectedFindingId,
           let finding = findings.first(where: { $0.id == selectedId }) {
            findingDetailView(
                finding,
                onApplyFix: { id in
                    runCodeReviewCommand("Apply the suggested fix for finding \(id)")
                },
                onDismiss: { id in
                    runCodeReviewCommand("Dismiss finding \(id)")
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
                            runCodeReviewCommand("Apply all suggested fixes for open findings")
                        },
                        onDismissAll: {
                            runCodeReviewCommand("Dismiss all open findings")
                        },
                        onReReview: {
                            runCodeReviewCommand("/review-uncommitted")
                        },
                        onExport: {
                            runCodeReviewCommand("Export all code review findings as a markdown summary")
                        }
                    )
                }
            }
        }
    }

    // MARK: - Timeline Tab

    var timelineTab: some View {
        timelineView(taskActivityStore.codeReviewEvents(for: conversationId))
    }

    private func runCodeReviewCommand(_ command: String) {
        if coderMode != .codeReviewMultiSwarm {
            onSelectMode(.codeReviewMultiSwarm)
        }
        onRunSlashCommand(command)
    }
}
