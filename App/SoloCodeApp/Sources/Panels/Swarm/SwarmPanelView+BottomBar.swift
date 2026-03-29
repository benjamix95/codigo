import SwiftUI

extension SwarmPanelView {
    // MARK: - Bottom Bar

    var bottomBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text("\(activeCards.count) active · \(finishedCards.count) finished")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)

                if isTaskRunning {
                    let totalOps = activeCards.reduce(0) { $0 + $1.activeOpsCount }
                    if totalOps > 0 {
                        Text("·").foregroundStyle(.quaternary)
                        Text("\(totalOps) active ops")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(accent)
                    }
                }

                Spacer()

                if !isFollowingLive && isTaskRunning {
                    Button("Follow Live") { isFollowingLive = true }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accent)
                        .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                orchestratorPicker
                workerPicker
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Provider Pickers

    private var orchestratorLabel: String {
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
    }

    private var orchestratorPicker: some View {
        Button {
            isWorkerPopoverPresented = false
            isOrchestratorPopoverPresented.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "cpu").font(.system(size: 8))
                Text("Orch: \(orchestratorLabel)").font(.system(size: 10))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isOrchestratorPopoverPresented, arrowEdge: .bottom) {
            providerPopover(
                title: "Orchestrator Backend",
                options: orchestratorOptions,
                selectedId: swarmOrchestrator
            ) { id in
                swarmOrchestrator = id
                onSyncSwarmProvider()
                isOrchestratorPopoverPresented = false
            }
        }
    }

    private var workerLabel: String {
        switch swarmWorkerBackend {
        case "auto": return "Auto"
        case "claude": return "Claude"
        case "gemini": return "Gemini"
        case "openai-api", "openai": return "OpenAI"
        case "anthropic-api": return "Anthropic"
        case "google-api": return "Google"
        case "openrouter-api", "openrouter": return "OpenRouter"
        case "minimax-api": return "MiniMax"
        case "grok-api": return "Grok"
        default: return "Codex"
        }
    }

    private var workerPicker: some View {
        Button {
            isOrchestratorPopoverPresented = false
            isWorkerPopoverPresented.toggle()
        } label: {
            HStack(spacing: 3) {
                Text("Worker: \(workerLabel)").font(.system(size: 10))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isWorkerPopoverPresented, arrowEdge: .bottom) {
            providerPopover(
                title: "Worker Backend",
                options: workerOptions,
                selectedId: swarmWorkerBackend
            ) { id in
                swarmWorkerBackend = id
                onSyncSwarmProvider()
                isWorkerPopoverPresented = false
            }
        }
    }

    private var orchestratorOptions: [ProviderOption] {
        [
            .init(id: "auto", label: "Auto (same as Agent)"),
            .init(id: "openai", label: "OpenAI API"),
            .init(id: "anthropic-api", label: "Anthropic API"),
            .init(id: "google-api", label: "Google API"),
            .init(id: "openrouter-api", label: "OpenRouter"),
            .init(id: "minimax-api", label: "MiniMax API"),
            .init(id: "grok-api", label: "Grok API"),
            .init(id: "codex", label: "Codex CLI"),
            .init(id: "claude", label: "Claude Code"),
            .init(id: "gemini", label: "Gemini CLI"),
        ]
    }

    private var workerOptions: [ProviderOption] {
        [
            .init(id: "auto", label: "Auto (same as Agent)"),
            .init(id: "openai-api", label: "OpenAI API"),
            .init(id: "anthropic-api", label: "Anthropic API"),
            .init(id: "google-api", label: "Google API"),
            .init(id: "openrouter-api", label: "OpenRouter"),
            .init(id: "minimax-api", label: "MiniMax API"),
            .init(id: "grok-api", label: "Grok API"),
            .init(id: "codex", label: "Codex CLI"),
            .init(id: "claude", label: "Claude Code"),
            .init(id: "gemini", label: "Gemini CLI"),
        ]
    }

    private func providerPopover(
        title: String,
        options: [ProviderOption],
        selectedId: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(options) { option in
                        Button {
                            onSelect(option.id)
                        } label: {
                            HStack(spacing: 8) {
                                Text(option.label)
                                    .font(.system(size: 11))
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                if selectedId == option.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(accent)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selectedId == option.id ? accent.opacity(0.12) : Color.clear)
                        )
                    }
                }
            }
            .frame(width: 240)
            .frame(maxHeight: 260)
        }
        .padding(10)
    }
}
