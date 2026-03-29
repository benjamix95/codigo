import SwiftUI

struct ToolTraceFileChangeExpandedPreviewCardView: View {
    let change: ToolTraceFileChange
    var maxHeight: CGFloat = 240

    var body: some View {
        if let previewText = change.fullPreviewText {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text("Delta modifiche")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer(minLength: 0)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    Text(previewText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: maxHeight)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.borderSubtle.opacity(0.75), lineWidth: 0.5)
            )
        }
    }
}
