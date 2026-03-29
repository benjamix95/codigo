import SwiftUI

struct ToolTraceFileChangeCompactPreviewView: View {
    let change: ToolTraceFileChange
    var maxLines: Int = 4
    var showsBackground: Bool = true
    var compactPadding: CGFloat = 8

    var body: some View {
        let previewLines = change.compactPreviewDiffLines(limit: maxLines)
        if !previewLines.isEmpty {
            ToolTraceFileChangeDiffLinesView(lines: previewLines, lineLimit: 1)
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
