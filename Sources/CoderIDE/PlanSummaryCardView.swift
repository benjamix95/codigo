import SwiftUI

struct PlanSummaryCardView: View {
    let title: String
    let summaryMarkdown: String
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onExpandPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Writing plan")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onToggleCollapse) {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Espandi piano" : "Comprimi piano")
            }

            if !isCollapsed {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 6) {
                    let lines = summaryMarkdown
                        .components(separatedBy: .newlines)
                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    ForEach(Array(lines.prefix(14).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.92))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack {
                    Spacer()
                    Button(action: onExpandPlan) {
                        Text("Expand plan")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.8)
        )
    }
}
