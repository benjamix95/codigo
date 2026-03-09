import SwiftUI

struct AutoCodeReviewRequest: Equatable {
    let prompt: String
    let selectedModes: Set<CodeReviewPanelMode>
    let prefersCodeReviewRuntimeProvider: Bool
}

@MainActor
func makeAutoCodeReviewRequest(
    userText: String,
    coderMode: CoderMode
) -> AutoCodeReviewRequest {
    let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard coderMode != .codeReviewMultiSwarm,
          !trimmed.isEmpty,
          !trimmed.hasPrefix("/") else {
        return AutoCodeReviewRequest(
            prompt: userText,
            selectedModes: [],
            prefersCodeReviewRuntimeProvider: false
        )
    }

    let lowercased = trimmed.lowercased()
    let reviewSignals = [
        "code review", "fai una review", "fammi una review", "review this",
        "review these", "review del diff", "review this diff", "analizza questo diff",
        "analizza il diff", "review branch", "revisione codice", "rivedi il codice",
        "audit del codice",
    ]
    let securitySignals = [
        "security review", "security audit", "audit di sicurezza", "sicurezza",
        "vulnerabil", "xss", "csrf", "ssrf", "authz", "secret", "segreti",
    ]
    let bugSignals = [
        "bug hunt", "bughunter", "cerca bug", "trova bug", "find bugs",
        "regress", "crash", "race condition", "stale state",
    ]

    let wantsReview = reviewSignals.contains(where: lowercased.contains)
    let wantsSecurity = securitySignals.contains(where: lowercased.contains)
    let wantsBugHunt = bugSignals.contains(where: lowercased.contains)

    guard wantsReview || wantsSecurity || wantsBugHunt else {
        return AutoCodeReviewRequest(
            prompt: userText,
            selectedModes: [],
            prefersCodeReviewRuntimeProvider: false
        )
    }

    var selectedModes: Set<CodeReviewPanelMode> = []
    if wantsReview {
        selectedModes.insert(.standard)
    }
    if wantsSecurity {
        selectedModes.insert(.securityAudit)
    }
    if wantsBugHunt {
        selectedModes.insert(.bugFinder)
    }
    if selectedModes.isEmpty {
        selectedModes.insert(.standard)
    }

    let prompt = ReviewPanelCoordinator.combinedPrompt(
        scope: .uncommitted,
        currentBranch: "",
        selectedModes: selectedModes,
        customInstructions: trimmed
    )
    return AutoCodeReviewRequest(
        prompt: prompt,
        selectedModes: selectedModes,
        prefersCodeReviewRuntimeProvider: true
    )
}

extension ChatPanelView {
    @MainActor
    internal func resolvedAutoCodeReviewRequest(for text: String) -> AutoCodeReviewRequest {
        makeAutoCodeReviewRequest(userText: text, coderMode: coderMode)
    }

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
