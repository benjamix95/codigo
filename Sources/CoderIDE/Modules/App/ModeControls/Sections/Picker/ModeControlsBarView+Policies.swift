import CoderEngine
import SwiftUI

extension ModeControlsBarView {
    // MARK: - Codex Reasoning Picker
    var codexReasoningPicker: some View {
        Menu {
            ForEach(["none", "low", "medium", "high", "xhigh"], id: \.self) { e in
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

    func reasoningEffortDisplay(_ e: String) -> String {
        switch e.lowercased() {
        case "none": return "None"
        case "low": return "Low"
        case "medium": return "Medium"
        case "high": return "High"
        case "xhigh": return "XHigh"
        default: return e
        }
    }

    // MARK: - Access Level Menu
    func accessLevelMenuView(showLabel: Bool) -> some View {
        let cfg = CodexConfigLoader.load()
        let currentSandbox = codexSandbox.isEmpty
            ? (cfg.sandboxMode ?? "workspace-write")
            : codexSandbox
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
                Image(systemName: accessLevelIcon(for: currentSandbox)).font(.caption)
                if showLabel {
                    Text(accessLevelLabel(for: currentSandbox)).font(.caption).lineLimit(1)
                }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(
                currentSandbox == "danger-full-access"
                    ? DesignSystem.Colors.error : .secondary
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    func accessLevelIcon(for s: String) -> String {
        switch s {
        case "read-only": return "lock.shield"
        case "danger-full-access": return "exclamationmark.shield.fill"
        default: return "shield"
        }
    }

    func accessLevelLabel(for s: String) -> String {
        switch s {
        case "read-only": return "Read Only"
        case "danger-full-access": return "Full Access"
        default: return "Default"
        }
    }
}
