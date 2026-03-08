import Foundation

// MARK: - Panel Settings Management

extension CodeReviewPanelStore {

    /// Add a new custom command.
    func addCustomCommand(_ command: ReviewPanelCustomCommand) {
        settings.customCommands.append(command)
        saveSettings()
    }

    /// Remove a custom command by ID.
    func removeCustomCommand(id: String) {
        settings.customCommands.removeAll { $0.id == id }
        saveSettings()
    }

    /// Update an existing custom command.
    func updateCustomCommand(_ command: ReviewPanelCustomCommand) {
        guard let index = settings.customCommands.firstIndex(
            where: { $0.id == command.id }
        ) else { return }
        settings.customCommands[index] = command
        saveSettings()
    }

    /// Update custom instructions.
    func updateCustomInstructions(_ text: String) {
        settings.customInstructions = text
        saveSettings()
    }

    /// Update pipeline settings.
    func updatePipelineSettings(
        maxWorkers: Int? = nil,
        maxRounds: Int? = nil,
        analysisOnly: Bool? = nil,
        analysisBackend: String? = nil,
        executionBackend: String? = nil,
        patchDeliveryMode: ReviewPatchDeliveryMode? = nil,
        autoPreparePatchForVerifiedFindings: Bool? = nil,
        autoApplyVerifiedPatch: Bool? = nil,
        autoOpenPRAfterApply: Bool? = nil,
        autoMergeAfterGreen: Bool? = nil,
        autoResolveConflicts: ReviewConflictAutomation? = nil,
        showCandidatesInMainFindings: Bool? = nil,
        publishOutcomeToChat: Bool? = nil
    ) {
        if let v = maxWorkers { settings.maxWorkers = v }
        if let v = maxRounds { settings.maxRounds = v }
        if let v = analysisOnly { settings.analysisOnly = v }
        if let v = analysisBackend { settings.analysisBackend = v }
        if let v = executionBackend { settings.executionBackend = v }
        if let v = patchDeliveryMode { settings.patchDeliveryMode = v }
        if let v = autoPreparePatchForVerifiedFindings { settings.autoPreparePatchForVerifiedFindings = v }
        if let v = autoApplyVerifiedPatch { settings.autoApplyVerifiedPatch = v }
        if let v = autoOpenPRAfterApply { settings.autoOpenPRAfterApply = v }
        if let v = autoMergeAfterGreen { settings.autoMergeAfterGreen = v }
        if let v = autoResolveConflicts { settings.autoResolveConflicts = v }
        if let v = showCandidatesInMainFindings { settings.showCandidatesInMainFindings = v }
        if let v = publishOutcomeToChat { settings.publishOutcomeToChat = v }
        saveSettings()
    }

    /// Reset all settings to defaults.
    func resetSettingsToDefaults() {
        settings = ReviewPanelSettings()
        saveSettings()
    }

    /// Save current settings to UserDefaults.
    func saveSettings() {
        ReviewPanelSettingsPersistence.save(settings)
    }

    /// Reload settings from UserDefaults.
    func reloadSettings() {
        settings = ReviewPanelSettingsPersistence.load()
    }

    /// Combined slash commands: built-in + custom.
    var allSlashCommands: [ReviewPanelSlashCommand] {
        let builtIn = CodeReviewQuickCommands.defaults.map {
            ReviewPanelSlashCommand(
                id: $0.id, slash: $0.slash, label: $0.label,
                prompt: $0.prompt, isCustom: false
            )
        }
        let custom = settings.customCommands.map {
            ReviewPanelSlashCommand(
                id: $0.id, slash: $0.slash, label: $0.name,
                prompt: $0.prompt, isCustom: true
            )
        }
        return builtIn + custom
    }
}

// MARK: - Unified Slash Command

struct ReviewPanelSlashCommand: Identifiable {
    let id: String
    let slash: String
    let label: String
    let prompt: String
    let isCustom: Bool

    var displayCommand: String {
        slash.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
