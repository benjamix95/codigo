import CoderEngine
import Foundation

extension ReviewPatchArtifact {
    /// Apply completata al workspace; la validazione (inclusa suite Xcode completa) è `passed`.
    var isPanelApplySuccess: Bool {
        status == .applied && validationStatus == .passed
    }

    /// Mostra «Crea PR» solo dopo apply+validazione verdi, prima che esista un URL.
    var canInitiatePullRequestFromPanel: Bool {
        isPanelApplySuccess && prURL == nil && status != .prOpened && status != .merged
    }
}
