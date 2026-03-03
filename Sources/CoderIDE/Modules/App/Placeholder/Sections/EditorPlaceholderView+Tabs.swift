import SwiftUI

extension EditorPlaceholderView {
    // MARK: - Tab Bar (Cursor style)
    @ViewBuilder
    var tabBar: some View {
        if !openFilesStore.openPaths.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(openFilesStore.openPaths, id: \.self) { tabPath in
                        cursorTab(path: tabPath)
                    }
                }
            }
            .frame(height: 34)
            .background(DesignSystem.Colors.backgroundPrimary)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DesignSystem.Colors.border.opacity(0.5)).frame(height: 0.5)
            }
        }
    }

    private func cursorTab(path: String) -> some View {
        let isActive = openFilesStore.openFilePath == path
        let isDirty = openFilesStore.isDirty(path: path)
        let name = (path as NSString).lastPathComponent

        return HStack(spacing: 6) {
            Image(systemName: tabFileIcon(name))
                .font(.system(size: 10))
                .foregroundStyle(tabIconColor(name))

            Text(name)
                .font(.system(size: 11.5, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)

            if isDirty {
                Circle()
                    .fill(.white.opacity(0.5))
                    .frame(width: 6, height: 6)
            }

            Button {
                openFilesStore.closeFile(path)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isActive ? DesignSystem.Colors.backgroundDeep : .clear)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle().fill(Color.accentColor).frame(height: 1.5)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DesignSystem.Colors.border.opacity(0.3))
                .frame(width: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { openFilesStore.openFile(path) }
        .contextMenu {
            Button("Close") { openFilesStore.closeFile(path) }
            Button("Close Others") { openFilesStore.closeOthers(keeping: path) }
            Button("Close All") { openFilesStore.closeAllFiles() }
            Divider()
            if openFilesStore.diff(for: path) != nil {
                Button("Show Diff") { openFilesStore.setViewMode(.diffInline, for: path) }
                Button("Show File") { openFilesStore.setPlainMode(path: path) }
            }
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
        }
    }

    private func tabFileIcon(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "curlybraces"
        case "ts", "tsx": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces.square"
        case "md", "markdown": return "doc.text"
        case "html", "htm": return "globe"
        case "css", "scss": return "paintbrush"
        case "rs": return "gearshape.2"
        case "go": return "arrow.right.arrow.left"
        case "sh", "zsh", "bash": return "terminal"
        case "yml", "yaml": return "list.bullet.indent"
        case "png", "jpg", "jpeg", "svg", "gif": return "photo"
        default: return "doc"
        }
    }

    private func tabIconColor(_ name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "js", "jsx": return .yellow
        case "ts", "tsx": return .blue
        case "py": return .green
        case "json": return .yellow.opacity(0.7)
        case "md": return .cyan
        case "html", "htm": return .orange.opacity(0.7)
        case "css", "scss": return .purple
        case "rs": return .orange.opacity(0.8)
        case "go": return .cyan
        default: return .secondary
        }
    }
}
