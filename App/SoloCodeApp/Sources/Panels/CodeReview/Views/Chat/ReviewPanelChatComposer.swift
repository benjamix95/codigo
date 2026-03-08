import CoderEngine
import SwiftUI

/// Input composer for the review panel chat with timer, presets, and stop.
struct ReviewPanelChatComposer: View {
    @ObservedObject var store: CodeReviewPanelStore
    @Binding var inputText: String
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Preset chips when not processing
            if !store.isChatProcessing && store.chatMessages.isEmpty == false {
                presetRow
            }

            // Input row
            HStack(spacing: 6) {
                inputField

                if store.isChatProcessing {
                    processingControls
                } else {
                    sendButton
                }
            }

            providerPickerRow
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Input Field

    private var inputField: some View {
        TextField("Ask about the review...", text: $inputText)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        DesignSystem.Colors.border.opacity(0.3),
                        lineWidth: 0.5
                    )
            )
            .disabled(store.isChatProcessing)
            .onSubmit {
                guard !inputText.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty
                else { return }
                onSend()
            }
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            guard !inputText.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty
            else { return }
            onSend()
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(
                    inputText.trimmingCharacters(
                        in: .whitespacesAndNewlines).isEmpty
                        ? Color.secondary.opacity(0.5)
                        : store.accent
                )
        }
        .buttonStyle(.plain)
        .disabled(
            inputText.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty
        )
    }

    // MARK: - Processing Controls

    private var processingControls: some View {
        HStack(spacing: 6) {
            // Timer
            if let start = store.chatStartedAt {
                ElapsedTimerView(startDate: start) { elapsed in
                    Text(formatElapsed(elapsed))
                        .font(.system(size: 9, weight: .medium,
                                      design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Stop button
            Button(action: onCancel) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignSystem.Colors.error)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Preset Row

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ReviewChatPreset.defaults) { preset in
                    Button {
                        Task { await store.sendPresetMessage(preset) }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: preset.icon)
                                .font(.system(size: 7.5))
                            Text(preset.label)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(store.accent.opacity(0.8))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            store.accent.opacity(0.06),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isChatProcessing)
                }

                // Clear button
                if !store.chatMessages.isEmpty {
                    Button {
                        store.clearChatHistory()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "trash")
                                .font(.system(size: 7.5))
                            Text("Clear")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Color.primary.opacity(0.03),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isChatProcessing)
                }
            }
        }
    }

    private var providerPickerRow: some View {
        HStack(spacing: 8) {
            ReviewPanelChatProviderPicker(store: store)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Helper

    private func formatElapsed(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
