import SwiftUI

extension DebugPanelView {
    /// Card interattiva solo per `debug_request_user` con kind generico (chiarimento).
    @ViewBuilder
    func clarificationResponseCard(parsed: DebugClarificationPromptParser.Parsed) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(accent.opacity(0.1))
                        .frame(width: 26, height: 26)
                    Image(systemName: "questionmark.bubble.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Domanda di chiarimento")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text(phaseClarificationSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            }

            if !parsed.preamble.isEmpty {
                Text(parsed.preamble)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.045))
                    )
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(accent.opacity(0.75))
                            .frame(width: 3)
                            .padding(.vertical, 6)
                            .padding(.leading, 4)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(accent.opacity(0.12), lineWidth: 0.5)
                    )
            }

            if !parsed.options.isEmpty {
                Text("Scegli l’opzione più vicina al tuo caso (puoi integrare sotto).")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(parsed.options) { opt in
                        clarificationOptionRow(opt, isSelected: clarificationSelectedLetter == opt.letter) {
                            clarificationSelectedLetter = opt.letter
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Dettagli, streaming/provider, altro")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                TextField(
                    parsed.options.isEmpty
                        ? "Scrivi la risposta completa…"
                        : "Testo libero (es. solo durante streaming, provider Claude…)",
                    text: $clarificationCustomNotes,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .lineLimit(3...8)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                )
            }

            Button {
                let body = composeClarificationSubmission(parsed: parsed)
                guard !body.isEmpty else { return }
                onSubmitDebugClarification(body)
                clarificationSelectedLetter = nil
                clarificationCustomNotes = ""
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 10))
                    Text("Invia all’agente")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    canSubmitClarification(parsed: parsed) ? accent : accent.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmitClarification(parsed: parsed))
        }
        .padding(12)
        .background(accent.opacity(0.03))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func clarificationOptionRow(
        _ opt: DebugClarificationPromptParser.Parsed.Option,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? accent : DesignSystem.Colors.textTertiary)
                    .padding(.top, 1)

                HStack(alignment: .top, spacing: 6) {
                    Text("(\(opt.letter))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                    Text(opt.text)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? accent.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? accent.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    func canSubmitClarification(parsed: DebugClarificationPromptParser.Parsed) -> Bool {
        let extra = clarificationCustomNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if parsed.options.isEmpty {
            return !extra.isEmpty
        }
        return clarificationSelectedLetter != nil || !extra.isEmpty
    }

    func composeClarificationSubmission(
        parsed: DebugClarificationPromptParser.Parsed
    ) -> String {
        var lines: [String] = ["[Risposta dal pannello Debug — chiarimento]"]
        let extra = clarificationCustomNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let letter = clarificationSelectedLetter,
           let chosen = parsed.options.first(where: { $0.letter == letter }) {
            lines.append("Scelta: (\(chosen.letter)) \(chosen.text)")
        }
        if !extra.isEmpty {
            lines.append("Dettagli / contesto: \(extra)")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
