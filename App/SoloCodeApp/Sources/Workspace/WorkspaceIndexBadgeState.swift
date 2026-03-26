import CoderEngine
import Foundation

// MARK: - WorkspaceIndexBadgeState

/// Stato UI unificato: simboli + semantic index + DB vettoriale (stesso ciclo di `indexWorkspace`).
struct WorkspaceIndexBadgeState: Equatable {
    var progress: IndexingProgress?
    var status: IndexStatus
    var hasWorkspacePaths: Bool
    var indexingEnabled: Bool

    static let initial = WorkspaceIndexBadgeState(
        progress: nil,
        status: .idle,
        hasWorkspacePaths: false,
        indexingEnabled: true
    )

    var isIndexingActive: Bool {
        progress != nil || status == .indexing
    }

    /// Indice completo (codebase + BM25/chunk + eventuale pipeline vettoriale — come un’unica operazione).
    var isFullyIndexed: Bool {
        guard indexingEnabled, hasWorkspacePaths else { return false }
        guard status == .ready, progress == nil else { return false }
        return true
    }

    /// Percentuale 0…100: in corso dal progresso, a fine corsa 100 solo se `isFullyIndexed`.
    var displayPercent: Int {
        if let p = progress {
            return min(100, max(0, Int((p.fraction * 100.0).rounded(.down))))
        }
        if isFullyIndexed { return 100 }
        return 0
    }

    var displayPercentText: String { "\(displayPercent)%" }

    var shouldShowWaitNotice: Bool {
        indexingEnabled && hasWorkspacePaths && !isFullyIndexed && !isIndexingActive && status != .error
    }

    var shouldShowErrorNotice: Bool {
        indexingEnabled && hasWorkspacePaths && status == .error && !isIndexingActive
    }

    static func from(
        info: IndexStatusInfo,
        hasWorkspacePaths: Bool,
        indexingEnabled: Bool
    ) -> WorkspaceIndexBadgeState {
        WorkspaceIndexBadgeState(
            progress: info.progress,
            status: info.status,
            hasWorkspacePaths: hasWorkspacePaths,
            indexingEnabled: indexingEnabled
        )
    }
}
