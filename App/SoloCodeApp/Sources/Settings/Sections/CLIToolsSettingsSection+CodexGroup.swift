import SwiftUI
import CoderEngine

// MARK: - Codex CLI Group

extension CLIToolsSettingsSection {
    var codexGroup: some View {
        GroupBox("Codex CLI") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    settingsFieldLabel("Path")
                    TextField("Auto-detect", text: $cliConfig.codexPath).textFieldStyle(.roundedBorder)
                    settingsStatusBadge(
                        connected: codexState.status.isLoggedIn,
                        label: codexState.status.isLoggedIn ? "Connected" : "Not connected"
                    )
                }
                Button("Connect to Codex") { connectToCodex() }
                    .buttonStyle(.borderedProminent).controlSize(.small)

                HStack(spacing: 8) {
                    settingsStatusBadge(
                        connected: codexMCPHealth.isHealthy,
                        label: codexMCPHealth.statusLabel
                    )
                    Spacer()
                    Button("Re-check") {
                        codexMCPHealth.refresh()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if codexMCPHealth.canRepair {
                        Button("Repair profiles") {
                            codexMCPHealth.repairProfiles()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                Divider()
                settingsFieldLabel("Sandbox")
                Picker("", selection: $cliConfig.codexSandbox) {
                    Text("Read Only").tag("read-only")
                    Text("Workspace Write").tag("workspace-write")
                    Text("Full Access").tag("danger-full-access")
                }.labelsHidden().pickerStyle(.segmented)

                settingsFieldLabel("Approval")
                Picker("", selection: $cliConfig.codexAskForApproval) {
                    Text("Never").tag("never")
                    Text("On request").tag("on-request")
                    Text("Untrusted").tag("untrusted")
                }.labelsHidden().pickerStyle(.segmented)

                settingsFieldLabel("Speed")
                Picker("", selection: $cliConfig.codexFastMode) {
                    Text("Standard").tag(false)
                    Text("Fast").tag(true)
                }.labelsHidden().pickerStyle(.segmented)

                Toggle("Prefer OpenAI Responses wire API", isOn: $cliConfig.codexPreferResponsesWireAPI)
                settingsHintBox(
                    "When enabled, Codex CLI runs with `model_providers.openai.wire_api=\"responses\"`."
                )
                settingsHintBox("Fast mode controls Codex CLI inference speed across threads, subagents, and compaction.")

                Toggle("Network access", isOn: $cliConfig.codexNetworkAccess)
                Toggle("Check for updates", isOn: $cliConfig.codexCheckUpdate)
            }.padding(4)
        }
    }

    // MARK: - Codex Custom Model Preset

    var codexCustomModelGroup: some View {
        GroupBox("Preset Modello Codex") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Abilita GPT-5.4 1M", isOn: codexCustomModelToggleBinding)
                settingsHintBox(
                    "Quando attivo, preserva e sincronizza `gpt-5.4` con `model_context_window = 1000000` e `model_auto_compact_token_limit = 900000` su `~/.codex/config.toml` e sui profili Codex dell'app."
                )
                settingsHintBox(
                    "Quando lo disattivi, Solo Code commenta il blocco gestito nel file di configurazione invece di cancellarlo, così puoi riattivarlo senza perdere i valori."
                )
            }
            .padding(4)
        }
    }

    var codexCustomModelToggleBinding: Binding<Bool> {
        Binding(
            get: { cliConfig.codexCustomGPT54Enabled },
            set: { isEnabled in
                cliConfig.codexCustomGPT54Enabled = isEnabled
                if isEnabled {
                    cliConfig.codexModelOverride = CodexCustomModelProfileSync.slug
                    cliConfig.codexReasoningEffort = "high"
                    runtimeConfig.codexVerbosity = "high"
                } else if cliConfig.codexModelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == CodexCustomModelProfileSync.slug {
                    cliConfig.codexModelOverride = ""
                }
                saveCodexToml()
                syncCoordinator.syncCodex()
            }
        )
    }

    // MARK: - Connect Actions

    func connectToCodex() {
        guard codexState.status.path != nil
            || CodexDetector.findCodexPath(customPath: cliConfig.codexPath.isEmpty ? nil : cliConfig.codexPath) != nil
        else { return }
        if codexState.status.isLoggedIn {
            syncCoordinator.syncCodex()
        } else {
            let existingAccounts = cliAccountsStore.accounts(for: .codex)
            if let first = existingAccounts.first {
                loginSheetAccount = first
            } else {
                let account = cliAccountsStore.addAccountQuick(provider: .codex)
                pendingLoginAccountIds.insert(account.id)
                loginSheetAccount = account
            }
        }
    }

    func connectToClaude() {
        guard ClaudeDetector.findClaudePath(
            customPath: cliConfig.claudePath.isEmpty ? nil : cliConfig.claudePath
        ) != nil else { return }
        let existingAccounts = cliAccountsStore.accounts(for: .claude)
        if let first = existingAccounts.first {
            loginSheetAccount = first
        } else {
            let account = cliAccountsStore.addAccountQuick(provider: .claude)
            pendingLoginAccountIds.insert(account.id)
            loginSheetAccount = account
        }
    }
}
