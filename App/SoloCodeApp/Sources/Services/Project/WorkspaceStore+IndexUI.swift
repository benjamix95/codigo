import CoderEngine
import Foundation

extension WorkspaceStore {

    func applyIndexStatus(_ info: IndexStatusInfo) {
        // Warm-start guard: il polling può leggere l'attore prima che indexWorkspace()
        // inizi (status ancora .idle). Non sovrascrivere il badge .ready impostato
        // dal warm-start con uno stato peggiore che mostrerebbe 0%.
        if indexBadgeState.status == .ready && info.status == .idle && info.progress == nil {
            return
        }
        indexProgress = info.progress
        indexBadgeState = WorkspaceIndexBadgeState.from(
            info: info,
            hasWorkspacePaths: !activeWorkspacePaths.isEmpty,
            indexingEnabled: isAutomaticIndexingEnabled
        )
    }

    func resetIndexBadgeToIdle() {
        indexProgress = nil
        indexBadgeState = WorkspaceIndexBadgeState(
            progress: nil,
            status: .idle,
            hasWorkspacePaths: !activeWorkspacePaths.isEmpty,
            indexingEnabled: isAutomaticIndexingEnabled
        )
    }

    /// Aggiorna stato badge da actor (es. Impostazioni).
    func refreshIndexBadgeStateAsync() async {
        let info = await codebaseIndex.status()
        applyIndexStatus(info)
    }
}
