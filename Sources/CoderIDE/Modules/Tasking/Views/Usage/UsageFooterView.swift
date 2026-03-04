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

    @State var usageRefreshTask: Task<Void, Never>?
    @State var contextEstimateSnapshot: (tokens: Int, size: Int, pct: Double) = (0, 128_000, 0)
    @State var contextEstimateWorkItem: DispatchWorkItem?
    @State var contextEstimateGeneration: Int = 0
    @State var lastContextEstimateFireDate: Date = .distantPast
    @State private var availableWidth: CGFloat = 980
    @State private var resolvedTier: FooterTier = .full
    @State var showWorktreeSheet = false
    @State var availableLocalBranches: [GitBranch] = []
    @State var worktreeBranchDraft = ""
    @State var worktreeBaseBranchDraft = ""
    @State var worktreeMergeTargetDraft = ""
    @State var worktreeAutoMergeOnReturn = true
    @State var worktreeDeleteBranchAfterMerge = false
    @State var pendingWorktreeLocalRoot: String?
    @State var worktreeStatusMessage: String?
    @State var worktreeErrorMessage: String?
    @State var isWorktreeActionInFlight = false
    @State var worktreeActionTask: Task<Void, Never>?
    static let contextEstimateQueue = DispatchQueue(
        label: "com.codigo.context-estimate",
        qos: .utility
    )
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

    var body: some View {
        let tier = footerTierFlags(for: resolvedTier)

        footerTier(
            showBranch: tier.showBranch,
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
                    .onChange(of: proxy.size.width) { _, newWidth in
                        updateAvailableWidth(newWidth)
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .padding(.vertical, 2)
        .sheet(isPresented: $showWorktreeSheet) {
            worktreeCreateSheet
        }
        .onAppear {
            cliAccountRouter.bootstrapActiveSelectionsIfNeeded()
            scheduleRefresh()
            scheduleContextEstimateRefresh()
            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
        }
        .onChange(of: effectiveProviderId) { _, _ in
            scheduleRefresh()
            scheduleContextEstimateRefresh()
        }
        .onChange(of: effectiveContextModel) { _, _ in scheduleContextEstimateRefresh() }
        .onChange(of: contextScopeModeRaw) { _, _ in scheduleContextEstimateRefresh() }
        .onChange(of: contextRefreshTick) { _, _ in scheduleContextEstimateRefresh() }
        .onChange(of: openFilesStore.openFilePath) { _, _ in scheduleContextEstimateRefresh() }
        .onChange(of: contextEstimateConversationSignature) { _, _ in scheduleContextEstimateRefresh() }
        .onChange(of: effectiveContext.primaryPath) { _, _ in
            scheduleRefresh()
            scheduleContextEstimateRefresh()
            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
        }
        .onChange(of: selectedConversationId) { _, _ in
            scheduleRefresh()
            scheduleContextEstimateRefresh()
            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
            clearWorktreeFeedback()
        }
        .onChange(of: cliAccountRouter.currentActiveAccountByProvider) { _, _ in
            scheduleRefresh()
        }
        .onChange(of: showWorktreeSheet) { _, isPresented in
            if isPresented {
                prepareWorktreeSheetState()
            }
        }
        .onDisappear {
            usageRefreshTask?.cancel()
            usageRefreshTask = nil
            contextEstimateWorkItem?.cancel()
            contextEstimateWorkItem = nil
            worktreeActionTask?.cancel()
            worktreeActionTask = nil
        }
    }

    private func footerTierFlags(for tier: FooterTier) -> (
        showBranch: Bool,
        showProviderUsage: Bool,
        showContext: Bool,
        showTotal: Bool,
        showMessages: Bool
    ) {
        switch tier {
        case .full:
            return (true, true, true, true, true)
        case .medium:
            return (true, false, true, true, true)
        case .compact:
            return (false, false, true, true, false)
        case .minimal:
            return (false, false, false, false, false)
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
}
