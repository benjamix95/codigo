import SwiftUI

struct EditorPlaceholderView: View {
    let folderPaths: [String]
    @EnvironmentObject var openFilesStore: OpenFilesStore

    var displayPath: String { folderPaths.first ?? "" }
    @State private var saveFeedback: String?
    @State var saveFeedbackIsError = false

    @AppStorage("ui_code_font_family") var uiCodeFontFamily = FontPreferences.defaultCodeFamily
    @AppStorage("ui_code_font_size") var uiCodeFontSize = FontPreferences.defaultCodeSize

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
}
