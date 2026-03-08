import SwiftUI

extension EditorPlaceholderView {
    var editorWorkspace: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 0) {
                    editorPane(.primary, path: openFilesStore.openFilePath)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if editorSplitStore.isSplitVisible {
                        Divider().opacity(0.25)
                        editorPane(.secondary, path: editorSplitStore.secondaryFilePath)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                if editorPanelsStore.isQuickOpenVisible {
                    quickOpenOverlay
                        .frame(maxWidth: 640)
                        .padding(.top, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Color.black.opacity(0.12))
                }
            }

            if editorPanelsStore.isBottomPanelVisible {
                Divider().opacity(0.2)
                bottomPanelView
                    .frame(height: 220)
            }
        }
        .background(DesignSystem.Colors.backgroundDeep)
    }

    @ViewBuilder
    func editorPane(_ pane: EditorPaneID, path: String?) -> some View {
        if let path, !path.isEmpty {
            if let error = openFilesStore.error(for: path) {
                errorBanner(error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(DesignSystem.Colors.backgroundDeep)
            } else if openFilesStore.viewMode(for: path) == .diffInline {
                diffInlineView(path: path)
                    .onTapGesture { editorSplitStore.setActivePane(pane) }
            } else {
                MonacoEditorView(
                    pane: pane,
                    filePath: path,
                    content: openFilesStore.content(for: path),
                    diagnostics: editorDiagnosticsStore.diagnostics(for: path),
                    commandRequest: editorCommandDispatchStore.request,
                    navigationRequest: editorNavigationDispatchStore.request,
                    options: editorOptions,
                    handlers: monacoHandlers(for: pane)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            emptySplitPane(pane: pane)
        }
    }

    private func emptySplitPane(pane: EditorPaneID) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(pane == .secondary ? "Split editor ready" : "Open a file")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Button(pane == .secondary ? "Quick Open in Split" : "Quick Open") {
                editorPanelsStore.showQuickOpen(targetPane: pane)
                editorQuickOpenStore.prepare(folderPaths: folderPaths)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DesignSystem.Colors.backgroundSecondary, in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.backgroundDeep)
        .onTapGesture { editorSplitStore.setActivePane(pane) }
    }

    func monacoHandlers(for pane: EditorPaneID) -> MonacoEditorBridgeHandlers {
        MonacoEditorBridgeHandlers(
            onContentChange: { newContent, changedPath in
                openFilesStore.contentDidChangeFromMonaco(newContent, for: changedPath)
                saveFeedback = nil
                saveFeedbackIsError = false
                editorSplitStore.setActivePane(pane)
            },
            onSaveRequested: { savePath in
                handleSaveRequest(savePath)
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
            },
            onCursorChange: { position in
                cursorByPane[position.pane] = position
                editorSplitStore.setActivePane(position.pane)
            },
            onSelectionChange: { selection in
                editorSplitStore.setActivePane(selection.pane)
            },
            onMarkersChanged: { payload in
                editorDiagnosticsStore.replaceBuiltInDiagnostics(payload)
            },
            onActionInvoked: { payload in
                handleMonacoAction(payload, pane: pane)
            },
            hoverProvider: { request in
                await editorSymbolsStore.hover(request: request, workspaceStore: workspaceStore)
            },
            definitionProvider: { request in
                await editorSymbolsStore.definitions(request: request, workspaceStore: workspaceStore)
            },
            referencesProvider: { request in
                let payload = await editorSymbolsStore.loadReferences(
                    request: request,
                    workspaceStore: workspaceStore
                )
                await MainActor.run {
                    if !payload.locations.isEmpty {
                        editorPanelsStore.showBottomPanel(.references)
                    }
                }
                return payload
            },
            renameProvider: { request in
                await editorSymbolsStore.rename(request: request, workspaceStore: workspaceStore)
            },
            outlineProvider: { request in
                await editorSymbolsStore.loadOutline(for: request.path, workspaceStore: workspaceStore)
                let symbols = editorSymbolsStore.outline(for: request.path).map {
                    MonacoOutlinePayload.Symbol(
                        name: $0.name,
                        detail: $0.detail,
                        line: $0.line,
                        column: $0.column,
                        iconName: $0.iconName
                    )
                }
                return MonacoOutlinePayload(symbols: symbols)
            }
        )
    }

    private func handleSaveRequest(_ path: String) {
        Task {
            let result = await editorDiagnosticsStore.save(path: path, openFilesStore: openFilesStore)
            await MainActor.run {
                saveFeedback = result.message
                saveFeedbackIsError = result.isError
            }
            refreshOutline(for: path)
        }
    }

    private func handleMonacoAction(_ payload: MonacoActionPayload, pane: EditorPaneID) {
        editorSplitStore.setActivePane(pane)
        switch payload.commandId {
        case "quickOpen":
            editorPanelsStore.showQuickOpen(targetPane: pane)
            editorQuickOpenStore.prepare(folderPaths: folderPaths)
        case "toggleSplit":
            editorSplitStore.toggleSplit(using: openFilesStore.openFilePath)
        case "showProblems":
            editorPanelsStore.toggleBottomPanel(.problems)
        case "formatDocument":
            formatActiveDocument()
        default:
            break
        }
    }

    func openQuickOpenResult(_ result: EditorQuickOpenResult) {
        let targetPane = editorPanelsStore.quickOpenTargetPane
        if targetPane == .primary {
            openFilesStore.openFile(result.path)
        } else {
            openFilesStore.prepareFile(result.path)
            editorSplitStore.open(
                path: result.path,
                in: .secondary,
                primaryPath: openFilesStore.openFilePath
            )
        }
        refreshOutline(for: result.path)
        editorPanelsStore.hideQuickOpen()
    }

    func navigateTo(path: String, line: Int, pane: EditorPaneID? = nil) {
        let targetPane = pane ?? editorSplitStore.activePane
        if targetPane == .primary {
            openFilesStore.openFile(path)
        } else {
            openFilesStore.prepareFile(path)
            editorSplitStore.open(
                path: path,
                in: .secondary,
                primaryPath: openFilesStore.openFilePath
            )
        }
        refreshOutline(for: path)
        editorNavigationDispatchStore.dispatch(path: path, line: line, pane: targetPane)
    }
}
