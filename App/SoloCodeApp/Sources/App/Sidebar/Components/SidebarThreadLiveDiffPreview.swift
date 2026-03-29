import SwiftUI

struct SidebarThreadLiveDiffPreview: View {
    let change: ToolTraceFileChange

    var body: some View {
        if let preview = change.compactPreviewText(limit: 2) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.planColor.opacity(0.9))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(change.basename)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                        if let lineSummary = change.lineSummary {
                            Text(lineSummary)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        }
                    }

                    Text(preview)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(2)
                }
            }
        }
    }
}
