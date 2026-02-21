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

    let onSend: () -> Void
    let onApplyQuickCommand: (String) -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            separator

            if !isProviderReady {
                providerNotReadyBanner
            }

            VStack(spacing: 8) {
                composerBox
                if !quickCommandPresets.isEmpty {
                    quickCommandsRow
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
                    .help(preset.prompt)
                }
            }
            .padding(.horizontal, 1)
        }
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
                // Mode indicator dot + hint
                HStack(spacing: 5) {
                    Circle()
                        .fill(activeModeGradient)
                        .frame(width: 6, height: 6)
                    Text(inputHint)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(activeModeColor.opacity(0.6))
                }

                // Attached images preview row
                if !attachedImageURLs.isEmpty {
                    attachedImagesRow
                }

                // Text field
                TextField("Send a message...", text: $inputText, axis: .vertical)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DesignSystem.Colors.backgroundTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isComposerDropTargeted
                        ? activeModeColor.opacity(0.6)
                        : (focusState
                            ? activeModeColor.opacity(0.4) : DesignSystem.Colors.border),
                    lineWidth: isComposerDropTargeted ? 2 : (focusState ? 1.2 : 0.5)
                )
        )
        .shadow(color: focusState ? activeModeColor.opacity(0.1) : .clear, radius: 12, y: 2)
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
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
                RoundedRectangle(cornerRadius: 12)
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
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
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
                .shadow(
                    color: canSend ? activeModeColor.opacity(0.3) : .clear,
                    radius: 6, y: 2
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .animation(.easeOut(duration: 0.15), value: canSend)
    }
}
