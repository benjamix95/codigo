import CoderEngine
import SwiftUI

/// Detail view for a single finding with description, suggested fix, comments, and actions.
struct ReviewPanelFindingDetail: View {
    @ObservedObject var store: CodeReviewPanelStore
    let finding: CodeReviewFinding
    let onOpenFile: (String) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailHeader
            Divider().opacity(0.2)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    locationSection
                    messageSection
                    if let fix = finding.suggestedFix, !fix.isEmpty {
                        suggestedFixSection(fix)
                    }
                    if !finding.comments.isEmpty {
                        commentsSection
                    }
                    actionsSection
                }
                .padding(12)
            }
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.accent)
            }
            .buttonStyle(.plain)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(reviewSeverityColor(finding.severity))
                .frame(width: 3, height: 14)

            Text(finding.severity.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(reviewSeverityColor(finding.severity))

            Spacer()

            Text(finding.id.prefix(8))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("LOCATION")
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
                .foregroundStyle(store.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Description

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("DESCRIPTION")
            Text(finding.message)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.85))
                .textSelection(.enabled)
        }
    }

    // MARK: - Suggested Fix

    private func suggestedFixSection(_ fix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("SUGGESTED FIX")
            Text(fix)
                .font(.system(size: 10, design: .monospaced))
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

    // MARK: - Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("COMMENTS (\(finding.comments.count))")
            ForEach(finding.comments, id: \.id) { comment in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(comment.author)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(store.accent)
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

    // MARK: - Actions

    private var actionsSection: some View {
        HStack(spacing: 8) {
            if finding.status == .open, let sessionId = store.selectedSessionId {
                Button {
                    Task { await store.applyFix(sessionId: sessionId, findingId: finding.id) }
                } label: {
                    Label("Apply Fix", systemImage: "wrench.and.screwdriver")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(store.accent)
                .controlSize(.small)

                Button {
                    Task {
                        await store.dismissFinding(
                            sessionId: sessionId, findingId: finding.id, reason: "dismissed"
                        )
                    }
                } label: {
                    Label("Dismiss", systemImage: "xmark.circle")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer()
        }
        .disabled(store.isRunning)
        .opacity(store.isRunning ? 0.72 : 1)
    }

    // MARK: - Helper

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.quaternary)
            .tracking(0.6)
    }
}
