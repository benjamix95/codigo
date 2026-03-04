import SwiftUI
import CoderEngine

extension SettingsView {
    var customSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "Custom",
                subtitle: "Personality and AGENTS.md for CLI/API providers",
                icon: "slider.horizontal.3"
            )

            GroupBox("Personality") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("", selection: $codexPersonality) {
                        Text("None").tag("none")
                        Text("Friendly").tag("friendly")
                        Text("Pragmatic").tag("pragmatic")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    hintBox("Sets Codex CLI personality in config.toml.")
                }
                .padding(4)
            }

            GroupBox("Custom Instructions (AGENTS.md)") {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $customAgentsDraft)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .frame(minHeight: 220)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        )

                    Text("Global source: \(CodexAgentsFile.globalPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        Button("Reset") {
                            resetCustomDraftFromCurrentSource()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isSavingCustom)

                        Spacer()

                        Button {
                            saveCustomSettings()
                        } label: {
                            if isSavingCustom {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Saving...")
                                }
                            } else {
                                Text("Salva")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isSavingCustom || !isCustomDirty)
                    }

                    if !customSaveMessage.isEmpty {
                        Text(customSaveMessage)
                            .font(.caption)
                            .foregroundStyle(customSaveMessageColor)
                    }
                }
                .padding(4)
            }
        }
    }

    var isCustomDirty: Bool {
        customAgentsDraft != savedAgentsSnapshot || codexPersonality != savedPersonalitySnapshot
    }

    var customSaveMessageColor: Color {
        if customSaveMessage.hasPrefix("Error") {
            return .red
        }
        return .secondary
    }
}
