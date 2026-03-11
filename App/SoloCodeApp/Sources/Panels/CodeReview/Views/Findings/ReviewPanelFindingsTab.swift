import CoderEngine
import SwiftUI

/// Findings tab: list view or detail view, with actions bar.
struct ReviewPanelFindingsTab: View {
    @ObservedObject var store: CodeReviewPanelStore
    let onOpenFileAtLocation: (String, Int?) -> Void

    var body: some View {
        let findings = store.currentPublishedFindings

        if let selectedId = store.selectedFindingId,
           let finding = findings.first(where: { $0.id == selectedId })
        {
            ReviewPanelFindingDetail(
                store: store,
                finding: finding,
                onOpenFileAtLocation: onOpenFileAtLocation,
                onBack: { store.selectedFindingId = nil }
            )
        } else {
            VStack(spacing: 0) {
                findingsListView(findings)

                if !findings.isEmpty {
                    Divider().opacity(0.2)
                    ReviewPanelActionsBar(store: store)
                }
            }
        }
    }

    // MARK: - List View

    @ViewBuilder
    private func findingsListView(_ findings: [CodeReviewFinding]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pipeline = store.currentPipelineJobState {
                ReviewPipelineJobCard(state: pipeline)
                    .padding(.horizontal, 10)
            }

            if findings.isEmpty {
                emptyPlaceholder
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    summaryBar(findings)
                    Divider().opacity(0.2)
                    scrollList(findings)
                }
            }

            ReviewPanelOutcomeCard(outcome: store.currentOutcome)
                .padding(.horizontal, 10)
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(emptyStateTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(emptyStateSubtitle)
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyStateTitle: String {
        if let derivedState = store.currentReviewPanelDerivedState {
            return derivedState.emptyStateTitle
        }
        switch store.currentReviewPanelWarmState {
        case .warming:
            return "Preparing review state..."
        case .ready, .failed:
            return store.currentPipelineJobState == nil ? "No findings yet" : "No published findings yet"
        case .idle:
            return "No findings yet"
        }
    }

    // MARK: - Summary Bar

    private func summaryBar(_ findings: [CodeReviewFinding]) -> some View {
        let grouped = store.currentReviewPanelDerivedState?.publishedSeverityCounts ?? [:]
        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(store.accent)
            Text("FINDINGS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Spacer()
            ForEach(FindingSeverity.allCases, id: \.rawValue) { sev in
                let count = grouped[sev] ?? 0
                if count > 0 {
                    severityPill(sev, count: count)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func severityPill(_ severity: FindingSeverity, count: Int) -> some View {
        let color = reviewSeverityColor(severity)
        return HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1), in: Capsule())
    }

    // MARK: - Scroll List

    private func scrollList(_ findings: [CodeReviewFinding]) -> some View {
        return ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 2) {
                ForEach(findings, id: \.id) { finding in
                    findingRow(finding, isSelected: store.selectedFindingId == finding.id)
                        .onTapGesture { store.selectedFindingId = finding.id }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Finding Row

    private func findingRow(_ finding: CodeReviewFinding, isSelected: Bool) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(reviewSeverityColor(finding.severity))
                .frame(width: 2.5)
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(finding.filePath.components(separatedBy: "/").last ?? finding.filePath)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(1)

                    if let ln = finding.lineNumber {
                        Text("L\(ln)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                    Spacer(minLength: 4)
                    let (statusText, statusColor) = reviewStatusLabel(finding.status)
                    Text(statusText)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(statusColor.opacity(0.1), in: Capsule())
                }

                Text(finding.message)
                    .font(.system(size: 10))
                    .foregroundStyle(.primary.opacity(0.75))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(finding.category.rawValue.capitalized)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.04), in: Capsule())

                    let sevColor = reviewSeverityColor(finding.severity)
                    Text(finding.severity.rawValue.capitalized)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(sevColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(sevColor.opacity(0.08), in: Capsule())

                    if !finding.comments.isEmpty {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.quaternary)
                        Text("\(finding.comments.count)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 5)
            .padding(.trailing, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? store.accent.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isSelected ? store.accent.opacity(0.3) : DesignSystem.Colors.border.opacity(0.3),
                    lineWidth: 0.5
                )
        )
        .contentShape(Rectangle())
    }

    private var emptyStateSubtitle: String {
        if let derivedState = store.currentReviewPanelDerivedState {
            return derivedState.emptyStateSubtitle
        }
        if store.currentReviewPanelWarmState == .warming {
            return "The panel is deriving findings and pipeline status off the render path."
        }
        if let pipeline = store.currentPipelineJobState {
            if pipeline.hiddenFindingCount > 0 {
                return "Verification and patch preparation are still gating the findings."
            }
            if pipeline.isTerminal {
                return "The run completed without any publish-ready findings."
            }
            return "The pipeline is still running. Findings appear only after verification and patch preview."
        }
        return "Start a review to analyze your code"
    }
}
