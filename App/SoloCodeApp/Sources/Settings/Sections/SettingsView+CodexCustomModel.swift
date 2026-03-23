import SwiftUI

extension SettingsView {
    var codexCustomModelGroup: some View {
        GroupBox("Preset Modello Codex") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Abilita GPT-5.4 1M", isOn: codexCustomModelToggleBinding)
                hintBox(
                    "Quando attivo, preserva e sincronizza `gpt-5.4` con `model_context_window = 1000000` e `model_auto_compact_token_limit = 900000` su `~/.codex/config.toml` e sui profili Codex dell'app."
                )
                hintBox(
                    "Quando lo disattivi, Solo Code commenta il blocco gestito nel file di configurazione invece di cancellarlo, così puoi riattivarlo senza perdere i valori."
                )
            }
            .padding(4)
        }
    }

    var codexCustomModelToggleBinding: Binding<Bool> {
        Binding(
            get: { codexCustomGPT54Enabled },
            set: { isEnabled in
                codexCustomGPT54Enabled = isEnabled
                if isEnabled {
                    codexModelOverride = CodexCustomModelProfileSync.slug
                    codexReasoningEffort = "high"
                    codexVerbosity = "high"
                } else if codexModelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == CodexCustomModelProfileSync.slug {
                    codexModelOverride = ""
                }

                saveCodexToml()
                syncCodex()
            }
        )
    }
}
