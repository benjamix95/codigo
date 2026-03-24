import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func handleComposerSend() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("\n"),
              trimmed.lowercased() == "/fast",
              providerRegistry.selectedProviderId == "codex-cli"
        else {
            sendMessage()
            return
        }

        handleComposerQuickCommand("/fast", runImmediately: false)
    }

    internal func handleComposerQuickCommand(_ text: String, runImmediately: Bool) {
        let slash = text
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        guard slash == "/fast", providerRegistry.selectedProviderId == "codex-cli" else {
            inputText = applyComposerCodeReviewModesIfNeeded(to: text)
            isInputFocused = true
            if runImmediately {
                sendMessage()
            }
            return
        }

        let nextValue = !CodexFastModeStore.currentValue()
        CodexFastModeStore.persist(nextValue)
        syncCodexProvider()
        inputText = ""
        isInputFocused = true
    }

    internal var providerNotReadyMessage: String {
        guard let id = providerRegistry.selectedProviderId else {
            return "No provider selected. Go to Settings to configure."
        }
        if providerSettings.multiCLIAccountEnabled,
           let kind = CLIProviderKind.fromProviderId(id),
           case .allExhausted(let reason) = cliAccountRouter.currentAvailability(provider: kind) {
            return "\(kind.displayName) account unavailable (\(reason)). Configure accounts in Settings."
        }
        switch id {
        case "openai-api": return "OpenAI API Key missing. Configure it in Settings."
        case "anthropic-api": return "Anthropic API Key missing. Configure it in Settings."
        case "google-api": return "Google Gemini API Key missing. Configure it in Settings."
        case "codex-cli":
            return "Codex CLI not connected. Configure it in Settings → Codex CLI."
        case "claude-cli":
            return "Claude Code not found. Configure it in Settings → Claude Code."
        case "gemini-cli":
            return "Gemini CLI not found/not authenticated. Configure it in Settings."
        case "openrouter-api": return "OpenRouter API Key missing. Configure it in Settings."
        case "minimax-api": return "MiniMax API Key missing. Configure it in Settings."
        case "grok-api": return "Grok API Key missing. Configure it in Settings."
        default:
            return "Provider \"\(id)\" not authenticated. Go to Settings to configure."
        }
    }


    internal var inputHint: String {
        switch coderMode {
        case .agent: return "Agent can modify files and run commands"
        case .codeReviewMultiSwarm:
            return
                "Code Review: analysis → dynamic worker tasks → parallel fix → test → re-review loop"
        case .debug: return "Debug mode: MCP-first phase flow + structured debug tools"
        case .plan: return "Plan with options + custom response"
        case .ide: return "Ask about code or describe an edit"
        case .browser: return "Browser mode: agent can navigate, test, and capture screenshots"
        case .mcpServer: return "Send to configured MCP server"
        }
    }

    internal var composerQuickCommandPresets: [ChatComposerView.QuickCommandPreset] {
        guard coderMode == .codeReviewMultiSwarm else { return [] }
        let defaults = CodeReviewQuickCommands.defaults.map { cmd in
            ChatComposerView.QuickCommandPreset(
                id: cmd.id,
                slash: cmd.slash,
                label: cmd.label,
                prompt: cmd.prompt,
                icon: nil
            )
        }
        return defaults + customCodeReviewQuickPresets
    }

    internal var composerSlashCommandPresets: [ChatComposerView.QuickCommandPreset] {
        guard providerRegistry.selectedProviderId == "codex-cli" else { return [] }
        let isFastModeEnabled = CodexFastModeStore.currentValue()
        return [
            .init(
                id: "codex-fast-toggle",
                slash: "/fast",
                label: isFastModeEnabled
                    ? "Turn off Fast mode and return to standard inference speed"
                    : "Turn on Fast mode for faster inference across Codex runs",
                prompt: "",
                icon: nil
            )
        ]
    }

    internal var customCodeReviewQuickPresets: [ChatComposerView.QuickCommandPreset] {
        struct CustomPreset: Decodable {
            let slash: String
            let label: String
            let prompt: String
        }
        let raw = swarmReviewSettings.codeReviewQuickCommandsCustomJSON.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return [] }
        guard let decoded = try? JSONDecoder().decode([CustomPreset].self, from: data) else {
            return []
        }
        return decoded.enumerated().compactMap { idx, item in
            let slash = item.slash.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let prompt = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard slash.hasPrefix("/"), !label.isEmpty, !prompt.isEmpty else { return nil }
            return .init(
                id: "review-custom-\(idx)-\(slash)",
                slash: slash,
                label: label,
                prompt: prompt,
                icon: nil
            )
        }
    }

    internal var effectiveSandbox: String {
        providerSettings.codexSandbox.isEmpty
            ? (CodexConfigLoader.load().sandboxMode ?? "workspace-write") : providerSettings.codexSandbox
    }

    internal func selectMode(_ mode: CoderMode) {
        userModeOverrideUntilConversationChange = true
        // One thread per context: conversation does not change on tab switch.
        // selectedConversationId stays, only coderMode and provider are updated.
        let currentConv = chatStore.conversation(for: selectedConversationId)
        switch mode {
        case .ide:
            if let preferred = currentConv?.preferredProviderId,
                ProviderSupport.isIDEProvider(id: preferred),
                providerRegistry.provider(for: preferred) != nil
            {
                providerRegistry.selectedProviderId = preferred
            } else {
                providerRegistry.selectedProviderId = ProviderSupport.preferredIDEProvider(
                    in: providerRegistry)
            }
        case .agent:
            applyStrictAgentModeProviderSelection(preferredProviderId: currentConv?.preferredProviderId)
        case .codeReviewMultiSwarm:
            applyStrictAgentModeProviderSelection(preferredProviderId: currentConv?.preferredProviderId)
        case .debug:
            applyStrictAgentModeProviderSelection(preferredProviderId: currentConv?.preferredProviderId)
            debugToggleEnabled = true
        case .plan:
            applyStrictAgentModeProviderSelection(preferredProviderId: currentConv?.preferredProviderId)
            // Only reset plan state when no active flow is in progress
            switch planFlowPhase {
            case .analyzing, .questioning, .generating, .building, .proposalReady, .readyToBuild:
                break
            case .idle:
                planningState = .idle
            }
            planToggleEnabled = true
        case .browser:
            applyStrictAgentModeProviderSelection(preferredProviderId: currentConv?.preferredProviderId)
            showBrowserPanel = true
        case .mcpServer: providerRegistry.selectedProviderId = "claude-cli"
        }
        coderMode = mode
        // When switching away from plan mode, only preserve plan state for
        // actively in-flight phases (questioning/generating) so switching back
        // doesn't lose work. Reset all other phases to avoid orphaned state
        // since planToggleEnabled is disabled below.
        if mode != .plan {
            switch planFlowPhase {
            case .analyzing, .questioning, .generating, .building:
                break
            case .idle:
                break
            case .proposalReady, .readyToBuild:
                planFlowPhase = .idle
                planningState = .idle
                clearPlanStreamingState()
            }
            // Keep toggle ON if an active plan session exists (e.g. during build phase)
            let hasActivePlanSession: Bool = {
                switch planFlowPhase {
                case .analyzing, .questioning, .generating, .building, .readyToBuild:
                    return true
                case .idle, .proposalReady:
                    return false
                }
            }()
            if !hasActivePlanSession && activeBuildPlanConversationId == nil {
                planToggleEnabled = false
            }
        }
        if mode != .debug && !debugStore.phase.isActive {
            debugToggleEnabled = false
        }
        if mode != .browser {
            showBrowserPanel = false
        }
        chatStore.updateConversationMode(conversationId: selectedConversationId, mode: mode)
    }

    internal func applyStrictAgentModeProviderSelection(preferredProviderId: String?) {
        if let resolved = ProviderSupport.preferredOrCurrentAgentProviderId(
            preferred: preferredProviderId,
            current: providerRegistry.selectedProviderId,
            registry: providerRegistry
        ) {
            providerRegistry.selectedProviderId = resolved
            return
        }
        let hasCurrentAgentProvider: Bool = {
            guard let current = providerRegistry.selectedProviderId else { return false }
            return ProviderSupport.isAgentCompatibleProvider(id: current)
                && providerRegistry.provider(for: current) != nil
        }()
        if !hasCurrentAgentProvider {
            providerRegistry.selectedProviderId = ProviderSupport.firstHealthyAgentProviderId(
                preferred: nil,
                registry: providerRegistry
            )
        }
    }

    internal func modeColor(for m: CoderMode) -> Color {
        switch m {
        case .agent: return DesignSystem.Colors.agentColor
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewColor
        case .debug: return DesignSystem.Colors.debugColor
        case .plan: return DesignSystem.Colors.planColor
        case .ide: return DesignSystem.Colors.ideColor
        case .browser: return DesignSystem.Colors.browserColor
        case .mcpServer: return DesignSystem.Colors.mcpColor
        }
    }
    internal func modeIcon(for m: CoderMode) -> String {
        switch m {
        case .agent: return "brain"
        case .codeReviewMultiSwarm: return "doc.text.magnifyingglass"
        case .debug: return "ladybug.fill"
        case .plan: return "list.bullet.rectangle"
        case .ide: return "sparkles"
        case .browser: return "globe"
        case .mcpServer: return "server.rack"
        }
    }
    internal func modeGradient(for m: CoderMode) -> LinearGradient {
        switch m {
        case .agent: return DesignSystem.Colors.agentGradient
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewGradient
        case .debug: return DesignSystem.Colors.debugGradient
        case .plan: return DesignSystem.Colors.planGradient
        case .ide: return DesignSystem.Colors.ideGradient
        case .browser: return DesignSystem.Colors.browserGradient
        case .mcpServer: return DesignSystem.Colors.mcpGradient
        }
    }

    // MARK: - Provider Sync

}
