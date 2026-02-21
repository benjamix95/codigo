import CoderEngine
import SwiftUI

// MARK: - Mode Controls Bar View
/// Extracted from ChatPanelView.controlsBar and associated picker computed properties.
/// Contains the provider picker, model pickers, reasoning picker, access level menu,
/// swarm orchestrator picker, formica button, and delegate-to-agent button.

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

    // MARK: - Models

    let codexModels: [CodexModel]
    let geminiModels: [GeminiModel]

    // MARK: - Effective mode provider label

    let effectiveModeProviderLabel: String?

    // MARK: - Callbacks

    let onSyncCodexProvider: () -> Void
    let onSyncGeminiProvider: () -> Void
    let onSyncSwarmProvider: () -> Void
    let onSyncPlanProvider: () -> Void
    let onDelegateToAgent: () -> Void
    let attachedImageURLs: [URL]
    @Binding var showPlanPanel: Bool

    // MARK: - Body

    var body: some View {
        HStack(spacing: 6) {
            providerPicker

            if let modeLabel = effectiveModeProviderLabel {
                Text(modeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }

            providerSpecificControls
        }
    }

    // MARK: - Provider-Specific Controls

    @ViewBuilder
    private var providerSpecificControls: some View {
        switch providerRegistry.selectedProviderId {
        case "codex-cli":
            codexModelPicker
            codexReasoningPicker
            accessLevelMenu
            if coderMode == .agent || coderMode == .agentSwarm {
                planButton
                formicaButton
            }

        case "gemini-cli":
            geminiModelPicker
            if coderMode == .agent || coderMode == .agentSwarm {
                planButton
                formicaButton
            }

        case "claude-cli":
            if coderMode == .agent || coderMode == .agentSwarm {
                planButton
                formicaButton
            }

        case "agent-swarm":
            swarmOrchestratorPicker
            Button {
                showSwarmHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.swarmColor)
            }
            .buttonStyle(.plain)
            if coderMode == .agent || coderMode == .agentSwarm {
                planButton
                formicaButton
            }

        case "plan-mode":
            planBackendPicker
            Spacer()
            if coderMode == .plan {
                formicaButton
            }

        default:
            if [.agent, .agentSwarm, .plan].contains(coderMode) {
                Spacer()
                planButton
                formicaButton
            } else if coderMode == .ide {
                Spacer()
                delegateAdAgentButton
            } else {
                Spacer()
            }
        }
    }

    // MARK: - Provider Picker

    private var providerPicker: some View {
        Menu {
            ForEach(providerRegistry.providers, id: \.id) { provider in
                Button {
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
                Text(providerLabel).font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var providerLabel: String {
        if let id = providerRegistry.selectedProviderId,
            let p = providerRegistry.providers.first(where: { $0.id == id })
        {
            return p.displayName
        }
        return "Seleziona provider"
    }

    // MARK: - Codex Model Picker

    private var codexModelPicker: some View {
        Menu {
            Button {
                codexModelOverride = ""
                onSyncCodexProvider()
            } label: {
                HStack {
                    Text("Default (da config)")
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
                Text(codexModelLabel).font(.caption)
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
                Text(geminiModelLabel).font(.caption)
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
                Text(reasoningEffortDisplay(codexReasoningEffort)).font(.caption)
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

    private var accessLevelMenu: some View {
        let cfg = CodexConfigLoader.load()
        return Menu {
            Button {
                codexSandbox = ""
                onSyncCodexProvider()
            } label: {
                HStack {
                    Label("Default (da config)", systemImage: "doc.badge.gearshape")
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
                onSyncCodexProvider()
            } label: {
                Label("Read Only", systemImage: "lock.shield")
            }
            Button {
                codexSandbox = "workspace-write"
                onSyncCodexProvider()
            } label: {
                Label("Default", systemImage: "shield")
            }
            Button {
                codexSandbox = "danger-full-access"
                onSyncCodexProvider()
            } label: {
                Label("Full Access", systemImage: "exclamationmark.shield.fill")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: accessLevelIcon(for: effectiveSandbox)).font(.caption)
                Text(accessLevelLabel(for: effectiveSandbox)).font(.caption)
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
            Section("API") {
                orchPickerButton("openai", "OpenAI API")
                orchPickerButton("anthropic-api", "Anthropic API")
                orchPickerButton("google-api", "Google API")
                orchPickerButton("openrouter-api", "OpenRouter")
                orchPickerButton("minimax-api", "MiniMax API")
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
                    case "codex": return "Codex"
                    case "claude": return "Claude"
                    case "gemini": return "Gemini"
                    case "anthropic-api": return "Anthropic"
                    case "google-api": return "Google"
                    case "openrouter-api": return "OpenRouter"
                    case "minimax-api": return "MiniMax"
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

    // MARK: - Formica (Task Activity Panel) Button

    private var formicaButton: some View {
        Button {
            taskPanelEnabled.toggle()
        } label: {
            Image(systemName: "ant.fill")
                .font(.caption)
                .foregroundStyle(
                    taskPanelEnabled ? DesignSystem.Colors.swarmColor : .secondary
                )
        }
        .buttonStyle(.plain)
        .help("Task Activity Panel")
    }

    // MARK: - Plan Button

    private var planButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showPlanPanel.toggle()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.caption2)
                Text("Plan")
                    .font(.caption)
            }
            .foregroundStyle(
                showPlanPanel ? DesignSystem.Colors.planColor : .secondary
            )
        }
        .buttonStyle(.plain)
        .help("Toggle Plan panel (Shift+Tab)")
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
            && !chatStore.isLoading
        let agentOk = isAnyAgentProviderReady

        return Button {
            onDelegateToAgent()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12))
                Text("Delega ad Agent")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(
                (canDelegate && agentOk) ? DesignSystem.Colors.agentColor : .secondary
            )
        }
        .buttonStyle(.plain)
        .disabled(!canDelegate || !agentOk)
        .help("Passa ad Agent e invia il messaggio (modifica file, comandi)")
    }
}
