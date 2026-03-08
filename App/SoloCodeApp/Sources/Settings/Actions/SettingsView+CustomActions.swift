import CoderEngine
import Foundation
import SwiftUI

extension SettingsView {
    func prepareCustomDraftIfNeeded() {
        let globalExists = FileManager.default.fileExists(atPath: CodexAgentsFile.globalPath)
        let currentGlobal = CodexAgentsFile.loadGlobal()
        let draftContent = globalExists ? currentGlobal : CLIProfileProvisioner.codexInstructionsTemplate

        codexAgentsMd = currentGlobal
        savedAgentsSnapshot = currentGlobal
        customAgentsDraft = draftContent
        savedPersonalitySnapshot = codexPersonality
        customSaveMessage = ""
    }

    func resetCustomDraftFromCurrentSource() {
        let globalExists = FileManager.default.fileExists(atPath: CodexAgentsFile.globalPath)
        let currentGlobal = CodexAgentsFile.loadGlobal()
        customAgentsDraft = globalExists ? currentGlobal : CLIProfileProvisioner.codexInstructionsTemplate
        codexAgentsMd = currentGlobal
        savedAgentsSnapshot = currentGlobal
        savedPersonalitySnapshot = codexPersonality
        customSaveMessage = ""
    }

    func saveCustomSettings() {
        guard !isSavingCustom else { return }
        isSavingCustom = true
        customSaveMessage = "Saving..."

        let content = customAgentsDraft

        saveCodexToml()
        CodexAgentsFile.saveGlobal(content)
        let report = CLIProfileProvisioner.syncAgentsContentToManagedAndGlobalProfiles(content)
        InstructionPolicyBundle.invalidateCache()
        syncProviders()

        codexAgentsMd = content
        savedAgentsSnapshot = content
        savedPersonalitySnapshot = codexPersonality

        if report.hasFailures {
            let failures = report.failedPaths.prefix(3).joined(separator: " | ")
            customSaveMessage = "Error: saved with partial failures (\(failures))"
        } else {
            customSaveMessage = "Saved. Updated \(report.writtenPaths.count) files."
        }

        isSavingCustom = false
    }
}
