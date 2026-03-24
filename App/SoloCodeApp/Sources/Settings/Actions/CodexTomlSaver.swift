import CoderEngine
import Foundation

// MARK: - Codex TOML Persistence

/// Writes the current Codex CLI config.toml from @AppStorage-backed values.
/// Extracted as a standalone helper so both SettingsView and CustomSettingsSection
/// can call it without duplicating logic.
enum CodexTomlSaver {
    static func save(
        cliConfig: SettingsCLIConfig,
        runtimeConfig: SettingsRuntimeConfig,
        accounts: [CLIAccount]
    ) {
        var cfg = CodexConfigLoader.load()
        if !cliConfig.codexSandbox.isEmpty { cfg.sandboxMode = cliConfig.codexSandbox }
        cfg.fastMode = cliConfig.codexFastMode
        let trimmedModelOverride = cliConfig.codexModelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.model = trimmedModelOverride.isEmpty ? nil : trimmedModelOverride
        cfg.modelProvider = cliConfig.codexModelProvider.isEmpty ? nil : cliConfig.codexModelProvider

        let model = trimmedModelOverride.lowercased()
        let isReasoningModel = model.hasPrefix("o1")
            || model.hasPrefix("o3")
            || model.hasPrefix("o4")
            || model == CodexCustomModelProfileSync.slug
        if isReasoningModel {
            if !cliConfig.codexReasoningEffort.isEmpty { cfg.modelReasoningEffort = cliConfig.codexReasoningEffort }
            cfg.modelReasoningSummary = runtimeConfig.codexReasoningSummary == "auto" ? nil : runtimeConfig.codexReasoningSummary
        } else {
            cfg.modelReasoningEffort = nil
            cfg.modelReasoningSummary = nil
        }
        cfg.modelVerbosity = runtimeConfig.codexVerbosity == "medium" ? nil : runtimeConfig.codexVerbosity
        cfg.personality = runtimeConfig.codexPersonality == "none" ? nil : runtimeConfig.codexPersonality
        cfg.networkAccess = cliConfig.codexNetworkAccess ? true : nil
        cfg.additionalWriteRoots = cliConfig.codexAdditionalWriteRoots.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        cfg.developerInstructions = cliConfig.codexDeveloperInstructions.isEmpty ? nil : cliConfig.codexDeveloperInstructions
        cfg.checkForUpdateOnStartup = cliConfig.codexCheckUpdate ? nil : false

        let presetEnabled = cliConfig.codexCustomGPT54Enabled || model == CodexCustomModelProfileSync.slug
        let syncedConfig = CodexCustomModelProfileSync.applyPresetIfEnabled(
            to: cfg,
            enabled: presetEnabled,
            modelOverride: trimmedModelOverride
        )
        let codexHomes = CodexCustomModelProfileSync.allCodexHomes(accounts: accounts)
        CodexCustomModelProfileSync.sync(config: syncedConfig, codexHomes: codexHomes, enabled: presetEnabled)
    }
}
