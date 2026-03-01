import SwiftUI

struct PlanSummaryCardView: View {
    let title: String
    let summaryMarkdown: String
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onExpandPlan: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var summaryPreview: String {
        let raw = summaryMarkdown
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(14)
            .joined(separator: "\n")
        return MermaidExtractor.stripMermaidBlocks(from: raw)
    }

    private var accentColor: Color {
        DesignSystem.Colors.planColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accentColor.opacity(0.7))
                Text("Plan")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
                    .textCase(.uppercase)
                Spacer()
                Button(action: onToggleCollapse) {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand plan" : "Collapse plan")
            }

            if !isCollapsed {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .tracking(-0.2)

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
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(accentColor.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(accentColor.opacity(colorScheme == .dark ? 0.08 : 0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color.primary.opacity(0.025)
                        : Color.primary.opacity(0.015)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.12),
                            Color.primary.opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }
}
