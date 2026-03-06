import SwiftUI
import CoderEngine

extension CodeReviewPanelView {
    // MARK: - Finding Detail View

    @ViewBuilder
    func findingDetailView(
        _ finding: CodeReviewFinding,
        onApplyFix: @escaping (String) -> Void,
        onDismiss: @escaping (String) -> Void,
        onOpenFile: @escaping (String) -> Void,
        onBack: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            detailHeader(finding, onBack: onBack)
            Divider().opacity(0.2)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    detailLocationSection(finding, onOpenFile: onOpenFile)
                    detailMessageSection(finding)
                    if let fix = finding.suggestedFix, !fix.isEmpty {
                        detailSuggestedFixSection(fix)
                    }
                    if !finding.comments.isEmpty {
                        detailCommentsSection(finding.comments)
                    }
                    detailActionsSection(finding, onApplyFix: onApplyFix, onDismiss: onDismiss)
                }
                .padding(12)
            }
        }
    }

    // MARK: - Detail Header

    private func detailHeader(
        _ finding: CodeReviewFinding,
        onBack: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(findingSeverityColor(finding.severity))
                .frame(width: 3, height: 14)

            Text(finding.severity.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(findingSeverityColor(finding.severity))

            Spacer()

            Text(finding.id.prefix(8))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Location Section

    private func detailLocationSection(
        _ finding: CodeReviewFinding,
        onOpenFile: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LOCATION")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.quaternary)
                .tracking(0.6)

            Button {
                onOpenFile(finding.filePath)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))
                    Text(finding.filePath)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                    if let ln = finding.lineNumber {
                        Text(":\(ln)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.quaternary)
                        if let eln = finding.endLineNumber {
                            Text("-\(eln)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
                .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Message Section

    private func detailMessageSection(_ finding: CodeReviewFinding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DESCRIPTION")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.quaternary)
                .tracking(0.6)

            Text(finding.message)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.primary.opacity(0.85))
                .textSelection(.enabled)
        }
    }

    // MARK: - Suggested Fix Section

    private func detailSuggestedFixSection(_ fix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SUGGESTED FIX")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.quaternary)
                .tracking(0.6)

            Text(fix)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.8))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                )
                .textSelection(.enabled)
        }
    }

    // MARK: - Comments Section

    private func detailCommentsSection(_ comments: [FindingComment]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COMMENTS (\(comments.count))")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.quaternary)
                .tracking(0.6)

            ForEach(comments, id: \.id) { comment in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(comment.author)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(accent)
                        Spacer()
                        Text(comment.createdAt, style: .relative)
                            .font(.system(size: 8))
                            .foregroundStyle(.quaternary)
                    }
                    Text(comment.content)
                        .font(.system(size: 10))
                        .foregroundStyle(.primary.opacity(0.8))
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                )
            }
        }
    }

    // MARK: - Actions Section

    private func detailActionsSection(
        _ finding: CodeReviewFinding,
        onApplyFix: @escaping (String) -> Void,
        onDismiss: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            if finding.status == .open {
                Button {
                    onApplyFix(finding.id)
                } label: {
                    Label("Apply Fix", systemImage: "wrench.and.screwdriver")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.small)
            }

            if finding.status == .open {
                Button {
                    onDismiss(finding.id)
                } label: {
                    Label("Dismiss", systemImage: "xmark.circle")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()
        }
        .disabled(isTaskRunning)
        .opacity(isTaskRunning ? 0.72 : 1)
    }
}
