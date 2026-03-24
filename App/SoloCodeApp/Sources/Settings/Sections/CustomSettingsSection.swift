import CoderEngine
import SwiftUI

// MARK: - Custom Settings Section

struct CustomSettingsSection: View {
    @EnvironmentObject var syncCoordinator: SettingsSyncCoordinator

    // MARK: - AppStorage Containers

    @State var runtimeConfig = SettingsRuntimeConfig()
    @State var cliConfig = SettingsCLIConfig()

    // MARK: - Local State

    @State private var codexAgentsMd = ""
    @State private var customAgentsDraft = ""
    @State private var savedAgentsSnapshot = ""
    @State private var savedPersonalitySnapshot = "none"
    @State private var isSavingCustom = false
    @State private var customSaveMessage = ""

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSectionHeader(
                title: "Custom",
                subtitle: "Personality and AGENTS.md for CLI/API providers",
                icon: "slider.horizontal.3"
            )

            personalityGroup
            customInstructionsGroup
        }
        .onAppear { prepareCustomDraftIfNeeded() }
    }
}

// MARK: - Sub-views

private extension CustomSettingsSection {
    var personalityGroup: some View {
        GroupBox("Personality") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $runtimeConfig.codexPersonality) {
                    Text("None").tag("none")
                    Text("Friendly").tag("friendly")
                    Text("Pragmatic").tag("pragmatic")
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                settingsHintBox("Sets Codex CLI personality in config.toml.")
            }
            .padding(4)
        }
    }

    var customInstructionsGroup: some View {
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

                actionButtons
                saveMessageLabel
            }
            .padding(4)
        }
    }

    var actionButtons: some View {
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
    }

    @ViewBuilder
    var saveMessageLabel: some View {
        if !customSaveMessage.isEmpty {
            Text(customSaveMessage)
                .font(.caption)
                .foregroundStyle(customSaveMessageColor)
        }
    }
}

// MARK: - Computed Properties

private extension CustomSettingsSection {
    var isCustomDirty: Bool {
        customAgentsDraft != savedAgentsSnapshot
            || runtimeConfig.codexPersonality != savedPersonalitySnapshot
    }

    var customSaveMessageColor: Color {
        customSaveMessage.hasPrefix("Error") ? .red : .secondary
    }
}

// MARK: - Actions

private extension CustomSettingsSection {
    func prepareCustomDraftIfNeeded() {
        let globalExists = FileManager.default.fileExists(atPath: CodexAgentsFile.globalPath)
        let currentGlobal = CodexAgentsFile.loadGlobal()
        let draftContent = globalExists ? currentGlobal : CLIProfileProvisioner.codexInstructionsTemplate

        codexAgentsMd = currentGlobal
        savedAgentsSnapshot = currentGlobal
        customAgentsDraft = draftContent
        savedPersonalitySnapshot = runtimeConfig.codexPersonality
        customSaveMessage = ""
    }

    func resetCustomDraftFromCurrentSource() {
        let globalExists = FileManager.default.fileExists(atPath: CodexAgentsFile.globalPath)
        let currentGlobal = CodexAgentsFile.loadGlobal()
        customAgentsDraft = globalExists ? currentGlobal : CLIProfileProvisioner.codexInstructionsTemplate
        codexAgentsMd = currentGlobal
        savedAgentsSnapshot = currentGlobal
        savedPersonalitySnapshot = runtimeConfig.codexPersonality
        customSaveMessage = ""
    }

    func saveCustomSettings() {
        guard !isSavingCustom else { return }
        isSavingCustom = true
        customSaveMessage = "Saving..."

        let content = customAgentsDraft

        CodexTomlSaver.save(
            cliConfig: cliConfig,
            runtimeConfig: runtimeConfig,
            accounts: CLIAccountsStore.shared.accounts
        )
        CodexAgentsFile.saveGlobal(content)
        let report = CLIProfileProvisioner.syncAgentsContentToManagedAndGlobalProfiles(content)
        InstructionPolicyBundle.invalidateCache()
        syncCoordinator.syncAll()

        codexAgentsMd = content
        savedAgentsSnapshot = content
        savedPersonalitySnapshot = runtimeConfig.codexPersonality

        if report.hasFailures {
            let failures = report.failedPaths.prefix(3).joined(separator: " | ")
            customSaveMessage = "Error: saved with partial failures (\(failures))"
        } else {
            customSaveMessage = "Saved. Updated \(report.writtenPaths.count) files."
        }

        isSavingCustom = false
    }
}
