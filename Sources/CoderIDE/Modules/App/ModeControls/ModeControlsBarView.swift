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
    @State private var availableWidth: CGFloat = 900
    @State private var resolvedTier: ControlsTier = .full

    // MARK: - Collapse Tiers

    enum ControlsTier {
        case full, medium, compact, minimal
    }

    private let tierHysteresis: CGFloat = 20

    // MARK: - Body

    var body: some View {
        controlsHStack(tier: resolvedTier)
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
    }

    private func stableControlsTier(for width: CGFloat, current: ControlsTier) -> ControlsTier {
        switch current {
        case .full:
            return width < (900 - tierHysteresis) ? .medium : .full
        case .medium:
            if width >= (900 + tierHysteresis) {
                return .full
            }
            if width < (760 - tierHysteresis) {
                return .compact
            }
            return .medium
        case .compact:
            if width >= (760 + tierHysteresis) {
                return .medium
            }
            if width < (640 - tierHysteresis) {
                return .minimal
            }
            return .compact
        case .minimal:
            return width >= (640 + tierHysteresis) ? .compact : .minimal
        }
    }

    private func updateAvailableWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        guard abs(width - availableWidth) > 1 else { return }
        availableWidth = width
        var nextTier = resolvedTier
        while true {
            let candidate = stableControlsTier(for: width, current: nextTier)
            if candidate == nextTier {
                break
            }
            nextTier = candidate
        }
        guard nextTier != resolvedTier else { return }
        resolvedTier = nextTier
    }

    // MARK: - Tier HStack Builder

    @ViewBuilder
    func controlsHStack(tier: ControlsTier) -> some View {
        let pid = providerRegistry.selectedProviderId ?? ""
        HStack(spacing: 6) {
            // Provider picker: full=icon+name, other tiers=icon-only
            if tier == .full {
                providerPickerView(showLabel: true)
            } else {
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
