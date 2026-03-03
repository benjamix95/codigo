import SwiftUI

extension ChatPanelView {
    @MainActor
    internal func requestInitialComposerFocusIfNeeded() {
        guard !didAutoFocusComposerOnLaunch else { return }
        guard selectedConversationId != nil else { return }
        didAutoFocusComposerOnLaunch = true
        composerAutoFocusTask?.cancel()
        composerAutoFocusTask = Task { @MainActor in
            // Delay slightly to ensure the window/composer NSView is mounted.
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            isInputFocused = true
        }
    }
}
