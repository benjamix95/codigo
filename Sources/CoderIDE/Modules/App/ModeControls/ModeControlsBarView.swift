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
    @Binding var browserToggleEnabled: Bool

    // MARK: - Collapse Tiers

    enum ControlsTier {
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
    func controlsHStack(tier: ControlsTier) -> some View {
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

            browserIconButton
            planIconButton
            debugIconButton
            codeReviewIconButton
            swarmIconButton
        }
    }

    func hasAccessLevel(_ pid: String) -> Bool {
        ["codex-cli", "gemini-cli", "claude-cli", "openrouter-api",
         "openai-api", "anthropic-api", "google-api", "minimax-api", "grok-api"].contains(pid)
    }

    @ViewBuilder
    func modelPickerForProvider(_ pid: String) -> some View {
        switch pid {
        case "codex-cli": codexModelPicker
        case "gemini-cli": geminiModelPicker
        case "claude-cli": claudeModelPicker
        case "openrouter-api": openRouterModelPicker
        default: EmptyView()
        }
    }
}
