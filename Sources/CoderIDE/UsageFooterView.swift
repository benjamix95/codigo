import CoderEngine
import SwiftUI

struct UsageFooterView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
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

    @State private var gitRoot: String?
    @State private var gitBranch = "-"
    @State private var gitBranches: [GitBranch] = []
    @State private var gitStatus: GitStatusSummary?
    @State private var gitError: String?
    @State private var showCommitSheet = false
    @State private var includeUnstaged = true
    @State private var commitMessage = ""
    @State private var nextStep: GitCommitNextStep = .commit
    @State private var isGitBusy = false
    @State private var gitSuccess: String?
    @State private var showBranchPopover = false
    @State private var branchSearch = ""
    @State private var showCreateBranchSheet = false
    @State private var newBranchName = ""

    private let gitService = GitService()
    private let commitMessageGenerator = GitCommitMessageGenerator()

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

    private var canUseGit: Bool { gitRoot != nil }
    private var canPush: Bool { gitStatus?.hasRemote == true }
    private var canCreatePR: Bool { canPush && gitBranch != "main" && gitBranch != "master" }
    private var filteredBranches: [GitBranch] {
        let query = branchSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return gitBranches }
        return gitBranches.filter { $0.name.lowercased().contains(query) }
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
            gitSection
            Divider().frame(height: 12)
            providerUsageSection
            contextSection
            Text(totalUsageText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let gitSuccess, !gitSuccess.isEmpty {
                Text(gitSuccess)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.success)
                    .lineLimit(1)
            }
            if let gitError, !gitError.isEmpty {
                Text(gitError)
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
            refreshGit()
        }
        .onChange(of: effectiveProviderId) { _, _ in scheduleRefresh() }
        .onChange(of: effectiveContext.primaryPath) { _, _ in
            scheduleRefresh()
            refreshGit()
        }
        .onChange(of: selectedConversationId) { _, _ in
            scheduleRefresh()
            refreshGit()
        }
        .onDisappear {
            usageRefreshTask?.cancel()
            usageRefreshTask = nil
        }
        .sheet(isPresented: $showCommitSheet) {
            GitCommitSheetView(
                branch: gitBranch,
                status: gitStatus
                    ?? GitStatusSummary(
                        changedFiles: 0, added: 0, removed: 0, modified: 0, untracked: 0,
                        aheadBehind: nil, hasRemote: false),
                canCreatePR: canCreatePR,
                includeUnstaged: $includeUnstaged,
                commitMessage: $commitMessage,
                nextStep: $nextStep,
                isBusy: isGitBusy,
                errorText: gitError,
                onClose: { showCommitSheet = false },
                onContinue: { runCommitFlow() }
            )
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

    private func refreshGit() {
        gitError = nil
        gitSuccess = nil
        do {
            let root = try gitService.resolveGitRoot(from: effectiveContext.primaryPath)
            gitRoot = root
            gitBranch = try gitService.currentBranch(gitRoot: root)
            gitBranches = try gitService.listLocalBranches(gitRoot: root)
            gitStatus = try gitService.status(gitRoot: root)
        } catch {
            gitRoot = nil
            gitBranch = "-"
            gitBranches = []
            gitStatus = nil
            if let e = error as? GitServiceError {
                switch e {
                case .notGitRepository:
                    gitError = "Nessuna repository Git nel contesto attivo."
                default:
                    gitError = error.localizedDescription
                }
            } else {
                gitError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var gitSection: some View {
        HStack(spacing: 8) {
            branchMenu
            gitActionsMenu
        }
    }

    private var branchMenu: some View {
        Button {
            showBranchPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                Text(gitBranch)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .help(canUseGit ? "Switch branch" : "Nessuna repository Git nel contesto attivo")
        .popover(isPresented: $showBranchPopover, arrowEdge: .bottom) {
            branchPopoverView
        }
        .sheet(isPresented: $showCreateBranchSheet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Create and checkout new branch")
                    .font(.system(size: 15, weight: .semibold))
                TextField("Nome branch", text: $newBranchName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Annulla") {
                        showCreateBranchSheet = false
                    }
                    Button("Crea") {
                        createAndCheckoutBranch()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isGitBusy)
                }
            }
            .padding(18)
            .frame(width: 380)
        }
    }

    private var branchPopoverView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search branches", text: $branchSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("Branches")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if !canUseGit {
                Text("Nessuna repository Git")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            } else if filteredBranches.isEmpty {
                Text("Nessun branch trovato")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredBranches) { branch in
                            Button {
                                switchBranch(branch.name)
                                showBranchPopover = false
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .padding(.top, 1)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(branch.name)
                                            .font(.system(size: 34 / 2, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        if branch.isCurrent, let status = gitStatus {
                                            HStack(spacing: 5) {
                                                Text("Uncommitted: \(status.changedFiles) files")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundStyle(.secondary)
                                                Text("+\(status.added)")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(DesignSystem.Colors.success)
                                                Text("-\(status.removed)")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(DesignSystem.Colors.error)
                                            }
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if branch.isCurrent {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.primary)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(isGitBusy)
                        }
                    }
                }
                .frame(maxHeight: 290)
            }

            Divider()
                .overlay(Color.white.opacity(0.16))
                .padding(.top, 10)
                .padding(.bottom, 10)

            Button {
                newBranchName = branchSearch.trimmingCharacters(in: .whitespacesAndNewlines)
                showCreateBranchSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 28 / 2, weight: .medium))
                    Text("Create and checkout new branch...")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.93))
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canUseGit || isGitBusy)
        }
        .padding(12)
        .frame(width: 620 / 2)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .onAppear {
            branchSearch = ""
        }
    }

    private var gitActionsMenu: some View {
        Menu {
            Button("Commit") {
                commitMessage = ""
                nextStep = .commit
                showCommitSheet = true
            }
            .disabled(!canUseGit || isGitBusy)

            Button("Push") { runPushOnly() }
                .disabled(!canPush || isGitBusy)

            Button("Create PR") { runCreatePROnly() }
                .disabled(!canCreatePR || isGitBusy)

            Divider()
            Button("Refresh") { refreshGit() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "circle.grid.2x1")
                    .font(.system(size: 11, weight: .semibold))
                Text("Commit")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.8))
        }
        .menuStyle(.borderlessButton)
        .help("Git actions")
    }

    private func switchBranch(_ name: String) {
        guard let gitRoot else { return }
        isGitBusy = true
        gitError = nil
        gitSuccess = nil
        Task {
            do {
                try gitService.checkoutBranch(name: name, gitRoot: gitRoot)
                await MainActor.run {
                    gitSuccess = "Branch cambiato: \(name)"
                    refreshGit()
                    isGitBusy = false
                }
            } catch {
                await MainActor.run {
                    gitError = error.localizedDescription
                    isGitBusy = false
                }
            }
        }
    }

    private func createAndCheckoutBranch() {
        guard let gitRoot else { return }
        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isGitBusy = true
        gitError = nil
        gitSuccess = nil
        Task {
            do {
                try gitService.createAndCheckoutBranch(name: name, gitRoot: gitRoot)
                await MainActor.run {
                    gitSuccess = "Branch creato: \(name)"
                    showCreateBranchSheet = false
                    showBranchPopover = false
                    newBranchName = ""
                    refreshGit()
                    isGitBusy = false
                }
            } catch {
                await MainActor.run {
                    gitError = error.localizedDescription
                    isGitBusy = false
                }
            }
        }
    }

    private func runPushOnly() {
        guard let gitRoot else { return }
        isGitBusy = true
        gitError = nil
        gitSuccess = nil
        Task {
            do {
                try gitService.push(gitRoot: gitRoot, branch: gitBranch)
                await MainActor.run {
                    gitSuccess = "Push completato su \(gitBranch)"
                    refreshGit()
                    isGitBusy = false
                }
            } catch {
                await MainActor.run {
                    gitError = error.localizedDescription
                    isGitBusy = false
                }
            }
        }
    }

    private func runCreatePROnly() {
        guard let gitRoot else { return }
        isGitBusy = true
        gitError = nil
        gitSuccess = nil
        Task {
            do {
                let result = try gitService.createPullRequest(
                    gitRoot: gitRoot,
                    base: nil,
                    title: "chore: update \(gitBranch)",
                    body: nil
                )
                await MainActor.run {
                    gitSuccess = "PR creata: \(result.url)"
                    isGitBusy = false
                }
            } catch {
                await MainActor.run {
                    gitError = error.localizedDescription
                    isGitBusy = false
                }
            }
        }
    }

    private func runCommitFlow() {
        guard let gitRoot else { return }
        isGitBusy = true
        gitError = nil
        gitSuccess = nil

        Task {
            do {
                var message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                if message.isEmpty {
                    let diff = try gitService.diffForCommitMessage(
                        gitRoot: gitRoot, includeUnstaged: includeUnstaged)
                    if let provider = bestCommitMessageProvider() {
                        let aiContext = WorkspaceContext(
                            workspacePath: URL(fileURLWithPath: gitRoot))
                        message = try await commitMessageGenerator.generateCommitMessage(
                            diff: diff, provider: provider, context: aiContext)
                    } else {
                        message = commitMessageGenerator.fallbackMessage(
                            from: try gitService.status(gitRoot: gitRoot)
                        )
                    }
                }

                let commit = try gitService.commit(
                    gitRoot: gitRoot, message: message, includeUnstaged: includeUnstaged)

                if nextStep == .commitAndPush || nextStep == .commitAndCreatePR {
                    try gitService.push(gitRoot: gitRoot, branch: gitBranch)
                }
                var success = "Commit \(commit.shortSha): \(commit.subject)"
                if nextStep == .commitAndCreatePR {
                    let pr = try gitService.createPullRequest(
                        gitRoot: gitRoot,
                        base: nil,
                        title: commit.subject,
                        body: nil
                    )
                    success += " • PR: \(pr.url)"
                }
                await MainActor.run {
                    gitSuccess = success
                    showCommitSheet = false
                    refreshGit()
                    isGitBusy = false
                }
            } catch {
                await MainActor.run {
                    gitError = error.localizedDescription
                    isGitBusy = false
                }
            }
        }
    }

    private func bestCommitMessageProvider() -> (any LLMProvider)? {
        if let selected = providerRegistry.selectedProvider, selected.isAuthenticated() {
            return selected
        }
        if let codex = providerRegistry.provider(for: "codex-cli"), codex.isAuthenticated() {
            return codex
        }
        if let claude = providerRegistry.provider(for: "claude-cli"), claude.isAuthenticated() {
            return claude
        }
        return nil
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
