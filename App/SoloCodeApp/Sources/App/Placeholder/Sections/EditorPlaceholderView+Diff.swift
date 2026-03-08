import SwiftUI

extension EditorPlaceholderView {
    // MARK: - Diff View
    func diffInlineView(path: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let diff = openFilesStore.diff(for: path) {
                    if diff.isBinary {
                        Text("Binary file changed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(12)
                    } else if diff.chunks.isEmpty {
                        Text("No diff available")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(12)
                    } else {
                        ForEach(Array(diff.chunks.enumerated()), id: \.offset) { _, chunk in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(chunk.header)
                                    .codeFont(
                                        size: FontPreferences.sanitizeSize(uiCodeFontSize - 1, kind: .code),
                                        family: uiCodeFontFamily,
                                        weight: .semibold
                                    )
                                    .foregroundStyle(Color.accentColor.opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.accentColor.opacity(0.08))

                                ForEach(Array(chunk.lines.prefix(3000).enumerated()), id: \.offset) { _, line in
                                    diffLine(line)
                                }
                            }
                            .background(DesignSystem.Colors.backgroundSecondary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8).strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
                            )
                        }
                    }
                } else {
                    Text("Diff not loaded")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .padding(8)
        }
        .background(DesignSystem.Colors.backgroundDeep)
    }

    private func diffLine(_ line: String) -> some View {
        let prefix = line.first ?? " "
        let bg: Color = {
            switch prefix {
            case "+": return DesignSystem.Colors.success.opacity(0.12)
            case "-": return DesignSystem.Colors.error.opacity(0.12)
            default: return .clear
            }
        }()
        return Text(line.isEmpty ? " " : line)
            .codeFont(size: FontPreferences.sanitizeSize(uiCodeFontSize - 1, kind: .code), family: uiCodeFontFamily)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg)
    }
}
