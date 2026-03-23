import AppKit
import SwiftUI

extension SoloCodeApp {
    @CommandsBuilder
    var appFileCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nuova finestra") {
                openCleanWindowFromFileMenu()
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("Apri progetto...") {
                openProjectFromFileMenu()
            }
            .keyboardShortcut("o", modifiers: [.command])
        }

        CommandGroup(after: .newItem) {
            Menu("Aperti recentemente") {
                if projectContextStore.recentProjectContexts.isEmpty {
                    Button("Nessun progetto recente") {}
                        .disabled(true)
                } else {
                    ForEach(projectContextStore.recentProjectContexts.prefix(12), id: \.id) { context in
                        Button(recentMenuTitle(for: context)) {
                            openContextFromRecents(context)
                        }
                    }
                }
            }

            Menu("Workspace recenti") {
                if projectContextStore.recentWorkspaceContexts.isEmpty {
                    Button("Nessun workspace recente") {}
                        .disabled(true)
                } else {
                    ForEach(projectContextStore.recentWorkspaceContexts.prefix(12), id: \.id) { context in
                        Button(recentMenuTitle(for: context)) {
                            openContextFromRecents(context)
                        }
                    }
                }
            }
        }

        CommandMenu("Editor") {
            Button("Quick Open File") {
                NotificationCenter.default.post(name: .editorQuickOpen, object: nil)
            }
            .keyboardShortcut("p", modifiers: [.command])

            Button("Toggle Split Editor") {
                NotificationCenter.default.post(name: .editorToggleSplit, object: nil)
            }
            .keyboardShortcut("\\", modifiers: [.command])

            Divider()

            Button("Find in File") {
                NotificationCenter.default.post(name: .editorFind, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Replace in File") {
                NotificationCenter.default.post(name: .editorReplace, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])

            Button("Go to Line") {
                NotificationCenter.default.post(name: .editorGoToLine, object: nil)
            }
            .keyboardShortcut("g", modifiers: [.control])

            Button("Show Problems") {
                NotificationCenter.default.post(name: .editorShowProblems, object: nil)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button("Show Outline") {
                NotificationCenter.default.post(name: .editorShowOutline, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Format Document") {
                NotificationCenter.default.post(name: .editorFormatDocument, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.shift, .option])
        }
    }

    @MainActor
    private func openCleanWindowFromFileMenu() {
        WindowLaunchIntentStore.shared.enqueueCleanWindowIntent()
        _ = NSApplication.shared.sendAction(#selector(NSApplication.newWindowForTab(_:)), to: nil, from: nil)
    }

    @MainActor
    private func openProjectFromFileMenu() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Apri"
        panel.title = "Apri cartella progetto"

        guard panel.runModal() == .OK else { return }
        let paths = panel.urls.map { $0.path(percentEncoded: false) }
        guard let contextId = projectContextStore.createOrReuseSingleProject(paths: paths) else { return }
        openContextById(contextId)
    }

    @MainActor
    private func openContextFromRecents(_ context: ProjectContext) {
        openContextById(context.id)
    }

    @MainActor
    private func openContextById(_ contextId: UUID) {
        projectContextStore.activeContextId = contextId
        projectContextStore.markAsRecentlyUsed(contextId: contextId)
        workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: contextId))
    }

    private func recentMenuTitle(for context: ProjectContext) -> String {
        let root = context.activeFolderPath ?? context.folderPaths.first ?? ""
        guard !root.isEmpty else { return context.name }
        let tail = (root as NSString).lastPathComponent
        return "\(context.name) (\(tail))"
    }
}
