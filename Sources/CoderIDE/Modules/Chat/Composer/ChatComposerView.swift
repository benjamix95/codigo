import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Chat Composer View
/// Contains the text input, inline controls, runtime controls, voice input,
/// and drag-and-drop / paste attachments handling.

struct ChatComposerView: View {
    struct QuickCommandPreset: Identifiable {
        let id: String
        let slash: String
        let label: String
        let prompt: String
    }

    // MARK: - Bindings & Environment

    @Binding var inputText: String
    @Binding var attachedAttachments: [ComposerAttachment]
    @Binding var isSelectingImage: Bool
    @Binding var isComposerDropTargeted: Bool
    @Binding var isConvertingHeic: Bool
    @Binding var isInputFocused: Bool

    let isProviderReady: Bool
    let isLoading: Bool
    let planningState: PlanningState
    let runtimeRunState: ExecutionRunState
    let runtimeTaskStartDate: Date?
    let frozenTimerText: String?
    let frozenTimerDismissible: Bool
    let activeModeColor: Color
    let activeModeGradient: LinearGradient
    let inputHint: String
    let providerNotReadyMessage: String
    let quickCommandPresets: [QuickCommandPreset]
    let slashCommandPresets: [QuickCommandPreset]
    let showCodeReviewAutofixToggle: Bool
    let showPlanRequestIndicator: Bool
    let controlsRow: AnyView
    let voiceState: VoiceInputController.State

    @Binding var codeReviewAutofixEnabled: Bool

    let onSend: () -> Void
    let onApplyQuickCommand: (String) -> Void
    let onInputTextChanged: (String) -> Void
    let onRunQuickCommand: (String) -> Void
    let onPauseResume: () -> Void
    let onStop: () -> Void
    let onDismissFrozenTimer: () -> Void
    let onVoiceAction: () -> Void
    let onOptimizePrompt: () -> Void
    let isOptimizingPrompt: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if !isProviderReady {
                providerNotReadyBanner
            }

            VStack(spacing: 8) {
                composerBox
                if !slashMatches.isEmpty {
                    slashAutocompletePanel
                }
                if !quickCommandPresets.isEmpty {
                    quickCommandsRow
                }
                if showCodeReviewAutofixToggle {
                    codeReviewAutofixToggleRow
                }
            }
            .padding(12)
        }
    }
}
