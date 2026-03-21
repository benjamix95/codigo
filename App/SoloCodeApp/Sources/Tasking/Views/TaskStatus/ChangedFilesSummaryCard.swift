import SwiftUI

// MARK: - Changed Files Summary Card (Expandable with chevron)
// Expandable summary list for git changed files.

struct ChangedFilesSummaryCard: View {
    @ObservedObject var gitPanelStore: GitPanelStore
    let onOpenFile: (String) -> Void
    let onUndoAll: () -> Void

    @State private var isExpanded = false

    var body: some View {
        if !gitPanelStore.changedFiles.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Header row - always visible, tappable
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName: isExpanded ? "chevron.down" : "chevron.right"
                        )
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                        Image(systemName: "doc.badge.gearshape")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.agentColor)

                        Text("\(gitPanelStore.changedFiles.count) files changed")
                            .font(.system(size: 12, weight: .semibold))

                        Text("+\(gitPanelStore.totalAdded)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.success)
                        Text("-\(gitPanelStore.totalRemoved)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.error)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Expanded file list
                if isExpanded {
                    Rectangle()
                        .fill(DesignSystem.Colors.border.opacity(0.5))
                        .frame(height: 0.5)
                        .padding(.horizontal, 8)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(gitPanelStore.changedFiles) { file in
                            HStack(spacing: 8) {
                                Button {
                                    onOpenFile(file.path)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: fileIcon(for: file.path))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 14)
                                        Text(file.path)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .buttonStyle(.plain)

                                Text("+\(file.added)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.success)
                                Text("-\(file.removed)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.error)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(0.02))
                            )
                        }

                        // Undo button
                        HStack {
                            Spacer()
                            Button {
                                onUndoAll()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 10))
                                    Text("Undo all changes")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(DesignSystem.Colors.error)
                            }
                            .buttonStyle(.plain)
                            .disabled(gitPanelStore.changedFiles.isEmpty)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.6)
            )
        }
    }

    internal func fileIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "chevron.left.forwardslash.chevron.right"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "toml": return "doc.badge.gearshape"
        case "md", "txt": return "doc.text"
        case "css", "scss": return "paintbrush"
        case "html": return "globe"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        default: return "doc"
        }
    }
}
