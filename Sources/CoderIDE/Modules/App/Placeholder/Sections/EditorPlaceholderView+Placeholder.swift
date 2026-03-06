import SwiftUI

extension EditorPlaceholderView {
    var placeholderView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DesignSystem.Colors.backgroundDeep,
                    DesignSystem.Colors.backgroundPrimary.opacity(0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 26) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 84, height: 84)
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.41, green: 0.70, blue: 0.98),
                                    Color(red: 0.36, green: 0.84, blue: 0.74)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 10) {
                    Text("Your workspace is ready")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(displayPath.isEmpty ? "Open a project to start editing with the IDE workbench." : "Jump into files, search, terminal and chat from one place.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !displayPath.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(DesignSystem.Colors.info)
                        Text(folderPaths.count > 1
                             ? folderPaths.map { ($0 as NSString).lastPathComponent }.joined(separator: "  •  ")
                             : displayPath)
                            .codeFont(
                                size: FontPreferences.sanitizeSize(uiCodeFontSize, kind: .code),
                                family: uiCodeFontFamily
                            )
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
                    )
                }

                if !displayPath.isEmpty {
                    HStack(spacing: 18) {
                        shortcutHint("Explorer", "sidebar.left", "Cmd+B")
                        shortcutHint("Terminal", "terminal", "Ctrl+`")
                        shortcutHint("Chat", "bubble.left", "Cmd+L")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(36)
    }

    private func shortcutHint(_ title: String, _ icon: String, _ shortcut: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.9))
            Text(shortcut)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
        )
    }
}
