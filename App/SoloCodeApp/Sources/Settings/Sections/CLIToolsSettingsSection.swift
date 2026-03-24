import SwiftUI
import CoderEngine

// MARK: - CLI Tools Settings Section (Standalone)

struct CLIToolsSettingsSection: View {
    // MARK: - DynamicProperty Containers

    @State var cliConfig = SettingsCLIConfig()
    var runtimeConfig = SettingsRuntimeConfig()

    // MARK: - Environment

    @EnvironmentObject var syncCoordinator: SettingsSyncCoordinator
    @EnvironmentObject var providerUsageStore: ProviderUsageStore

    // MARK: - State Objects

    @StateObject var codexState = CodexStateStore()
    @StateObject var codexMCPHealth = CodexMCPHealthStore.shared
    @StateObject var geminiState = GeminiStateStore()
    @StateObject var kiloState = KiloStateStore()
    @StateObject var cliAccountsStore = CLIAccountsStore.shared
    @StateObject var cliUsageLedger = CLIAccountUsageLedgerStore.shared
    @StateObject var accountLoginCoordinator = CLIAccountLoginCoordinator()

    // MARK: - UI State

    @State var loginSheetAccount: CLIAccount?
    @State var showDeleteConfirmation: UUID?
    @State var pendingLoginAccountIds: Set<UUID> = []

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSectionHeader(title: "CLI Tools", subtitle: "Codex, Claude Code, and Gemini CLI", icon: "terminal")
            codexGroup
            codexCustomModelGroup
            multiAccountProviderSection(.codex)
            claudeCodeGroup
            multiAccountProviderSection(.claude)
            geminiGroup
            multiAccountProviderSection(.gemini)
            kiloGroup
        }
        .sheet(item: $loginSheetAccount) { account in
            CLIAccountLoginSheet(
                account: account,
                providerPath: providerPath(for: account.provider),
                onDismiss: {
                    handleLoginSheetDismiss(for: account)
                }
            )
        }
        .onAppear {
            cliAccountsStore.bootstrapAccountsIfNeeded()
            codexMCPHealth.refresh()
            geminiState.refresh()
            kiloState.refresh()
        }
        .onChange(of: cliConfig.codexPath) { _ in codexState.refresh(); syncCoordinator.syncCodex() }
        .onChange(of: cliConfig.codexSandbox) { _ in syncCoordinator.syncCodex(); saveCodexToml() }
        .onChange(of: cliConfig.codexAskForApproval) { _ in syncCoordinator.syncCodex() }
        .onChange(of: cliConfig.codexModelOverride) { _ in syncCoordinator.syncCodex(); saveCodexToml() }
        .onChange(of: cliConfig.codexReasoningEffort) { _ in syncCoordinator.syncCodex(); saveCodexToml() }
        .onChange(of: cliConfig.codexFastMode) { _ in syncCoordinator.syncCodex(); saveCodexToml() }
        .onChange(of: cliConfig.codexModelProvider) { _ in syncCoordinator.syncCodex(); saveCodexToml() }
        .onChange(of: cliConfig.codexPreferResponsesWireAPI) { _ in syncCoordinator.syncCodex() }
        .onChange(of: cliConfig.codexSessionFullAccess) { _ in syncCoordinator.syncCodex() }
        .onChange(of: cliConfig.codexCustomGPT54Enabled) { _ in syncCoordinator.syncCodex(); saveCodexToml() }
        .onChange(of: cliConfig.codexNetworkAccess) { _ in saveCodexToml() }
        .onChange(of: cliConfig.codexAdditionalWriteRoots) { _ in saveCodexToml() }
        .onChange(of: cliConfig.codexCheckUpdate) { _ in saveCodexToml() }
        .onChange(of: cliConfig.codexDeveloperInstructions) { _ in saveCodexToml() }
        .onChange(of: runtimeConfig.codexVerbosity) { _ in saveCodexToml() }
        .onChange(of: cliConfig.claudePath) { _ in syncCoordinator.syncClaude() }
        .onChange(of: cliConfig.claudeModel) { _ in syncCoordinator.syncClaude() }
        .onChange(of: cliConfig.claudeAllowedTools) { _ in syncCoordinator.syncClaude() }
        .onChange(of: cliConfig.geminiCliPath) { _ in syncCoordinator.syncGemini() }
        .onChange(of: cliConfig.kiloPath) { _ in kiloState.refresh(); syncCoordinator.syncKilo() }
        .onChange(of: cliConfig.kiloModel) { _ in syncCoordinator.syncKilo() }
    }
}

// MARK: - Codex TOML Persistence

extension CLIToolsSettingsSection {
    func saveCodexToml() {
        CodexTomlSaver.save(
            cliConfig: cliConfig,
            runtimeConfig: runtimeConfig,
            accounts: cliAccountsStore.accounts
        )
    }

    func parseClaudeAllowedTools() -> [String] {
        ProviderFactory.normalizedToolList(from: cliConfig.claudeAllowedTools)
    }

    func providerPath(for provider: CLIProviderKind) -> String? {
        switch provider {
        case .codex: return cliConfig.codexPath
        case .claude: return cliConfig.claudePath
        case .gemini: return cliConfig.geminiCliPath
        }
    }
}
