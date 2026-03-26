import CoderEngine
import Foundation

extension WorkspaceStore {

    func applyIndexStatus(_ info: IndexStatusInfo) {
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
