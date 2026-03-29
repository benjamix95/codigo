import SwiftUI

struct ToolTraceFileChangeDiffLinesView: View {
    let lines: [ToolTraceFileChangeDiffLine]
    var lineLimit: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines) { line in
                Text(verbatim: line.text.isEmpty ? " " : line.text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(line.style.color)
                    .lineLimit(lineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
