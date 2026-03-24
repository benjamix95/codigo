import SwiftUI
import CoderEngine

// MARK: - Claude Code Group

extension CLIToolsSettingsSection {
    var claudeCodeGroup: some View {
        GroupBox("Claude Code") {
            VStack(alignment: .leading, spacing: 12) {
                claudePathRow
                claudeReauthSection
                Divider()
                claudeAllowedToolsGrid
            }.padding(4)
        }
    }

    // MARK: - Path Row

    private var claudePathRow: some View {
        HStack {
            settingsFieldLabel("Path")
            TextField("Auto-detect", text: $cliConfig.claudePath).textFieldStyle(.roundedBorder)
            let claudeDetected = ClaudeDetector.detect(
                customPath: cliConfig.claudePath.isEmpty ? nil : cliConfig.claudePath
            )
            settingsStatusBadge(
                connected: claudeDetected.isInstalled && claudeDetected.isLoggedIn,
                label: !claudeDetected.isInstalled
                    ? "Not found"
                    : (claudeDetected.isLoggedIn ? "Connected" : "Token expired")
            )
        }
    }

    // MARK: - Re-auth Warning

    @ViewBuilder
    private var claudeReauthSection: some View {
        let claudeStatus = ClaudeDetector.detect(
            customPath: cliConfig.claudePath.isEmpty ? nil : cliConfig.claudePath
        )
        if claudeStatus.isInstalled && !claudeStatus.isLoggedIn {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("OAuth token expired. Open Claude Desktop app to refresh, or click below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Re-authenticate Claude") {
                connectToClaude()
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        }
    }

    // MARK: - Allowed Tools Grid

    private var claudeAllowedToolsGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            settingsFieldLabel("Allowed tools")
            let allTools = [
                "Read", "Edit", "Bash", "Write", "Search",
                "Task", "Glob", "Grep", "TodoRead", "TodoWrite"
            ]
            let selectedTools = parseClaudeAllowedTools()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 6) {
                ForEach(allTools, id: \.self) { tool in
                    let isOn = selectedTools.contains(tool)
                    Button {
                        var set = Set(selectedTools)
                        if isOn { set.remove(tool) } else { set.insert(tool) }
                        cliConfig.claudeAllowedTools = allTools
                            .filter { set.contains($0) }
                            .joined(separator: ",")
                    } label: {
                        Text(tool)
                            .font(.system(size: 10, weight: isOn ? .semibold : .regular))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(
                                isOn ? Color.accentColor.opacity(0.15) : Color.clear,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    isOn ? Color.accentColor : Color.secondary.opacity(0.3)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
