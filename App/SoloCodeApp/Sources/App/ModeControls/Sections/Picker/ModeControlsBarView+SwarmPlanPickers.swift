import CoderEngine
import SwiftUI

extension ModeControlsBarView {
    // MARK: - Swarm Orchestrator Picker
    func orchPickerButton(_ id: String, _ label: String) -> some View {
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

    var swarmOrchestratorPicker: some View {
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
    var planBackendPicker: some View {
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
}
