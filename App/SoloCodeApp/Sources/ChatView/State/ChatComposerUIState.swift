import Foundation
import SwiftUI

// MARK: - ChatComposerUIState

/// ObservableObject state container for composer-related UI properties.
/// Extracted from ChatPanelView to reduce @State explosion and isolate re-renders.
/// Uses ObservableObject (not @Observable) for macOS 13.0 compatibility.
@MainActor
final class ChatComposerUIState: ObservableObject {
    @Published var inputText: String = ""
    @Published var isInputFocused: Bool = false
    @Published var didAutoFocusOnLaunch: Bool = false
    var autoFocusTask: Task<Void, Never>?
    var draftSaveTask: Task<Void, Never>?
    @Published var attachedAttachments: [ComposerAttachment] = []
    @Published var codeReviewModes: Set<CodeReviewPanelMode> = [
        .standard, .bugFinder, .securityAudit,
    ]
    @Published var isSelectingImage: Bool = false
    @Published var isDropTargeted: Bool = false
    @Published var isConvertingHeic: Bool = false
    var pasteMonitor: Any?
    @Published var frozenTimerState: ComposerFrozenTimerState?
    var timerAutoHideTask: Task<Void, Never>?
    @Published var taskStartDate: Date?
    @Published var lastTaskEndedByManualStop: Bool = false
    @Published var isOptimizingPrompt: Bool = false
    @Published var showPromptOptimizerPopup: Bool = false
    @Published var optimizedPromptResult: String = ""
    var promptOptimizerTask: Task<Void, Never>?

    func resetPromptOptimizer() {
        isOptimizingPrompt = false
        showPromptOptimizerPopup = false
        optimizedPromptResult = ""
        promptOptimizerTask?.cancel()
        promptOptimizerTask = nil
    }
}
