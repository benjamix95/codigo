import CoderEngine
import SwiftUI

struct AutoCodeReviewRequest: Equatable {
    let prompt: String
    let selectedModes: Set<CodeReviewPanelMode>
    let prefersCodeReviewRuntimeProvider: Bool
    let scopeTarget: ReviewScopeTarget?
}

@MainActor
func makeAutoCodeReviewRequest(
    userText: String,
    coderMode: CoderMode,
    currentGitBranch: String = ""
) -> AutoCodeReviewRequest {
    _ = coderMode
    _ = currentGitBranch

    return AutoCodeReviewRequest(
        prompt: userText,
        selectedModes: [],
        prefersCodeReviewRuntimeProvider: false,
        scopeTarget: nil
    )
}

extension ChatPanelView {
    /// Normalized branch for review prompts (`GitPanelStore` uses "-" when unknown).
    internal func resolvedGitBranchForReviewPrompt() -> String {
        let b = gitPanelStore.currentBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty || b == "-" { return "" }
        return b
    }

    @MainActor
    internal func resolvedAutoCodeReviewRequest(for text: String) -> AutoCodeReviewRequest {
        makeAutoCodeReviewRequest(
            userText: text,
            coderMode: coderMode,
            currentGitBranch: resolvedGitBranchForReviewPrompt()
        )
    }

    internal var composerCodeReviewModePresets: [ChatComposerView.QuickCommandPreset] {
        []
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
            currentBranch: resolvedGitBranchForReviewPrompt(),
            selectedModes: composerCodeReviewModes,
            customInstructions: text
        )
        return prompt
    }
}
