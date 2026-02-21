import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Chat Composer View
/// Extracted from ChatPanelView.composerArea / composerBox to reduce complexity.
/// Contains the text input, image attachments, send button, provider/model pickers,
/// and the drag-and-drop / paste image handling.

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
    let activeModeColor: Color
    let activeModeGradient: LinearGradient
    let inputHint: String
    let providerNotReadyMessage: String
    let quickCommandPresets: [QuickCommandPreset]
    let showCodeReviewAutofixToggle: Bool
    @Binding var codeReviewAutofixEnabled: Bool

    let onSend: () -> Void
    let onApplyQuickCommand: (String) -> Void
    let onRunQuickCommand: (String) -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            separator

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

    // MARK: - Separator

    private var separator: some View {
        Rectangle()
            .fill(DesignSystem.Colors.border)
            .frame(height: 0.5)
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
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                // Attached images preview row
                if !attachedImageURLs.isEmpty {
                    attachedImagesRow
                }

                // Text field — hint moved to placeholder
                TextField(inputHint, text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...8)
                    .focused($focusState)
                    .onSubmit { onSend() }
                    .onChange(of: isInputFocused) { _, newValue in
                        focusState = newValue
                    }
                    .onChange(of: focusState) { _, newValue in
                        isInputFocused = newValue
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                imageAttachButton
                sendButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DesignSystem.Colors.backgroundTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isComposerDropTargeted
                        ? activeModeColor.opacity(0.5)
                        : (focusState
                            ? activeModeColor.opacity(0.3) : DesignSystem.Colors.border.opacity(0.6)),
                    lineWidth: isComposerDropTargeted ? 2 : (focusState ? 1 : 0.5)
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
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
                RoundedRectangle(cornerRadius: 20, style: .continuous)
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

    // MARK: - Focus
    @FocusState private var focusState: Bool

    // MARK: - Attached Images Row

    private var attachedImagesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(attachedImageURLs.enumerated()), id: \.offset) { index, url in
                    ZStack(alignment: .topTrailing) {
                        if let nsImage = NSImage(contentsOf: url) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        Button {
                            attachedImageURLs.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 1)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                }
            }
        }
    }

    // MARK: - Image Attach Button

    private var imageAttachButton: some View {
        Button {
            isSelectingImage = true
        } label: {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Allega immagine (⌘V per incollare)")
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
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background {
                    Circle().fill(
                        canSend
                            ? activeModeGradient
                            : LinearGradient(
                                colors: [DesignSystem.Colors.borderAccent],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
                }
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .animation(.easeOut(duration: 0.15), value: canSend)
    }
}
