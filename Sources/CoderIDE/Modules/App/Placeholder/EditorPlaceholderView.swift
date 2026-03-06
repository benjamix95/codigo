import SwiftUI

struct EditorPlaceholderView: View {
    let folderPaths: [String]
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var editorSplitStore: EditorSplitStore
    @EnvironmentObject var editorPanelsStore: EditorPanelsStore
    @EnvironmentObject var editorQuickOpenStore: EditorQuickOpenStore
    @EnvironmentObject var editorDiagnosticsStore: EditorDiagnosticsStore
    @EnvironmentObject var editorSymbolsStore: EditorSymbolsStore
    @EnvironmentObject var editorCommandDispatchStore: EditorCommandDispatchStore
    @EnvironmentObject var editorNavigationDispatchStore: EditorNavigationDispatchStore

    var displayPath: String { folderPaths.first ?? "" }
    @State var saveFeedback: String?
    @State var saveFeedbackIsError = false
    @State var cursorByPane: [EditorPaneID: EditorCursorPosition] = [:]
    @State var editorOptions = MonacoEditorOptions()

    @AppStorage("ui_code_font_family") var uiCodeFontFamily = FontPreferences.defaultCodeFamily
    @AppStorage("ui_code_font_size") var uiCodeFontSize = FontPreferences.defaultCodeSize

    var body: some View {
        Group {
            if hasOpenEditor {
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
        .onAppear { editorQuickOpenStore.prepare(folderPaths: folderPaths) }
        .onChange(of: folderPaths) { _, newPaths in
            editorQuickOpenStore.prepare(folderPaths: newPaths)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorQuickOpen)) { _ in
            editorPanelsStore.showQuickOpen(targetPane: editorSplitStore.activePane)
            editorQuickOpenStore.prepare(folderPaths: folderPaths)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorToggleSplit)) { _ in
            editorSplitStore.toggleSplit(using: openFilesStore.openFilePath)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorFind)) { _ in
            dispatchMonacoCommand("findInFile")
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorReplace)) { _ in
            dispatchMonacoCommand("replaceInFile")
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorGoToLine)) { _ in
            dispatchMonacoCommand("gotoLine")
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorShowProblems)) { _ in
            editorPanelsStore.toggleBottomPanel(.problems)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorShowOutline)) { _ in
            editorPanelsStore.toggleBottomPanel(.outline)
            refreshOutline(for: activeEditorPath)
            dispatchMonacoCommand("showOutline")
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorFormatDocument)) { _ in
            formatActiveDocument()
        }
        .onChange(of: activeEditorPath) { _, newPath in
            refreshOutline(for: newPath)
        }
    }

    var hasOpenEditor: Bool {
        if let path = openFilesStore.openFilePath, !path.isEmpty { return true }
        if let secondaryPath = editorSplitStore.secondaryFilePath, !secondaryPath.isEmpty { return true }
        return false
    }

    var path: String {
        activeEditorPath ?? ""
    }

    var activeEditorPath: String? {
        editorSplitStore.filePath(primaryPath: openFilesStore.openFilePath)
    }

    func fileEditorView(path _: String) -> some View {
        VStack(spacing: 0) {
            tabBar
            editorWorkspace
            editorFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func dispatchMonacoCommand(_ commandId: String) {
        editorCommandDispatchStore.dispatch(commandId, pane: editorSplitStore.activePane)
    }

    func formatActiveDocument() {
        guard let path = activeEditorPath else { return }
        Task {
            let result = await editorDiagnosticsStore.formatDocument(path: path, openFilesStore: openFilesStore)
            await MainActor.run {
                saveFeedback = result.message
                saveFeedbackIsError = result.isError
            }
        }
    }

    func refreshOutline(for path: String?) {
        guard let path, !path.isEmpty else { return }
        Task { await editorSymbolsStore.loadOutline(for: path, workspaceStore: workspaceStore) }
    }
}
