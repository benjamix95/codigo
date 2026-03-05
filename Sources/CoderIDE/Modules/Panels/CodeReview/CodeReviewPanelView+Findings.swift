import SwiftUI
import CoderEngine

extension CodeReviewPanelView {
    // MARK: - Findings List

    @ViewBuilder
    func findingsListView(
        _ findings: [CodeReviewFinding],
        selectedFindingId: Binding<String?>
    ) -> some View {
        if findings.isEmpty {
            emptyFindingsPlaceholder
        } else {
            findingsContent(findings, selectedFindingId: selectedFindingId)
        }
    }

    // MARK: - Empty Placeholder

    private var emptyFindingsPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No findings yet")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Text("Start a review to analyze your code")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Findings Content

    private func findingsContent(
        _ findings: [CodeReviewFinding],
        selectedFindingId: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            findingsSummaryBar(findings)
            Divider().opacity(0.2)
            findingsScrollList(findings, selectedFindingId: selectedFindingId)
        }
    }

    // MARK: - Summary Bar

    private func findingsSummaryBar(_ findings: [CodeReviewFinding]) -> some View {
        let grouped = Dictionary(grouping: findings, by: \.severity)
        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
            Text("FINDINGS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Spacer()
            ForEach(FindingSeverity.allCases, id: \.rawValue) { sev in
                let count = grouped[sev]?.count ?? 0
                if count > 0 {
                    findingSeverityPill(sev, count: count)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func findingSeverityPill(
        _ severity: FindingSeverity,
        count: Int
    ) -> some View {
        let color = findingSeverityColor(severity)
        return HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1), in: Capsule())
    }

    // MARK: - Scroll List

    private func findingsScrollList(
        _ findings: [CodeReviewFinding],
        selectedFindingId: Binding<String?>
    ) -> some View {
        let sorted = findings.sorted { $0.severity.sortOrder < $1.severity.sortOrder }
        return ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 2) {
                ForEach(sorted, id: \.id) { finding in
                    findingRow(finding, isSelected: selectedFindingId.wrappedValue == finding.id)
                        .onTapGesture {
                            selectedFindingId.wrappedValue = finding.id
                        }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Finding Row

    private func findingRow(
        _ finding: CodeReviewFinding,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(findingSeverityColor(finding.severity))
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
                    findingStatusBadge(finding.status)
                }

                Text(finding.message)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.primary.opacity(0.75))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    findingCategoryTag(finding.category)
                    findingSeverityTag(finding.severity)
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
                .fill(isSelected
                      ? accent.opacity(0.08)
                      : Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isSelected
                    ? accent.opacity(0.3)
                    : DesignSystem.Colors.border.opacity(0.3),
                    lineWidth: 0.5
                )
        )
        .contentShape(Rectangle())
    }

    // MARK: - Severity / Status / Category Helpers

    func findingSeverityColor(_ severity: FindingSeverity) -> Color {
        switch severity {
        case .critical: return DesignSystem.Colors.error
        case .warning: return DesignSystem.Colors.warning
        case .suggestion: return DesignSystem.Colors.info
        case .info: return .secondary
        }
    }

    private func findingStatusBadge(_ status: FindingStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .open: return ("Open", accent)
            case .fixApplied: return ("Fixed", DesignSystem.Colors.success)
            case .dismissed: return ("Dismissed", .secondary)
            case .wontFix: return ("Won't Fix", .secondary)
            }
        }()
        return Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.1), in: Capsule())
    }

    private func findingCategoryTag(_ category: FindingCategory) -> some View {
        Text(category.rawValue.capitalized)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.primary.opacity(0.04), in: Capsule())
    }

    private func findingSeverityTag(_ severity: FindingSeverity) -> some View {
        let color = findingSeverityColor(severity)
        return Text(severity.rawValue.capitalized)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.08), in: Capsule())
    }
}
