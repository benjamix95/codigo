import SwiftUI

extension ChatPanelView {
    internal var composerCodeReviewModePresets: [ChatComposerView.QuickCommandPreset] {
        guard coderMode == .codeReviewMultiSwarm else { return [] }
        let selected = composerCodeReviewModes
        return CodeReviewPanelMode.allCases.map { mode in
            ChatComposerView.QuickCommandPreset(
                id: "composer-review-mode-\(mode.id)",
                slash: mode.displayName,
                label: mode.displayName,
                prompt: "",
                isSelected: selected.contains(mode),
                icon: mode.icon
            )
        }
    }

    internal func toggleComposerCodeReviewMode(_ modeId: String) {
        guard let mode = CodeReviewPanelMode.allCases.first(where: { $0.id == modeId }) else { return }
        if composerCodeReviewModes.contains(mode) {
            if composerCodeReviewModes.count > 1 {
                composerCodeReviewModes.remove(mode)
            }
        } else {
            composerCodeReviewModes.insert(mode)
        }
    }

    internal func applyComposerCodeReviewModesIfNeeded(to text: String) -> String {
        guard coderMode == .codeReviewMultiSwarm else { return text }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") == false else {
            return text
        }
        let prompt = ReviewPanelCoordinator.combinedPrompt(
            scope: .uncommitted,
            currentBranch: "",
            selectedModes: composerCodeReviewModes,
            customInstructions: text
        )
        return prompt
    }
}
