import CoderEngine
import SwiftUI

// MARK: - Mode Controls Bar View
/// Bottom controls bar: provider picker, model pickers, reasoning picker, access level menu,
/// and icon-only buttons for Code Review & Swarm at the far right.

struct ModeControlsBarView: View {
    // MARK: - Provider Registry

    @ObservedObject var providerRegistry: ProviderRegistry
    @ObservedObject var chatStore: ChatStore

    // MARK: - Mode & State

    let coderMode: CoderMode
    let conversationId: UUID?
    let isAnyAgentProviderReady: Bool

    // MARK: - Bindings for AppStorage values

    @Binding var codexModelOverride: String
    @Binding var codexReasoningEffort: String
    @Binding var codexSandbox: String
    @Binding var geminiModelOverride: String
    @Binding var swarmOrchestrator: String
    @Binding var taskPanelEnabled: Bool
    @Binding var showSwarmHelp: Bool
    @Binding var inputText: String
    @Binding var planModeBackend: String
    @Binding var swarmWorkerBackend: String
    @Binding var openaiModel: String
    @Binding var claudeModel: String
    @Binding var openrouterModel: String

    // MARK: - Models

    let codexModels: [CodexModel]
    let geminiModels: [GeminiModel]

    // MARK: - Callbacks

    let onSyncCodexProvider: () -> Void
    let onSyncClaudeProvider: () -> Void
    let onSyncGeminiProvider: () -> Void
    let onSyncSwarmProvider: () -> Void
    let onSyncPlanProvider: () -> Void
    let onSyncOpenRouterProvider: () -> Void
    let onSyncToolRuntimePolicy: () -> Void
    let onUserSelectedProvider: () -> Void
    let onDelegateToAgent: () -> Void
    let attachedImageURLs: [URL]
    @Binding var planToggleEnabled: Bool
    @Binding var debugToggleEnabled: Bool
    @Binding var swarmToggleEnabled: Bool
    @Binding var codeReviewToggleEnabled: Bool

    // MARK: - Collapse Tiers

    private enum ControlsTier {
        case full, medium, compact, minimal
    }

    // MARK: - Body

    var body: some View {
        ViewThatFits(in: .horizontal) {
            controlsHStack(tier: .full)
            controlsHStack(tier: .medium)
            controlsHStack(tier: .compact)
            controlsHStack(tier: .minimal)
        }
    }

    // MARK: - Tier HStack Builder

    @ViewBuilder
    private func controlsHStack(tier: ControlsTier) -> some View {
        let pid = providerRegistry.selectedProviderId ?? ""
        HStack(spacing: 6) {
            // Provider picker: full=icon+name, medium=icon-only, compact/minimal=hidden
            if tier == .full {
                providerPickerView(showLabel: true)
            } else if tier == .medium {
                providerPickerView(showLabel: false)
            }

            // Model picker (always shown)
            modelPickerForProvider(pid)

            // Reasoning picker (codex only, hidden at minimal)
            if pid == "codex-cli" && tier != .minimal {
                codexReasoningPicker
            }

            // Access level menu: full/medium=icon+label, compact=icon-only, minimal=hidden
            if hasAccessLevel(pid) {
                if tier == .full || tier == .medium {
                    accessLevelMenuView(showLabel: true)
                } else if tier == .compact {
                    accessLevelMenuView(showLabel: false)
                }
            }

            if coderMode == .ide && tier == .full {
                delegateAdAgentButton
            }

            Spacer(minLength: 0)

            planIconButton
            debugIconButton
            codeReviewIconButton
            swarmIconButton
        }
    }

    private func hasAccessLevel(_ pid: String) -> Bool {
        ["codex-cli", "gemini-cli", "claude-cli", "openrouter-api",
         "openai-api", "anthropic-api", "google-api", "minimax-api", "grok-api"].contains(pid)
    }

    @ViewBuilder
    private func modelPickerForProvider(_ pid: String) -> some View {
        switch pid {
        case "codex-cli": codexModelPicker
        case "gemini-cli": geminiModelPicker
        case "claude-cli": claudeModelPicker
        case "openrouter-api": openRouterModelPicker
        default: EmptyView()
        }
    }

    // MARK: - Provider Picker

    private func providerPickerView(showLabel: Bool) -> some View {
        let realProviders = providerRegistry.providers
            .filter { ProviderSupport.isUserSelectableRealProvider(id: $0.id) }
        return Menu {
            ForEach(realProviders, id: \.id) { provider in
                Button {
                    onUserSelectedProvider()
                    providerRegistry.selectedProviderId = provider.id
                    chatStore.updatePreferredProvider(
                        conversationId: conversationId, providerId: provider.id)
                } label: {
                    HStack {
                        Text(provider.displayName)
                        if providerRegistry.selectedProviderId == provider.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu").font(.caption2)
                if showLabel {
                    Text(providerLabel).font(.caption).lineLimit(1)
                }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var providerLabel: String {
        if let id = providerRegistry.selectedProviderId,
            ProviderSupport.isUserSelectableRealProvider(id: id),
            let p = providerRegistry.providers.first(where: { $0.id == id })
        {
            return p.displayName
        }
        if let fallback = providerRegistry.providers.first(where: {
            ProviderSupport.isUserSelectableRealProvider(id: $0.id)
        }) {
            return fallback.displayName
        }
        return "No provider"
    }

    // MARK: - Codex Model Picker

    private var codexModelPicker: some View {
        Menu {
            Button {
                codexModelOverride = ""
                onSyncCodexProvider()
            } label: {
                HStack {
                    Text("Default (from config)")
                    if codexModelOverride.isEmpty { Image(systemName: "checkmark") }
                }
            }
            if !codexModels.isEmpty {
                Divider()
                ForEach(codexModels, id: \.slug) { m in
                    Button {
                        codexModelOverride = m.slug
                        onSyncCodexProvider()
                    } label: {
                        HStack {
                            Text(m.displayName)
                            if codexModelOverride == m.slug { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(codexModelLabel).font(.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var codexModelLabel: String {
        codexModelOverride.isEmpty
            ? "Default"
            : (codexModels.first(where: { $0.slug == codexModelOverride })?.displayName
                ?? codexModelOverride)
    }

    // MARK: - Claude Model Picker

    private var claudeModelPicker: some View {
        Menu {
            ForEach(ClaudeModelsCache.loadModels(), id: \.slug) { model in
                Button {
                    claudeModel = model.slug
                    onSyncClaudeProvider()
                } label: {
                    HStack {
                        Text(model.displayName)
                        if claudeModel == model.slug { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(ClaudeModelsCache.displayName(for: claudeModel)).font(.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Gemini Model Picker

    private var geminiModelPicker: some View {
        Menu {
            Button {
                geminiModelOverride = ""
                onSyncGeminiProvider()
            } label: {
                HStack {
                    Text("Default (auto)")
                    if geminiModelOverride.isEmpty { Image(systemName: "checkmark") }
                }
            }
            if !geminiModels.isEmpty {
                Divider()
                ForEach(geminiModels, id: \.slug) { m in
                    Button {
                        geminiModelOverride = m.slug
                        onSyncGeminiProvider()
                    } label: {
                        HStack {
                            Text(m.displayName)
                            if geminiModelOverride == m.slug { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(geminiModelLabel).font(.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var geminiModelLabel: String {
        geminiModelOverride.isEmpty
            ? "Default"
            : (geminiModels.first(where: { $0.slug == geminiModelOverride })?.displayName
                ?? geminiModelOverride)
    }

    // MARK: - OpenRouter Model Picker

    private var openRouterModelPicker: some View {
        Menu {
            if !openRouterPopularModels.isEmpty {
                Section("Popular") {
                    ForEach(openRouterPopularModels, id: \.self) { model in
                        Button {
                            openrouterModel = model
                            onSyncOpenRouterProvider()
                        } label: {
                            HStack {
                                Text(model)
                                if openrouterModel == model { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
            if !openRouterFreeModels.isEmpty {
                Section("Free") {
                    ForEach(openRouterFreeModels, id: \.self) { model in
                        Button {
                            openrouterModel = model
                            onSyncOpenRouterProvider()
                        } label: {
                            HStack {
                                Text(model)
                                Text("FREE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.green)
                                if openrouterModel == model { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(openRouterModelLabel).font(.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var openRouterModelLabel: String {
        let trimmed = openrouterModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "OpenRouter Model"
        }
        let display = trimmed.replacingOccurrences(of: ":free", with: "")
        if trimmed.hasSuffix(":free") {
            return "\(display) · FREE"
        }
        return display
    }

    // MARK: - Codex Reasoning Picker

    private var codexReasoningPicker: some View {
        Menu {
            ForEach(["low", "medium", "high", "xhigh"], id: \.self) { e in
                Button {
                    codexReasoningEffort = e
                    onSyncCodexProvider()
                } label: {
                    HStack {
                        Text(reasoningEffortDisplay(e))
                        if codexReasoningEffort == e { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(reasoningEffortDisplay(codexReasoningEffort)).font(.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func reasoningEffortDisplay(_ e: String) -> String {
        switch e.lowercased() {
        case "low": return "Low"
        case "medium": return "Medium"
        case "high": return "High"
        case "xhigh": return "XHigh"
        default: return e
        }
    }

    // MARK: - Access Level Menu

    private var effectiveSandbox: String {
        codexSandbox.isEmpty
            ? (CodexConfigLoader.load().sandboxMode ?? "workspace-write") : codexSandbox
    }

    private func accessLevelMenuView(showLabel: Bool) -> some View {
        let cfg = CodexConfigLoader.load()
        return Menu {
            Button {
                codexSandbox = ""
                onSyncToolRuntimePolicy()
            } label: {
                HStack {
                    Label("Default (from config)", systemImage: "doc.badge.gearshape")
                    if codexSandbox.isEmpty { Image(systemName: "checkmark") }
                }
            }
            if cfg.sandboxMode != nil {
                Text("Config: \(accessLevelLabel(for: cfg.sandboxMode ?? ""))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button {
                codexSandbox = "read-only"
                onSyncToolRuntimePolicy()
            } label: {
                Label("Read Only", systemImage: "lock.shield")
            }
            Button {
                codexSandbox = "workspace-write"
                onSyncToolRuntimePolicy()
            } label: {
                Label("Default", systemImage: "shield")
            }
            Button {
                codexSandbox = "danger-full-access"
                onSyncToolRuntimePolicy()
            } label: {
                Label("Full Access", systemImage: "exclamationmark.shield.fill")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: accessLevelIcon(for: effectiveSandbox)).font(.caption)
                if showLabel {
                    Text(accessLevelLabel(for: effectiveSandbox)).font(.caption).lineLimit(1)
                }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(
                effectiveSandbox == "danger-full-access"
                    ? DesignSystem.Colors.error : .secondary
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func accessLevelIcon(for s: String) -> String {
        switch s {
        case "read-only": return "lock.shield"
        case "danger-full-access": return "exclamationmark.shield.fill"
        default: return "shield"
        }
    }

    private func accessLevelLabel(for s: String) -> String {
        switch s {
        case "read-only": return "Read Only"
        case "danger-full-access": return "Full Access"
        default: return "Default"
        }
    }

    // MARK: - Swarm Orchestrator Picker

    private func orchPickerButton(_ id: String, _ label: String) -> some View {
        Button {
            swarmOrchestrator = id
            onSyncSwarmProvider()
        } label: {
            HStack {
                Text(label)
                if swarmOrchestrator == id { Image(systemName: "checkmark") }
            }
        }
    }

    private var swarmOrchestratorPicker: some View {
        Menu {
            orchPickerButton("auto", "Auto (same as Agent)")
            Divider()
            Section("API") {
                orchPickerButton("openai", "OpenAI API")
                orchPickerButton("anthropic-api", "Anthropic API")
                orchPickerButton("google-api", "Google API")
                orchPickerButton("openrouter-api", "OpenRouter")
                orchPickerButton("minimax-api", "MiniMax API")
                orchPickerButton("grok-api", "Grok API")
            }
            Section("CLI") {
                orchPickerButton("codex", "Codex CLI")
                orchPickerButton("claude", "Claude Code")
                orchPickerButton("gemini", "Gemini CLI")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "ant.fill").font(.caption2)
                let orchLabel: String = {
                    switch swarmOrchestrator {
                    case "auto": return "Auto"
                    case "codex": return "Codex"
                    case "claude": return "Claude"
                    case "gemini": return "Gemini"
                    case "anthropic-api": return "Anthropic"
                    case "google-api": return "Google"
                    case "openrouter-api": return "OpenRouter"
                    case "minimax-api": return "MiniMax"
                    case "grok-api": return "Grok"
                    default: return "OpenAI"
                    }
                }()
                Text("Orch: \(orchLabel)").font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Plan Backend Picker

    private var planBackendPicker: some View {
        Menu {
            Button {
                planModeBackend = "codex"
                onSyncPlanProvider()
            } label: {
                HStack {
                    Text("Codex CLI")
                    if planModeBackend == "codex" { Image(systemName: "checkmark") }
                }
            }
            Button {
                planModeBackend = "claude"
                onSyncPlanProvider()
            } label: {
                HStack {
                    Text("Claude CLI")
                    if planModeBackend == "claude" { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle").font(.caption2)
                Text("Plan: \(planModeBackend == "claude" ? "Claude" : "Codex")").font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Code Review Icon Button (icon-only, far right)

    private var planIconButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                planToggleEnabled.toggle()
            }
        } label: {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    planToggleEnabled
                        ? DesignSystem.Colors.planColor : .secondary
                )
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            planToggleEnabled
                                ? DesignSystem.Colors.planColor.opacity(0.14)
                                : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Toggle Plan panel")
    }

    private var debugIconButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                debugToggleEnabled.toggle()
            }
        } label: {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    debugToggleEnabled
                        ? DesignSystem.Colors.debugColor : .secondary
                )
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            debugToggleEnabled
                                ? DesignSystem.Colors.debugColor.opacity(0.14)
                                : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Toggle Debug panel")
    }

    private var codeReviewIconButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                codeReviewToggleEnabled.toggle()
            }
        } label: {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    codeReviewToggleEnabled
                        ? DesignSystem.Colors.reviewColor : .secondary
                )
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            codeReviewToggleEnabled
                                ? DesignSystem.Colors.reviewColor.opacity(0.14)
                                : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Toggle Code Review panel")
    }

    // MARK: - Swarm Icon Button (icon-only, far right)

    private var swarmIconButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                swarmToggleEnabled.toggle()
            }
        } label: {
            Image(systemName: "ant.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    swarmToggleEnabled
                        ? DesignSystem.Colors.swarmColor : .secondary
                )
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            swarmToggleEnabled
                                ? DesignSystem.Colors.swarmColor.opacity(0.14)
                                : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Toggle Swarm panel")
    }

    // MARK: - Delegate to Agent Button

    private var delegateAdAgentButton: some View {
        let msg = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastUser =
            chatStore.conversation(for: conversationId)?
            .messages.last(where: { $0.role == .user })?
            .content ?? ""
        let canDelegate =
            (!msg.isEmpty || !lastUser.isEmpty || !attachedImageURLs.isEmpty)
            && !chatStore.isTaskActive(for: conversationId)
        let agentOk = isAnyAgentProviderReady

        return Button {
            onDelegateToAgent()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12))
                Text("Delegate to Agent")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(
                (canDelegate && agentOk) ? DesignSystem.Colors.agentColor : .secondary
            )
        }
        .buttonStyle(.plain)
        .disabled(!canDelegate || !agentOk)
        .help("Switch to Agent and send message (edit files, run commands)")
    }
}
