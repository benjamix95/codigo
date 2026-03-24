import CoderEngine
import Foundation
import SwiftUI

// MARK: - ChatPanelView Debug State Aliases

/// Computed property aliases that forward to `debugUIState` (ChatDebugUIState).
/// These maintain backward compatibility with the extension files
/// that reference `self.debugToggleEnabled`, etc.
///
/// Once all extensions are migrated to use `debugUIState.xyz` directly,
/// these aliases can be removed.
extension ChatPanelView {
    var debugToggleEnabled: Bool {
        get { debugUIState.toggleEnabled }
        nonmutating set { debugUIState.toggleEnabled = newValue }
    }

    var pendingCodeReviewSessionConfigOverride: SessionConfig? {
        get { debugUIState.pendingCodeReviewSessionConfigOverride }
        nonmutating set { debugUIState.pendingCodeReviewSessionConfigOverride = newValue }
    }
}
