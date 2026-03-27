import CoderEngine
import SwiftUI

struct UsageFooterView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var gitPanelStore: GitPanelStore
    @EnvironmentObject var projectContextStore: ProjectContextStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @StateObject var cliAccountsStore = CLIAccountsStore.shared
    @StateObject var cliAccountRouter = CLIAccountRouter.shared
    @StateObject var worktreeSessionStore = WorktreeSessionStore.shared
    @Binding var selectedConversationId: UUID?
    @AppStorage("context_scope_mode") var contextScopeModeRaw = "auto"
    @AppStorage("codex_path") var codexPath = ""
    @AppStorage("claude_path") var claudePath = ""
    @AppStorage("gemini_cli_path") var geminiCliPath = ""
    @AppStorage("openai_model") var openaiModelSetting = "gpt-4o-mini"
    @AppStorage("anthropic_model") var anthropicModelSetting = "claude-sonnet-4-6"
    @AppStorage("google_model") var googleModelSetting = "gemini-2.5-pro"
    @AppStorage("openrouter_model") var openrouterModelSetting = "anthropic/claude-sonnet-4-6"
    @AppStorage("minimax_model") var minimaxModelSetting = "MiniMax-M2.5"
    @AppStorage("grok_model") var grokModelSetting = "grok-4-1-fast-reasoning"
    @AppStorage("anthropic_admin_api_key") var anthropicAdminApiKey = ""
    @AppStorage("codex_model_override") var codexModelOverride = ""
    @AppStorage("gemini_model_override") var geminiModelOverride = ""
    let effectiveContext: EffectiveContext
    let planModeBackend: String
    let swarmWorkerBackend: String
    let openaiModel: String
    let claudeModel: String
    let contextRefreshTick: Int

    // MARK: - Grouped State

    @State var wt = UsageFooterWorktreeState()
    @State var ctx = UsageFooterContextState()

    @State private var availableWidth: CGFloat = 980
    @State private var resolvedTier: FooterTier = .full

    let cliSecretsStore = CLIAccountSecretsStore()

    enum FooterTier {
        case full
        case medium
        case compact
        case minimal
    }

    private let tierHysteresis: CGFloat = 20

    var effectiveProviderId: String? {
        providerRegistry.selectedProviderId
    }

    private var contextEstimateFingerprint: String {
        [
            effectiveContextModel,
            contextScopeModeRaw,
            "\(contextRefreshTick)",
            openFilesStore.openFilePath ?? "",
            contextEstimateConversationSignature,
        ].joined(separator: "|")
    }

    var body: some View {
        let tier = footerTierFlags(for: resolvedTier)

        footerTier(
            showFooterBranchPicker: tier.showFooterBranchPicker,
            showProviderUsage: tier.showProviderUsage,
            showContext: tier.showContext,
            showTotal: tier.showTotal,
            showMessages: tier.showMessages
        )
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        updateAvailableWidth(proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { newWidth in
                        updateAvailableWidth(newWidth)
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .padding(.vertical, 2)
        .sheet(isPresented: $wt.showWorktreeSheet) {
            worktreeCreateSheet
        }
        .onAppear {
            cliAccountRouter.bootstrapActiveSelectionsIfNeeded()
            scheduleRefresh()
            scheduleContextEstimateRefresh()
            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
            // #region agent log
            logUsageFooterTier(hypothesisId: "H1", reason: "onAppear")
            // #endregion
        }
        .onChange(of: resolvedTier) { newTier in
            // #region agent log
            logUsageFooterTier(hypothesisId: "H1", reason: "tier_change", tierOverride: newTier)
            // #endregion
        }
        .onChange(of: effectiveProviderId) { _ in
            scheduleRefresh()
            scheduleContextEstimateRefresh()
        }
        .onChange(of: contextEstimateFingerprint) { _ in scheduleContextEstimateRefresh() }
        .onChange(of: effectiveContext.primaryPath) { _ in
            scheduleRefresh()
            scheduleContextEstimateRefresh()
            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
        }
        .onChange(of: selectedConversationId) { _ in
            scheduleRefresh()
            scheduleContextEstimateRefresh()
            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
            clearWorktreeFeedback()
            cancelWorktreeSheetPreparation(resetSheetState: true)
        }
        .onChange(of: cliAccountRouter.currentActiveAccountByProvider) { _ in
            scheduleRefresh()
        }
        .onChange(of: wt.showWorktreeSheet) { isPresented in
            if !isPresented {
                cancelWorktreeSheetPreparation(resetSheetState: true)
            }
        }
        .onDisappear {
            ctx.usageRefreshTask?.cancel()
            ctx.usageRefreshTask = nil
            ctx.contextEstimateWorkItem?.cancel()
            ctx.contextEstimateWorkItem = nil
            wt.worktreeSheetTask?.cancel()
            wt.worktreeSheetTask = nil
            wt.worktreeActionTask?.cancel()
            wt.worktreeActionTask = nil
        }
    }

    /// Allineato a `providerUsageSection` in `UsageFooterView+UsageRows`: stessi provider con riga usage.
    private var footerProviderHasUsageRow: Bool {
        let pid = effectiveProviderId ?? ""
        return pid == "codex-cli" || pid == "claude-cli" || pid == "gemini-cli" || pid.hasSuffix("-api")
    }

    private func footerTierFlags(for tier: FooterTier) -> (
        showFooterBranchPicker: Bool,
        showProviderUsage: Bool,
        showContext: Bool,
        showTotal: Bool,
        showMessages: Bool
    ) {
        switch tier {
        case .full:
            return (true, true, true, true, true)
        case .medium:
            // Mostra usage provider (es. Codex 5h/settimana) anche con footer non “full”: prima era nascosto e restava solo il badge contesto modello (es. 1M).
            return (true, true, true, true, true)
        case .compact:
            return (true, true, true, true, false)
        case .minimal:
            // Composer stretto: sotto ~700px il tier diventa minimal; senza usage qui la riga spariva mentre il pill modello (1M) restava.
            return (false, footerProviderHasUsageRow, false, false, false)
        }
    }

    private func stableTier(for width: CGFloat, current: FooterTier) -> FooterTier {
        switch current {
        case .full:
            return width < (980 - tierHysteresis) ? .medium : .full
        case .medium:
            if width >= (980 + tierHysteresis) {
                return .full
            }
            if width < (860 - tierHysteresis) {
                return .compact
            }
            return .medium
        case .compact:
            if width >= (860 + tierHysteresis) {
                return .medium
            }
            if width < (720 - tierHysteresis) {
                return .minimal
            }
            return .compact
        case .minimal:
            return width >= (720 + tierHysteresis) ? .compact : .minimal
        }
    }

    private func updateAvailableWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        guard abs(width - availableWidth) > 1 else { return }
        availableWidth = width
        var nextTier = resolvedTier
        while true {
            let candidate = stableTier(for: width, current: nextTier)
            if candidate == nextTier {
                break
            }
            nextTier = candidate
        }
        guard nextTier != resolvedTier else { return }
        resolvedTier = nextTier
    }

    // #region agent log
    private func logUsageFooterTier(hypothesisId: String, reason: String, tierOverride: FooterTier? = nil) {
        let tier = tierOverride ?? resolvedTier
        let flags = footerTierFlags(for: tier)
        let pid = effectiveProviderId ?? ""
        let u = providerUsageStore.codexUsage
        let p5 = u?.fiveHourPct.map { String(format: "%.1f", $0) } ?? "nil"
        let pw = u?.weeklyPct.map { String(format: "%.1f", $0) } ?? "nil"
        CursorSessionDebugNDJSON.append(
            hypothesisId: hypothesisId,
            location: "UsageFooterView.swift",
            message: "footer_tier",
            data: [
                "reason": reason,
                "tier": String(describing: tier),
                "showProviderUsage": flags.showProviderUsage ? "1" : "0",
                "providerId": pid,
                "codexP5": p5,
                "codexPw": pw,
                "footerWidth": String(Int(availableWidth)),
                "footerProviderHasUsageRow": footerProviderHasUsageRow ? "1" : "0",
            ]
        )
    }
    // #endregion
}
