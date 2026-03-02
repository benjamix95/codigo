import SwiftUI

/// Popup che mostra il prompt ottimizzato con opzioni per accettare o annullare.
struct PromptOptimizerPopup: View {
    let originalPrompt: String
    let optimizedPrompt: String
    let onAccept: (String) -> Void
    let onCancel: () -> Void

    @State private var editedPrompt: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.yellow)
                Text("Prompt Ottimizzato")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            Divider()
                .opacity(0.4)

            // Prompt originale (collassato)
            VStack(alignment: .leading, spacing: 4) {
                Text("Originale")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(originalPrompt)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .lineLimit(3)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            }

            // Prompt ottimizzato (editabile)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ottimizzato")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.yellow.opacity(0.9))
                TextEditor(text: $editedPrompt)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 200)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.yellow.opacity(0.2), lineWidth: 0.6)
                    )
            }

            Divider()
                .opacity(0.4)

            // Azioni
            HStack(spacing: 10) {
                Spacer()
                Button("Annulla") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )

                Button {
                    onAccept(editedPrompt)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Usa questo prompt")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.yellow)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 6)
        .onAppear {
            editedPrompt = optimizedPrompt
        }
    }
}
