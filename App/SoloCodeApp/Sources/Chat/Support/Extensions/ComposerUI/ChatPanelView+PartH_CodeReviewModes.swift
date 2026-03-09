import SwiftUI

struct AutoCodeReviewRequest: Equatable {
    let prompt: String
    let selectedModes: Set<CodeReviewPanelMode>
    let prefersCodeReviewRuntimeProvider: Bool
}

private struct AutoCodeReviewIntentMatch: Equatable {
    let wantsReview: Bool
    let wantsSecurity: Bool
    let wantsBugHunt: Bool
    let prefersWorkspaceScope: Bool

    var shouldRouteToReviewRuntime: Bool {
        wantsReview || wantsSecurity || wantsBugHunt
    }
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

    let intent = matchAutoCodeReviewIntent(trimmed)
    guard intent.shouldRouteToReviewRuntime else {
        return AutoCodeReviewRequest(
            prompt: userText,
            selectedModes: [],
            prefersCodeReviewRuntimeProvider: false
        )
    }

    var selectedModes: Set<CodeReviewPanelMode> = []
    if intent.wantsReview {
        selectedModes.insert(.standard)
    }
    if intent.wantsSecurity {
        selectedModes.insert(.securityAudit)
    }
    if intent.wantsBugHunt {
        selectedModes.insert(.bugFinder)
    }
    if selectedModes.isEmpty {
        selectedModes.insert(.standard)
    }

    let scopeTarget: ReviewScopeTarget = intent.prefersWorkspaceScope ? .workspace : .uncommitted
    let prompt = ReviewPanelCoordinator.combinedPrompt(
        scope: scopeTarget,
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

private func matchAutoCodeReviewIntent(_ text: String) -> AutoCodeReviewIntentMatch {
    let lowercased = text.lowercased()

    let reviewSignals = [
        "code review", "fai una review", "fammi una review", "review this",
        "review these", "review del diff", "review this diff", "analizza questo diff",
        "analizza il diff", "review branch", "revisione codice", "rivedi il codice",
        "audit del codice", "analizza queste modifiche", "controlla queste modifiche",
        "controlla il diff", "controlla questa patch", "check this diff",
    ]
    let reviewVerbs = [
        "review", "revisione", "rivedi", "analizza", "controlla",
        "audit", "check", "valuta", "ispeziona",
    ]
    let scopedTargets = [
        "diff", "modifiche", "changes", "commit", "branch", "patch",
        "pull request", "merge request", "file", "files",
    ]
    let securitySignals = [
        "security review", "security audit", "audit di sicurezza", "sicurezza",
        "vulnerabil", "xss", "csrf", "ssrf", "authz", "secret", "segreti",
        "token esposto", "hardcoded key", "hardcoded secret",
    ]
    let bugSignals = [
        "bug hunt", "bughunter", "cerca bug", "trova bug", "find bugs",
        "regress", "crash", "race condition", "stale state", "null dereference",
        "off-by-one", "memory leak", "logic error",
    ]
    let negativeSignals = [
        "spiegami", "explain", "che cos", "what is", "come funziona",
        "how does", "documenta", "documentation", "riassumi",
    ]

    let hasReviewPhrase = reviewSignals.contains(where: lowercased.contains)
    let hasReviewVerb = reviewVerbs.contains(where: lowercased.contains)
    let hasPullRequestTarget =
        lowercased.contains("pull request")
        || lowercased.contains("merge request")
        || lowercased.contains("questa pr")
        || lowercased.contains("questa mr")
        || lowercased.hasPrefix("pr ")
        || lowercased.contains(" pr ")
    let hasScopedTarget = scopedTargets.contains(where: lowercased.contains) || hasPullRequestTarget
    let hasSecuritySignal = securitySignals.contains(where: lowercased.contains)
    let hasBugSignal = bugSignals.contains(where: lowercased.contains)
    let hasNegativeSignal = negativeSignals.contains(where: lowercased.contains)
    let hasExplicitSecurityReview =
        lowercased.contains("security review")
        || lowercased.contains("security audit")
        || lowercased.contains("audit di sicurezza")
    let hasExplicitBugReview =
        lowercased.contains("bug hunt")
        || lowercased.contains("bughunter")
        || lowercased.contains("cerca bug")
        || lowercased.contains("trova bug")
        || lowercased.contains("find bugs")

    if hasNegativeSignal,
       !hasScopedTarget,
       !hasExplicitSecurityReview,
       !hasExplicitBugReview,
       !hasReviewPhrase {
        return AutoCodeReviewIntentMatch(
            wantsReview: false,
            wantsSecurity: false,
            wantsBugHunt: false,
            prefersWorkspaceScope: false
        )
    }

    let wantsReview = hasReviewPhrase || (hasReviewVerb && hasScopedTarget)
    let wantsSecurity = hasSecuritySignal
        && (hasExplicitSecurityReview || hasScopedTarget || (hasReviewVerb && !hasNegativeSignal))
    let wantsBugHunt = hasBugSignal
        && (hasExplicitBugReview || hasScopedTarget || (hasReviewVerb && !hasNegativeSignal))
    let prefersWorkspaceScope = !hasScopedTarget && (hasReviewPhrase || hasReviewVerb)

    return AutoCodeReviewIntentMatch(
        wantsReview: wantsReview,
        wantsSecurity: wantsSecurity,
        wantsBugHunt: wantsBugHunt,
        prefersWorkspaceScope: prefersWorkspaceScope
    )
}
