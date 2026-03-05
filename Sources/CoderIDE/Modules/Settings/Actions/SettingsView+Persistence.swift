import AppKit
import SwiftUI
import CoderEngine

extension SettingsView {
    func normalizeStoredSelections() {
        if !openAIModels.contains(openaiModel), let first = openAIModels.first { openaiModel = first }
        if !anthropicModels.contains(anthropicModel), let first = anthropicModels.first { anthropicModel = first }
        if !googleModels.contains(googleModel), let first = googleModels.first { googleModel = first }
        if !minimaxModels.contains(minimaxModel), let first = minimaxModels.first { minimaxModel = first }
        if !grokModels.contains(grokModel), let first = grokModels.first { grokModel = first }
        if !["low", "medium", "high"].contains(reasoningEffort) { reasoningEffort = "medium" }
        if !["read-only", "workspace-write", "danger-full-access"].contains(codexSandbox) { codexSandbox = "workspace-write" }
        if !["never", "on-request", "untrusted"].contains(codexAskForApproval) { codexAskForApproval = "never" }
        if !["codex", "claude"].contains(planModeBackend) { planModeBackend = "codex" }
        let validClaudeSlugs = ClaudeModelsCache.loadModels().map(\.slug)
        if !validClaudeSlugs.contains(claudeModel) {
            switch claudeModel {
            case "sonnet":
                claudeModel = "claude-sonnet-4-6"
            case "opus":
                claudeModel = "claude-opus-4-6"
            case "haiku":
                claudeModel = "claude-haiku-4-5-20251001"
            default:
                claudeModel = "claude-sonnet-4-6"
            }
        }
        if !["system", "light", "dark"].contains(appearance) { appearance = "system" }
        chatBackgroundStyle = ChatBackgroundStyle.normalizedRawValue(chatBackgroundStyle)
        if !["openai-api", "codex-cli", "claude-cli"].contains(summarizeProvider) { summarizeProvider = "openai-api" }
    }
    func loadCodexAdvanced() {
        let cfg = CodexConfigLoader.load()
        codexSandbox = cfg.sandboxMode ?? ""
        codexModelOverride = cfg.model ?? ""
        codexModelProvider = cfg.modelProvider ?? ""
        codexReasoningEffort = cfg.modelReasoningEffort ?? "low"
        codexFastMode = CodexFastModeStore.hydrateFromConfig()
        codexReasoningSummary = cfg.modelReasoningSummary ?? "auto"
        codexVerbosity = cfg.modelVerbosity ?? "medium"
        let validPersonalities = ["none", "friendly", "pragmatic"]
        codexPersonality = validPersonalities.contains(cfg.personality ?? "none") ? (cfg.personality ?? "none") : "none"
        codexNetworkAccess = cfg.networkAccess ?? false
        codexAdditionalWriteRoots = cfg.additionalWriteRoots.joined(separator: ", ")
        codexDeveloperInstructions = cfg.developerInstructions ?? ""
        codexCheckUpdate = cfg.checkForUpdateOnStartup ?? true
        codexAgentsMd = CodexAgentsFile.loadGlobal()
        normalizeStoredSelections()
        reloadRulesFromDisk()
    }
    func saveCodexToml() {
        var cfg = CodexConfigLoader.load()
        if !codexSandbox.isEmpty { cfg.sandboxMode = codexSandbox }
        cfg.fastMode = codexFastMode
        if !codexModelOverride.isEmpty { cfg.model = codexModelOverride }
        if !codexModelProvider.isEmpty { cfg.modelProvider = codexModelProvider }

        let model = codexModelOverride.lowercased()
        let isReasoningModel = model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4")
        if isReasoningModel {
            if !codexReasoningEffort.isEmpty { cfg.modelReasoningEffort = codexReasoningEffort }
            cfg.modelReasoningSummary = codexReasoningSummary == "auto" ? nil : codexReasoningSummary
        } else {
            cfg.modelReasoningEffort = nil
            cfg.modelReasoningSummary = nil
        }
        cfg.modelVerbosity = codexVerbosity == "medium" ? nil : codexVerbosity
        cfg.personality = codexPersonality == "none" ? nil : codexPersonality
        cfg.networkAccess = codexNetworkAccess ? true : nil
        cfg.additionalWriteRoots = codexAdditionalWriteRoots.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        cfg.developerInstructions = codexDeveloperInstructions.isEmpty ? nil : codexDeveloperInstructions
        cfg.checkForUpdateOnStartup = codexCheckUpdate ? nil : false
        CodexConfigLoader.save(cfg)
    }
    func refreshIndexStatus() async {
        let index = workspaceStore.codebaseIndex
        let info = await index.status()
        switch info.status {
        case .idle: indexStatusText = "Idle - no indexed workspace"
        case .indexing: indexStatusText = "Indexing..."
        case .ready:
            let duration = info.indexDurationMs > 0 ? " (\(info.indexDurationMs)ms)" : ""
            indexStatusText = "Ready\(duration)"
        case .error: indexStatusText = "Indexing error"
        }
        var stats: [String] = []
        if info.totalFiles > 0 { stats.append("\(info.totalFiles) files") }
        if info.totalSourceFiles > 0 { stats.append("\(info.totalSourceFiles) sources") }
        if info.totalSymbols > 0 { stats.append("\(info.totalSymbols) symbols") }
        indexStatsText = stats.joined(separator: " · ")
    }
    func parseClaudeAllowedTools() -> [String] {
        ProviderFactory.normalizedToolList(from: claudeAllowedTools)
    }
    var currentProjectRootPath: String? {
        if let active = workspaceStore.activeWorkspace, let root = active.folderPaths.first, !root.isEmpty { return root }
        return workspaceStore.workspaces.first(where: { !$0.folderPaths.isEmpty })?.folderPaths.first
    }
    func reloadRulesFromDisk() {
        globalRuleDocs = CoderRulesFile.loadGlobalRules()
        if selectedGlobalRuleName.isEmpty || !globalRuleDocs.contains(where: { $0.name == selectedGlobalRuleName }) {
            selectedGlobalRuleName = globalRuleDocs.first?.name ?? ""
        }
        globalRuleContentDraft = globalRuleDocs.first(where: { $0.name == selectedGlobalRuleName })?.content ?? ""
        if let root = currentProjectRootPath {
            projectRuleDocs = CoderRulesFile.loadProjectRules(workspacePath: root)
            if selectedProjectRuleName.isEmpty || !projectRuleDocs.contains(where: { $0.name == selectedProjectRuleName }) {
                selectedProjectRuleName = projectRuleDocs.first?.name ?? ""
            }
            projectRuleContentDraft = projectRuleDocs.first(where: { $0.name == selectedProjectRuleName })?.content ?? ""
        } else {
            projectRuleDocs = []; selectedProjectRuleName = ""; projectRuleContentDraft = ""
        }
    }
    func createGlobalRule() {
        let base = newGlobalRuleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }
        CoderRulesFile.saveGlobalRule(name: base, content: "# \(base.replacingOccurrences(of: ".md", with: ""))\n")
        newGlobalRuleName = ""
        reloadRulesFromDisk()
        if let created = globalRuleDocs.last?.name {
            selectedGlobalRuleName = created
            globalRuleContentDraft = globalRuleDocs.first(where: { $0.name == created })?.content ?? ""
        }
    }
    func saveSelectedGlobalRule() {
        guard !selectedGlobalRuleName.isEmpty else { return }
        CoderRulesFile.saveGlobalRule(name: selectedGlobalRuleName, content: globalRuleContentDraft)
        reloadRulesFromDisk()
    }
    func deleteSelectedGlobalRule() {
        guard !selectedGlobalRuleName.isEmpty else { return }
        CoderRulesFile.deleteGlobalRule(name: selectedGlobalRuleName)
        reloadRulesFromDisk()
    }
    func createProjectRule() {
        guard let root = currentProjectRootPath else { return }
        let base = newProjectRuleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }
        CoderRulesFile.saveProjectRule(name: base, content: "# \(base.replacingOccurrences(of: ".md", with: ""))\n", workspacePath: root)
        newProjectRuleName = ""
        reloadRulesFromDisk()
        if let created = projectRuleDocs.last?.name {
            selectedProjectRuleName = created
            projectRuleContentDraft = projectRuleDocs.first(where: { $0.name == created })?.content ?? ""
        }
    }
    func saveSelectedProjectRule() {
        guard let root = currentProjectRootPath, !selectedProjectRuleName.isEmpty else { return }
        CoderRulesFile.saveProjectRule(name: selectedProjectRuleName, content: projectRuleContentDraft, workspacePath: root)
        reloadRulesFromDisk()
    }
    func deleteSelectedProjectRule() {
        guard let root = currentProjectRootPath, !selectedProjectRuleName.isEmpty else { return }
        CoderRulesFile.deleteProjectRule(name: selectedProjectRuleName, workspacePath: root)
        reloadRulesFromDisk()
    }
    func openFullDiskAccessPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
    func refreshUsageSnapshotsForSettings() async {
        let codexBin = CodexDetector.findCodexPath(customPath: codexPath.isEmpty ? nil : codexPath) ?? ""
        let claudeBin = ClaudeDetector.findClaudePath(customPath: claudePath.isEmpty ? nil : claudePath) ?? ""
        let geminiBin = GeminiDetector.findGeminiPath(customPath: geminiCliPath.isEmpty ? nil : geminiCliPath) ?? ""
        await providerUsageStore.fetchCodexUsage(codexPath: codexBin, workingDirectory: nil)
        await providerUsageStore.fetchClaudeUsage(
            claudePath: claudeBin,
            workingDirectory: nil,
            anthropicAdminApiKey: anthropicAdminApiKey
        )
        await providerUsageStore.fetchGeminiUsage(geminiPath: geminiBin, workingDirectory: nil)
    }
}
