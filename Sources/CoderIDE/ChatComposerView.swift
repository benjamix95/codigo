import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Chat Composer View
/// Contains the text input, inline controls, runtime controls, voice input,
/// and drag-and-drop / paste image handling.

struct ChatComposerView: View {
    struct QuickCommandPreset: Identifiable {
        let id: String
        let slash: String
        let label: String
        let prompt: String
    }

    // MARK: - Bindings & Environment

    @Binding var inputText: String
    @Binding var attachedImageURLs: [URL]
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

    // MARK: - Quick Commands

    private var quickCommandsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(quickCommandPresets) { preset in
                    HStack(spacing: 5) {
                        Button {
                            onApplyQuickCommand("\(preset.slash)\n\n\(preset.prompt)")
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.slash)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(activeModeColor)
                                Text(preset.label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                Color(nsColor: .controlBackgroundColor).opacity(0.55),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(activeModeColor.opacity(0.22), lineWidth: 0.6)
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            onRunQuickCommand("\(preset.slash)\n\n\(preset.prompt)")
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(activeModeColor, in: Circle())
                        }
                    }
                    .help(preset.prompt)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var slashMatches: [QuickCommandPreset] {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return [] }
        guard !trimmed.contains("\n") else { return [] }
        let query = trimmed.lowercased()
        return quickCommandPresets.filter {
            $0.slash.lowercased().contains(query) || $0.label.lowercased().contains(query)
        }
        .prefix(6)
        .map { $0 }
    }

    private var slashAutocompletePanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Comandi rapidi")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(slashMatches) { preset in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preset.slash)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(activeModeColor)
                        Text(preset.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button("Inserisci") {
                        onApplyQuickCommand("\(preset.slash)\n\n\(preset.prompt)")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .semibold))
                    Button("Run now") {
                        onRunQuickCommand("\(preset.slash)\n\n\(preset.prompt)")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Color(nsColor: .controlBackgroundColor).opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.55), lineWidth: 0.6)
        )
    }

    private var codeReviewAutofixToggleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(activeModeColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Code Review")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(codeReviewAutofixEnabled
                    ? "Autofix (YOLO): analisi + applicazione fix automatica"
                    : "Discovery: solo analisi, nessun fix automatico")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle(isOn: $codeReviewAutofixEnabled) {
                Text(codeReviewAutofixEnabled ? "Autofix" : "Discovery")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(codeReviewAutofixEnabled ? DesignSystem.Colors.success : .secondary)
            }
            .toggleStyle(.switch)
            .labelsHidden()
            Text(codeReviewAutofixEnabled ? "Autofix" : "Discovery")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(codeReviewAutofixEnabled ? DesignSystem.Colors.success : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (codeReviewAutofixEnabled ? DesignSystem.Colors.success : activeModeColor)
                        .opacity(0.12),
                    in: Capsule()
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.46))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    (codeReviewAutofixEnabled ? DesignSystem.Colors.success : activeModeColor)
                        .opacity(0.25),
                    lineWidth: 0.6
                )
        )
    }

    // MARK: - Provider Not Ready Banner

    private var providerNotReadyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(providerNotReadyMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Composer Box

    private var composerBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            if voiceState != .idle {
                voiceStatusView
            }

            if !attachedImageURLs.isEmpty {
                attachedImagesRow
            }

            TextField(inputHint, text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...8)
                .focused($focusState)
                .onSubmit { onSend() }
                .onChange(of: inputText) { _, newValue in
                    onInputTextChanged(newValue)
                }
                .onChange(of: isInputFocused) { _, newValue in
                    focusState = newValue
                }
                .onChange(of: focusState) { _, newValue in
                    isInputFocused = newValue
                }

            bottomControlsRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(composerSurfaceGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isComposerDropTargeted
                        ? Color.white.opacity(0.35)
                        : (focusState
                            ? Color.white.opacity(0.22)
                            : Color.white.opacity(0.12)),
                    lineWidth: isComposerDropTargeted ? 1.2 : 0.8
                )
        )
        .shadow(color: Color.black.opacity(0.25), radius: 12, y: 3)
        .animation(.easeOut(duration: 0.2), value: focusState)
        .onDrop(
            of: [.image, .fileURL, .png, .jpeg, .gif],
            isTargeted: $isComposerDropTargeted
        ) { providers in
            Task {
                for provider in providers {
                    if let url = await ImageAttachmentHelper.imageURLFromDropProvider(provider) {
                        await MainActor.run { attachedImageURLs.append(url) }
                    }
                }
            }
            return true
        }
        .overlay {
            if isConvertingHeic {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
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
    }

    private var bottomControlsRow: some View {
        HStack(spacing: 8) {
            imageAttachButton

            controlsRow
                .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading {
                runtimeControls
            } else {
                idleTrailingControls
            }
        }
    }

    @ViewBuilder
    private var idleTrailingControls: some View {
        HStack(spacing: 6) {
            if frozenTimerText != nil {
                runtimeTimerLabel
            }
            microphoneButton
            sendButton
        }
    }

    @ViewBuilder
    private var runtimeControls: some View {
        HStack(spacing: 6) {
            runtimeTimerLabel

            Button {
                onPauseResume()
            } label: {
                Image(systemName: runtimeRunState == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help(runtimeRunState == .paused ? "Riprendi" : "Pausa")

            Button {
                onStop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.black.opacity(0.9))
                    .frame(width: 34, height: 34)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Ferma")
        }
    }

    @ViewBuilder
    private var runtimeTimerLabel: some View {
        if let startDate = runtimeTaskStartDate {
            TimelineView(.periodic(from: startDate, by: 1.0)) { context in
                Text(formatElapsed(max(0, Int(context.date.timeIntervalSince(startDate)))) )
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        } else if let frozenTimerText {
            if frozenTimerDismissible {
                Button {
                    onDismissFrozenTimer()
                } label: {
                    Text(frozenTimerText)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Nascondi timer")
            } else {
                Text(frozenTimerText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var voiceStatusView: some View {
        switch voiceState {
        case .idle:
            EmptyView()
        case .requestingPermission:
            voiceStatusBadge(icon: "lock.open.fill", text: "Richiesta permessi microfono/speech…", color: .secondary)
        case .listening:
            voiceStatusBadge(icon: "waveform", text: "In ascolto… clicca il microfono per fermare", color: DesignSystem.Colors.info)
        case .transcribing:
            voiceStatusBadge(icon: "waveform.badge.magnifyingglass", text: "Trascrizione in corso…", color: .secondary)
        case .failed:
            EmptyView()
        }
    }

    private func voiceStatusBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: - Focus
    @FocusState private var focusState: Bool

    // MARK: - Attached Images Row

    private var attachedImagesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachedImageURLs.enumerated()), id: \.offset) { index, url in
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(attachmentDisplayName(for: url))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Button {
                            attachedImageURLs.remove(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(4)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.6)
                    )
                }
            }
        }
    }

    /// Grigio scuro più profondo (~#2a2a2a), come nell’immagine di riferimento.
    private var composerSurfaceGradient: LinearGradient {
        let gray = Color(red: 42 / 255, green: 42 / 255, blue: 42 / 255)
        return LinearGradient(
            stops: [
                .init(color: gray.opacity(0.98), location: 0.0),
                .init(color: gray.opacity(0.96), location: 0.38),
                .init(color: gray.opacity(0.96), location: 1.0),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func attachmentDisplayName(for url: URL) -> String {
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ext.isEmpty {
            return url.lastPathComponent.isEmpty ? "image" : url.lastPathComponent
        }
        return "image.\(ext)"
    }

    // MARK: - Image Attach Button

    private var imageAttachButton: some View {
        Button {
            isSelectingImage = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help("Allega immagine (⌘V per incollare)")
    }

    // MARK: - Voice Button

    private var microphoneButton: some View {
        Button {
            onVoiceAction()
        } label: {
            Group {
                switch voiceState {
                case .transcribing, .requestingPermission:
                    ProgressView()
                        .controlSize(.small)
                case .listening:
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black.opacity(0.9))
                default:
                    Image(systemName: "mic")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .background(
                voiceState == .listening
                    ? Color(red: 1, green: 0.94, blue: 0.94)
                    : Color.clear,
                in: Circle()
            )
            .overlay(
                Circle().strokeBorder(
                    voiceState == .listening
                        ? Color.red.opacity(0.45)
                        : Color.clear,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(voiceState == .requestingPermission || voiceState == .transcribing)
        .help(voiceState == .listening ? "Ferma registrazione" : "Dettatura vocale")
    }

    // MARK: - Send Button

    private var sendButton: some View {
        let awaitingChoice = if case .awaitingChoice = planningState { true } else { false }
        let canSend =
            (!inputText.isEmpty || !attachedImageURLs.isEmpty)
            && !isLoading
            && !awaitingChoice
            && isProviderReady

        return Button(action: onSend) {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(canSend ? .black.opacity(0.9) : .secondary)
                .frame(width: 38, height: 38)
                .background(
                    Circle().fill(
                        canSend ? Color.white : Color.white.opacity(0.24)
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .animation(.easeOut(duration: 0.15), value: canSend)
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
