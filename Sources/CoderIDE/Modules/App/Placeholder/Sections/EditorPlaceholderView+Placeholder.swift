import SwiftUI

extension EditorPlaceholderView {
    // MARK: - Placeholder
    var placeholderView: some View {
        VStack(spacing: 24) {
            Image(systemName: "curlybraces")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(DesignSystem.Colors.border)

            VStack(spacing: 10) {
                Text("Codigo")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.7))

                if displayPath.isEmpty {
                    Text("Open a project to get started")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                } else {
                    VStack(spacing: 8) {
                        Text("WORKSPACE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.quaternary)
                            .tracking(1.2)

                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.accentColor.opacity(0.5))
                            Text(folderPaths.count > 1
                                 ? folderPaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
                                 : displayPath)
                                .codeFont(
                                    size: FontPreferences.sanitizeSize(uiCodeFontSize, kind: .code),
                                    family: uiCodeFontFamily
                                )
                                .foregroundStyle(.secondary)
                                .lineLimit(2).multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(
                            DesignSystem.Colors.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8).strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
                        )
                    }
                }
            }

            if !displayPath.isEmpty {
                HStack(spacing: 20) {
                    shortcutHint("Explorer", "sidebar.left", "Cmd+B")
                    shortcutHint("Terminal", "terminal", "Ctrl+`")
                    shortcutHint("Chat", "bubble.left", "Cmd+L")
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.backgroundDeep)
    }

    private func shortcutHint(_ title: String, _ icon: String, _ shortcut: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.quaternary)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(shortcut)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(12)
        .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5))
    }
}
