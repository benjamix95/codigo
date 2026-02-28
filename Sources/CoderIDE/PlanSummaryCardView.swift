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
                        HStack(spacing: 5) {
                            Text("Open full plan")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}
