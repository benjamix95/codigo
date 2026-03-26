import CoderEngine
import SwiftUI

struct AutoCodeReviewRequest: Equatable {
    let prompt: String
    let selectedModes: Set<CodeReviewPanelMode>
    let prefersCodeReviewRuntimeProvider: Bool
    let scopeTarget: ReviewScopeTarget?
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
    coderMode: CoderMode,
    currentGitBranch: String = ""
) -> AutoCodeReviewRequest {
    let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard coderMode != .codeReviewMultiSwarm,
          !trimmed.isEmpty,
          !trimmed.hasPrefix("/") else {
        return AutoCodeReviewRequest(
            prompt: userText,
            selectedModes: [],
            prefersCodeReviewRuntimeProvider: false,
            scopeTarget: nil
        )
    }

    let intent = matchAutoCodeReviewIntent(trimmed)
    guard intent.shouldRouteToReviewRuntime else {
        return AutoCodeReviewRequest(
            prompt: userText,
            selectedModes: [],
            prefersCodeReviewRuntimeProvider: false,
            scopeTarget: nil
        )
    }

    let selectedModes = codeReviewModesForAutoIntent(intent)

    let scopeTarget: ReviewScopeTarget = intent.prefersWorkspaceScope ? .workspace : .uncommitted
    let prompt = ReviewPanelCoordinator.combinedPrompt(
        scope: scopeTarget,
        currentBranch: currentGitBranch,
        selectedModes: selectedModes,
        customInstructions: trimmed
    )
    return AutoCodeReviewRequest(
        prompt: prompt,
        selectedModes: selectedModes,
        prefersCodeReviewRuntimeProvider: true,
        scopeTarget: scopeTarget
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

private func codeReviewModesForAutoIntent(
    _ intent: AutoCodeReviewIntentMatch
) -> Set<CodeReviewPanelMode> {
    var modes = Set<CodeReviewPanelMode>()
    if intent.wantsReview { modes.insert(.standard) }
    if intent.wantsSecurity { modes.insert(.securityAudit) }
    if intent.wantsBugHunt { modes.insert(.bugFinder) }
    if modes.isEmpty {
        return [.standard, .bugFinder, .securityAudit]
    }
    return modes
}

/// Evità falsi positivi tipo `file` dentro `profile` o `changes` dentro `exchanges`.
private func textContainsWholeWord(_ haystack: String, _ needle: String) -> Bool {
    let h = haystack.lowercased()
    let n = needle.lowercased()
    guard !n.isEmpty else { return false }
    var start = h.startIndex
    while let r = h.range(of: n, range: start..<h.endIndex) {
        let beforeOK = r.lowerBound == h.startIndex
            || !h[h.index(before: r.lowerBound)].isLetter
        let afterOK = r.upperBound == h.endIndex || !h[r.upperBound].isLetter
        if beforeOK && afterOK { return true }
        start = r.upperBound
    }
    return false
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
        "audit", "check", "valuta", "ispeziona", "verifica",
    ]
    let scopedTargets = [
        "diff", "modifiche", "changes", "commit", "commits", "branch", "patch",
        "file", "files",
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
    let hasReviewVerb = reviewVerbs.contains { textContainsWholeWord(lowercased, $0) }
    let hasPullRequestTarget =
        lowercased.contains("pull request")
        || lowercased.contains("merge request")
        || lowercased.contains("questa pr")
        || lowercased.contains("questa mr")
        || lowercased.hasPrefix("pr ")
        || lowercased.contains(" pr ")
    let hasScopedTarget = scopedTargets.contains { textContainsWholeWord(lowercased, $0) } || hasPullRequestTarget
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
