import SwiftUI
import CoderEngine

struct UsageFooterView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @Binding var selectedConversationId: UUID?
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
        if id == "agent-swarm" { return swarmWorkerBackend == "claude" ? "claude-cli" : "codex-cli" }
        return id
    }

    private var contextEstimate: (tokens: Int, size: Int, pct: Double) {
        guard let conv = chatStore.conversation(for: selectedConversationId) else {
            return (0, 128_000, 0)
        }
        let ctx = effectiveContext.toWorkspaceContext(openFiles: openFilesStore.openFilesForContext(), activeSelection: nil, activeFilePath: openFilesStore.openFilePath)
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

    var body: some View {
        HStack(spacing: 12) {
            providerUsageSection
            contextSection
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .onAppear { scheduleRefresh() }
        .onChange(of: effectiveProviderId) { _, _ in scheduleRefresh() }
        .onChange(of: effectiveContext.primaryPath) { _, _ in scheduleRefresh() }
        .onDisappear {
            usageRefreshTask?.cancel()
            usageRefreshTask = nil
        }
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
                let path = codexPath.isEmpty ? (PathFinder.find(executable: "codex") ?? "") : codexPath
                await providerUsageStore.fetchCodexUsage(codexPath: path, workingDirectory: wd)
            } else if pid == "claude-cli" {
                let path = claudePath.isEmpty ? (PathFinder.find(executable: "claude") ?? "/usr/local/bin/claude") : claudePath
                await providerUsageStore.fetchClaudeUsage(claudePath: path, workingDirectory: wd)
            } else if pid == "gemini-cli" {
                let path = geminiCliPath.isEmpty ? (PathFinder.find(executable: "gemini") ?? "/opt/homebrew/bin/gemini") : geminiCliPath
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
        HStack(spacing: 8) {
            if providerUsageStore.isRefreshing {
                ProgressView().controlSize(.mini)
            }
            if let u = providerUsageStore.codexUsage {
                if let p5 = u.fiveHourPct {
                    Text("5 h")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(Int(p5))%")
                        .font(.system(size: 10, weight: .medium))
                    if let r = u.resetFiveH { Text(r).font(.system(size: 10)).foregroundStyle(.tertiary) }
                }
                if let pw = u.weeklyPct {
                    Text("·")
                    Text("Settimana")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(Int(pw))%")
                        .font(.system(size: 10, weight: .medium))
                    if let r = u.resetWeekly { Text(r).font(.system(size: 10)).foregroundStyle(.tertiary) }
                }
            } else {
                Text(providerUsageStore.codexUsageMessage ?? "—")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var claudeUsageRow: some View {
        HStack(spacing: 8) {
            if providerUsageStore.isRefreshing {
                ProgressView().controlSize(.mini)
            }
            if let u = providerUsageStore.claudeUsage {
                if let c = u.sessionCost {
                    Text(c)
                        .font(.system(size: 10, weight: .medium))
                }
                if let i = u.inputTokens {
                    Text("in \(i)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if let o = u.outputTokens {
                    Text("out \(o)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(providerUsageStore.claudeUsageMessage ?? "—")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var geminiUsageRow: some View {
        HStack(spacing: 8) {
            if providerUsageStore.isRefreshing {
                ProgressView().controlSize(.mini)
            }
            if let u = providerUsageStore.geminiUsage {
                if let total = u.totalTokens {
                    Text("\(total) tok")
                        .font(.system(size: 10, weight: .medium))
                } else {
                    if let i = u.inputTokens {
                        Text("in \(i)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if let o = u.outputTokens {
                        Text("out \(o)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
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
