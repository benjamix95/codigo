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
        let isSelected: Bool
        let icon: String?

        init(
            id: String,
            slash: String,
            label: String,
            prompt: String,
            isSelected: Bool = false,
            icon: String? = nil
        ) {
            self.id = id
            self.slash = slash
            self.label = label
            self.prompt = prompt
            self.isSelected = isSelected
            self.icon = icon
        }
    }

    // MARK: - Bindings & Environment

    @Binding var inputText: String
    @Binding var attachedAttachments: [ComposerAttachment]
    @Binding var isSelectingImage: Bool
    @Binding var isComposerDropTargeted: Bool
    @Binding var isConvertingHeic: Bool
    @Binding var isInputFocused: Bool

    let isProviderReady: Bool
    /// `false` quando non c’è workspace/cartella: l’invio è bloccato e mostriamo il banner sul composer.
    let isProjectContextAvailable: Bool
    let isLoading: Bool
    let planningState: PlanningState
    let runtimeRunState: ExecutionRunState
    let runtimeTaskStartDate: Date?
    let frozenTimerText: String?
    let frozenTimerDismissible: Bool
    let isIDEStyle: Bool
    let activeModeColor: Color
    let activeModeGradient: LinearGradient
    let inputHint: String
    let providerNotReadyMessage: String
    let quickCommandPresets: [QuickCommandPreset]
    let slashCommandPresets: [QuickCommandPreset]
    let reviewModePresets: [QuickCommandPreset]
    let showPlanRequestIndicator: Bool
    let controlsRow: AnyView
    let voiceState: VoiceInputController.State
    let voiceTranscript: String

    let onSend: () -> Void
    let onApplyQuickCommand: (String) -> Void
    let onToggleReviewMode: (String) -> Void
    let onInputTextChanged: (String) -> Void
    let onRunQuickCommand: (String) -> Void
    let onPauseResume: () -> Void
    let onStop: () -> Void
    let onDismissFrozenTimer: () -> Void
    let onVoiceAction: () -> Void
    let onOptimizePrompt: () -> Void
    let isOptimizingPrompt: Bool
    var topOverlay: AnyView? = nil

    private var composerChromeAnimationToken: String {
        "\(isInputFocused)-\(isComposerDropTargeted)"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isProviderReady {
                providerNotReadyBanner
            }
            if !isProjectContextAvailable {
                noProjectOpenBanner
            }

            VStack(spacing: isIDEStyle ? 6 : 8) {
                // The parent mounts the todo overlay above the composer while
                // preserving the same fused visual container.
                VStack(spacing: 0) {
                    if let topOverlay {
                        topOverlay
                    }

                    composerBoxContent
                        .padding(.horizontal, isIDEStyle ? 12 : 14)
                        .padding(.vertical, isIDEStyle ? 8 : 10)
                }
                .background(
                    RoundedRectangle(cornerRadius: isIDEStyle ? 16 : 20, style: .continuous)
                        .fill(composerSurfaceGradient)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isIDEStyle ? 16 : 20, style: .continuous)
                        .strokeBorder(
                            isComposerDropTargeted
                                ? Color.white.opacity(0.35)
                                : (isInputFocused
                                    ? Color.white.opacity(0.22)
                                    : Color.white.opacity(0.12)),
                            lineWidth: isComposerDropTargeted ? 1.2 : 0.8
                        )
                        .animation(.easeOut(duration: 0.2), value: composerChromeAnimationToken)
                )
                .shadow(color: Color.black.opacity(isIDEStyle ? 0.14 : 0.25), radius: isIDEStyle ? 6 : 12, y: isIDEStyle ? 1 : 3)
                .onDrop(
                    of: [.item, .fileURL, .image, .png, .jpeg, .gif, .pdf],
                    isTargeted: $isComposerDropTargeted
                ) { providers in
                    Task {
                        var incoming: [ComposerAttachment] = []
                        for provider in providers {
                            if let attachment = await AttachmentIntakeService.attachmentFromDropProvider(provider) {
                                incoming.append(attachment)
                            }
                        }
                        await MainActor.run {
                            appendAttachments(incoming)
                        }
                    }
                    return true
                }
                .overlay {
                    if isConvertingHeic {
                        RoundedRectangle(cornerRadius: isIDEStyle ? 18 : 26, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                VStack(spacing: 8) {
                                    ProgressView().controlSize(.regular)
                                    Text("Converting HEIC image...")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                    }
                }

                if !slashMatches.isEmpty {
                    slashAutocompletePanel
                }
                if !quickCommandPresets.isEmpty {
                    quickCommandsRow
                }
                if !reviewModePresets.isEmpty {
                    reviewModeRow
                }
            }
            .padding(isIDEStyle ? 8 : 12)
        }
    }
}
