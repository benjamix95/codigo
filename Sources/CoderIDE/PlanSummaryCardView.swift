import SwiftUI

struct PlanSummaryCardView: View {
    let title: String
    let summaryMarkdown: String
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onExpandPlan: () -> Void

    private var summaryPreview: String {
        let raw = summaryMarkdown
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(14)
            .joined(separator: "\n")
        return MermaidExtractor.stripMermaidBlocks(from: raw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Plan")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onToggleCollapse) {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand plan" : "Collapse plan")
            }

            if !isCollapsed {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                MarkdownContentView(
                    content: summaryPreview,
                    context: nil,
                    onFileClicked: { _ in },
                    textAlignment: .leading
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Spacer()
                    Button(action: onExpandPlan) {
                        HStack(spacing: 6) {
                            Text("Open full plan")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(DesignSystem.Colors.border.opacity(0.45), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.4), lineWidth: 0.5)
        )
    }
}
