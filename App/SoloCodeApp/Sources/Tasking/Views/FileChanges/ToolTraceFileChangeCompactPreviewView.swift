import SwiftUI

struct ToolTraceFileChangeCompactPreviewView: View {
    let change: ToolTraceFileChange
    var maxLines: Int = 4
    var showsBackground: Bool = true
    var compactPadding: CGFloat = 8

    var body: some View {
        if let previewText = change.compactPreviewText(limit: maxLines) {
            Text(previewText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.horizontal, compactPadding)
                .padding(.vertical, 6)
                .background(backgroundView)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if showsBackground {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.22))
        } else {
            Color.clear
        }
    }
}
