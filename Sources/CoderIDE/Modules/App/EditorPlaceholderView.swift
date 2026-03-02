import SwiftUI

struct EditorPlaceholderView: View {
    let folderPaths: [String]
    @EnvironmentObject var openFilesStore: OpenFilesStore

    private var displayPath: String { folderPaths.first ?? "" }
    @State private var saveFeedback: String?
    @State private var saveFeedbackIsError = false

    @AppStorage("ui_code_font_family") private var uiCodeFontFamily = FontPreferences.defaultCodeFamily
    @AppStorage("ui_code_font_size") private var uiCodeFontSize = FontPreferences.defaultCodeSize

    var body: some View {
        Group {
            if let path = openFilesStore.openFilePath, !path.isEmpty {
                fileEditorView(path: path)
            } else {
                placeholderView
            }
        }
        .onChange(of: openFilesStore.openFilePath) { _, newPath in
            openFilesStore.ensureLoaded(newPath)
            saveFeedback = nil
            saveFeedbackIsError = false
        }
        .onAppear { openFilesStore.ensureLoaded(openFilesStore.openFilePath) }
    }

    private func fileEditorView(path: String) -> some View {
        VStack(spacing: 0) {
            tabBar

            if let error = openFilesStore.error(for: path) {
                errorBanner(error)
            } else if openFilesStore.viewMode(for: path) == .diffInline {
                diffInlineView(path: path)
            } else {
                MonacoEditorView(
                    filePath: path,
                    content: openFilesStore.content(for: path),
                    onContentChange: { newContent, changedPath in
                        openFilesStore.contentDidChangeFromMonaco(newContent, for: changedPath)
                        saveFeedback = nil
                        saveFeedbackIsError = false
                    },
                    onSaveRequested: { savePath in
                        let saved = openFilesStore.save(path: savePath)
                        saveFeedback = saved ? "Saved" : (openFilesStore.error(for: savePath) ?? "Error saving file")
                        saveFeedbackIsError = !saved
                    },
                    onFixInChat: { fixPath, selection, line in
                        let filename = (fixPath as NSString).lastPathComponent
                        let prompt = "Fix this code from `\(filename)` (line \(line)):\n```\n\(selection)\n```"
                        NotificationCenter.default.post(
                            name: .editorFixInChat,
                            object: nil,
                            userInfo: ["prompt": prompt, "path": fixPath]
                        )
                    },
                    onAddToChat: { addPath, selection, line in
                        let filename = (addPath as NSString).lastPathComponent
                        let context = "From `\(filename)` (line \(line)):\n```\n\(selection)\n```"
                        NotificationCenter.default.post(
                            name: .editorAddToChat,
                            object: nil,
                            userInfo: ["content": context, "path": addPath]
                        )
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let feedback = saveFeedback {
                statusBar(feedback)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tab Bar (Cursor style)

    @ViewBuilder
    private var tabBar: some View {
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
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 1.5)
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
                Button("Show Diff") {
                    openFilesStore.setViewMode(.diffInline, for: path)
                }
                Button("Show File") {
                    openFilesStore.setPlainMode(path: path)
                }
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
        }
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
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
                        .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5))
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

    // MARK: - Error / Status

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Colors.error)
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.Colors.error)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DesignSystem.Colors.error.opacity(0.08))
    }

    private func statusBar(_ feedback: String) -> some View {
        HStack {
            Text(feedback)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(saveFeedbackIsError ? DesignSystem.Colors.error : .secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(DesignSystem.Colors.backgroundPrimary.opacity(0.5))
    }

    // MARK: - Tab Icon Helpers

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

    // MARK: - Diff View

    private func diffInlineView(path: String) -> some View {
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
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5))
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

extension Notification.Name {
    static let editorFixInChat = Notification.Name("CoderIDE.EditorFixInChat")
    static let editorAddToChat = Notification.Name("CoderIDE.EditorAddToChat")
}
