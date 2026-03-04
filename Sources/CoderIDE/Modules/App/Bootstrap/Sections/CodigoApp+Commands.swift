import AppKit
import SwiftUI

extension CodigoApp {
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
