import Foundation
import SwiftUI

// MARK: - ChatPanelView Composer State Aliases

/// Computed property aliases that forward to `composerState` (ChatComposerUIState).
/// These maintain backward compatibility with the extension files
/// that reference `self.inputText`, `self.isInputFocused`, etc.
///
/// Once all extensions are migrated to use `composerState.xyz` directly,
/// these aliases can be removed.
extension ChatPanelView {
    var inputText: String {
        get { composerState.inputText }
        nonmutating set { composerState.inputText = newValue }
    }

    var isInputFocused: Bool {
        get { composerState.isInputFocused }
        nonmutating set { composerState.isInputFocused = newValue }
    }

    var didAutoFocusComposerOnLaunch: Bool {
        get { composerState.didAutoFocusOnLaunch }
        nonmutating set { composerState.didAutoFocusOnLaunch = newValue }
    }

    var composerAutoFocusTask: Task<Void, Never>? {
        get { composerState.autoFocusTask }
        nonmutating set { composerState.autoFocusTask = newValue }
    }

    var draftSaveTask: Task<Void, Never>? {
        get { composerState.draftSaveTask }
        nonmutating set { composerState.draftSaveTask = newValue }
    }

    var attachedComposerAttachments: [ComposerAttachment] {
        get { composerState.attachedAttachments }
        nonmutating set { composerState.attachedAttachments = newValue }
    }

    var composerCodeReviewModes: Set<CodeReviewPanelMode> {
        get { composerState.codeReviewModes }
        nonmutating set { composerState.codeReviewModes = newValue }
    }

    var isSelectingImage: Bool {
        get { composerState.isSelectingImage }
        nonmutating set { composerState.isSelectingImage = newValue }
    }

    var isComposerDropTargeted: Bool {
        get { composerState.isDropTargeted }
        nonmutating set { composerState.isDropTargeted = newValue }
    }

    var isConvertingHeic: Bool {
        get { composerState.isConvertingHeic }
        nonmutating set { composerState.isConvertingHeic = newValue }
    }

    var pasteMonitor: Any? {
        get { composerState.pasteMonitor }
        nonmutating set { composerState.pasteMonitor = newValue }
    }

    var composerFrozenTimerState: ComposerFrozenTimerState? {
        get { composerState.frozenTimerState }
        nonmutating set { composerState.frozenTimerState = newValue }
    }

    var composerTimerAutoHideTask: Task<Void, Never>? {
        get { composerState.timerAutoHideTask }
        nonmutating set { composerState.timerAutoHideTask = newValue }
    }

    var composerTaskStartDate: Date? {
        get { composerState.taskStartDate }
        nonmutating set { composerState.taskStartDate = newValue }
    }

    var lastTaskEndedByManualStop: Bool {
        get { composerState.lastTaskEndedByManualStop }
        nonmutating set { composerState.lastTaskEndedByManualStop = newValue }
    }

    var isOptimizingPrompt: Bool {
        get { composerState.isOptimizingPrompt }
        nonmutating set { composerState.isOptimizingPrompt = newValue }
    }

    var showPromptOptimizerPopup: Bool {
        get { composerState.showPromptOptimizerPopup }
        nonmutating set { composerState.showPromptOptimizerPopup = newValue }
    }

    var optimizedPromptResult: String {
        get { composerState.optimizedPromptResult }
        nonmutating set { composerState.optimizedPromptResult = newValue }
    }

    var promptOptimizerTask: Task<Void, Never>? {
        get { composerState.promptOptimizerTask }
        nonmutating set { composerState.promptOptimizerTask = newValue }
    }
}
