import CoderEngine
import SwiftUI

struct UsageFooterView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var gitPanelStore: GitPanelStore
    @Binding var selectedConversationId: UUID?
    @AppStorage("context_scope_mode") private var contextScopeModeRaw = "auto"
    @AppStorage("codex_path") private var codexPath = ""
    @AppStorage("claude_path") private var claudePath = ""
    @AppStorage("gemini_cli_path") private var geminiCliPath = ""
    let effectiveContext: EffectiveContext
    let planModeBackend: String
    let swarmWorkerBackend: String
    let openaiModel: String
    let claudeModel: String
    @State private var usageRefreshTask: Task<Void, Never>?

    private var effectiveProviderId: String? {
        let id = providerRegistry.selectedProviderId ?? ""
        if id == "plan-mode" { return planModeBackend == "claude" ? "claude-cli" : "codex-cli" }
        if id == "agent-swarm" {
            switch swarmWorkerBackend {
            case "codex": return "codex-cli"
            case "claude": return "claude-cli"
            case "gemini": return "gemini-cli"
            case "openai", "openai-api": return "openai-api"
            case "anthropic-api": return "anthropic-api"
            case "google-api": return "google-api"
            case "openrouter-api": return "openrouter-api"
            case "minimax-api": return "minimax-api"
            default: return swarmWorkerBackend
            }
        }
        return id
    }

    private var contextEstimate: (tokens: Int, size: Int, pct: Double) {
        guard let conv = chatStore.conversation(for: selectedConversationId) else {
            return (0, 128_000, 0)
        }
        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto
        )
        let ctxPrompt = ctx.contextPrompt()
        let model = effectiveProviderId?.contains("claude") == true ? claudeModel : openaiModel
        let size = ContextEstimator.contextSize(for: effectiveProviderId, model: model)
        let (tokens, ctxSize, pct) = ContextEstimator.estimate(
            messages: conv.messages,
            contextPrompt: ctxPrompt,
            modelContextSize: size
        )
        return (tokens, ctxSize, pct)
    }

    private var totalUsageText: String {
        var total = providerUsageStore.apiTokensIn + providerUsageStore.apiTokensOut
        if let c = providerUsageStore.claudeUsage {
            total += (c.inputTokens ?? 0) + (c.outputTokens ?? 0)
        }
        if let g = providerUsageStore.geminiUsage {
            if let t = g.totalTokens {
                total += t
            } else {
                total += (g.inputTokens ?? 0) + (g.outputTokens ?? 0)
            }
        }
        if total > 0 {
            return "Totale \(total.formatted()) tok"
        }
        if providerUsageStore.apiEstimatedCost > 0 {
            return String(format: "Totale $%.3f", providerUsageStore.apiEstimatedCost)
        }
        return "Totale —"
    }

    var body: some View {
        HStack(spacing: 10) {
            gitButton
            Divider().frame(height: 12)
            providerUsageSection
            contextSection
            Text(totalUsageText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let success = gitPanelStore.successMessage, !success.isEmpty {
                Text(success)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.success)
                    .lineLimit(1)
            }
            if let err = gitPanelStore.error, !err.isEmpty {
                Text(err)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.error)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .onAppear {
            scheduleRefresh()
            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
        }
        .onChange(of: effectiveProviderId) { _, _ in scheduleRefresh() }
        .onChange(of: effectiveContext.primaryPath) { _, _ in
            scheduleRefresh()
            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
        }
        .onChange(of: selectedConversationId) { _, _ in
            scheduleRefresh()
            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
        }
        .onDisappear {
            usageRefreshTask?.cancel()
            usageRefreshTask = nil
        }
    }

    // MARK: - Git Button
    private var gitButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                gitPanelStore.isOpen.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(gitPanelStore.isOpen ? DesignSystem.Colors.agentColor : .primary)
                Text(gitPanelStore.currentBranch)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if !gitPanelStore.changedFiles.isEmpty {
                    Text("\(gitPanelStore.changedFiles.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DesignSystem.Colors.agentColor, in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (gitPanelStore.isOpen ? DesignSystem.Colors.agentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.55)),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    gitPanelStore.isOpen ? DesignSystem.Colors.agentColor.opacity(0.3) : DesignSystem.Colors.borderSubtle,
                    lineWidth: 0.8
                )
            )
        }
        .buttonStyle(.plain)
        .help(gitPanelStore.gitRoot == nil ? "Nessuna repository Git" : "Apri pannello Git")
    }

    private func scheduleRefresh() {
        usageRefreshTask?.cancel()
        usageRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            refreshUsage()
        }
    }

    private func refreshUsage() {
        let pid = effectiveProviderId ?? ""
        let wd = effectiveContext.primaryPath
        Task {
            if pid == "codex-cli" {
                let path =
                    codexPath.isEmpty ? (PathFinder.find(executable: "codex") ?? "") : codexPath
                await providerUsageStore.fetchCodexUsage(codexPath: path, workingDirectory: wd)
            } else if pid == "claude-cli" {
                let path =
                    claudePath.isEmpty
                    ? (PathFinder.find(executable: "claude") ?? "/usr/local/bin/claude")
                    : claudePath
                await providerUsageStore.fetchClaudeUsage(claudePath: path, workingDirectory: wd)
            } else if pid == "gemini-cli" {
                let path =
                    geminiCliPath.isEmpty
                    ? (GeminiDetector.findGeminiPath(customPath: nil) ?? "/opt/homebrew/bin/gemini")
                    : geminiCliPath
                await providerUsageStore.fetchGeminiUsage(geminiPath: path, workingDirectory: wd)
            }
        }
    }


    @ViewBuilder
    private var providerUsageSection: some View {
        let pid = effectiveProviderId ?? ""
        if pid == "codex-cli" {
            codexUsageRow
        } else if pid == "claude-cli" {
            claudeUsageRow
        } else if pid == "gemini-cli" {
            geminiUsageRow
        } else if pid.hasSuffix("-api") {
            apiUsageRow
        } else {
            EmptyView()
        }
    }

    private var codexUsageRow: some View {
        HStack(spacing: 6) {
            if providerUsageStore.isRefreshing {
                ProgressView().controlSize(.mini)
            }

            // Rate limit / warning icon
            if providerUsageStore.isCodexRateLimited {
                Image(systemName: "octagon.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.red)
                    .help(providerUsageStore.codexRateLimitMessage ?? "Rate limit raggiunto")
            } else if providerUsageStore.isCodexUsageHigh {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help("Usage elevato — rallenta per evitare il rate limit")
            }

            if let u = providerUsageStore.codexUsage {
                if let p5 = u.fiveHourPct {
                    Text("5 h")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(Int(p5))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(p5 >= 100 ? .red : (p5 >= 80 ? .orange : .primary))
                    if let r = u.resetFiveH {
                        Text(r).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                if let pw = u.weeklyPct {
                    Text("·")
                    Text("Settimana")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(Int(pw))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(pw >= 100 ? .red : (pw >= 80 ? .orange : .primary))
                    if let r = u.resetWeekly {
                        Text(r).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text(providerUsageStore.codexUsageMessage ?? "—")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .help(
            providerUsageStore.isCodexRateLimited
                ? (providerUsageStore.codexRateLimitMessage ?? "Rate limit raggiunto")
                : "Codex CLI usage"
        )
    }

    private var claudeUsageRow: some View {
        HStack(spacing: 6) {
            if providerUsageStore.isRefreshing {
                ProgressView().controlSize(.mini)
            }
            if let u = providerUsageStore.claudeUsage {
                if let c = u.sessionCost {
                    Text(c)
                        .font(.system(size: 10, weight: .medium))
                }
                if let i = u.inputTokens, i > 0 {
                    Text("in \(i.formatted())")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if let o = u.outputTokens, o > 0 {
                    Text("out \(o.formatted())")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if let cr = u.cacheReadTokens, cr > 0 {
                    Text("cache \(cr.formatted())")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                if let dur = u.totalDuration, !dur.isEmpty {
                    Text("· \(dur)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                // Show something even when all values are zero
                if u.sessionCost == nil || u.sessionCost == "$0.0000",
                    (u.inputTokens ?? 0) == 0, (u.outputTokens ?? 0) == 0
                {
                    Text("Sessione vuota")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(providerUsageStore.claudeUsageMessage ?? "—")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .help("Claude Code — costo e token della sessione corrente")
    }

    private var geminiUsageRow: some View {
        HStack(spacing: 6) {
            if providerUsageStore.isRefreshing {
                ProgressView().controlSize(.mini)
            }
            if let u = providerUsageStore.geminiUsage {
                if let total = u.totalTokens, total > 0 {
                    Text("\(total.formatted()) tok")
                        .font(.system(size: 10, weight: .medium))
                } else if let i = u.inputTokens, i > 0 {
                    Text("in \(i.formatted())")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let o = u.outputTokens, o > 0 {
                        Text("out \(o.formatted())")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else if let c = u.sessionCost, !c.isEmpty {
                    Text(c)
                        .font(.system(size: 10, weight: .medium))
                }
                if let note = u.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            } else {
                Text(providerUsageStore.geminiUsageMessage ?? "—")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .help("Gemini CLI — usage dalla sessione locale")
    }

    private var apiUsageRow: some View {
        HStack(spacing: 8) {
            Text("\(providerUsageStore.apiTokensIn + providerUsageStore.apiTokensOut) tok")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if providerUsageStore.apiEstimatedCost > 0 {
                Text(String(format: "$%.3f", providerUsageStore.apiEstimatedCost))
                    .font(.system(size: 10, weight: .medium))
            }
        }
    }

    private var contextSection: some View {
        let (tokens, size, pct) = contextEstimate
        return HStack(spacing: 6) {
            CircularProgressView(progress: pct, lineWidth: 1.5, size: 14)
            Text("\(tokens.formatted()) / \((size / 1000).formatted())k")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .help("Contesto finestra: \(Int(pct * 100))% utilizzato")
    }
}
