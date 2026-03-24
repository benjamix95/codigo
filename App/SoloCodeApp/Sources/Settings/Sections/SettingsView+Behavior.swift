import SwiftUI

// MARK: - BehaviorSettingsSection

struct BehaviorSettingsSection: View {
    @State var behaviorConfig = SettingsBehaviorConfig()

    @EnvironmentObject var syncCoordinator: SettingsSyncCoordinator
    @EnvironmentObject var appUpdateCenter: AppUpdateCenter

    var body: some View {
        let historyEntryLimits = [50, 100, 200]
        let historyMarkdownLimits = [32_768, 49_152, 65_536]

        VStack(alignment: .leading, spacing: 20) {
            settingsSectionHeader(title: "Behavior", subtitle: "Agent and terminal behavior", icon: "bolt.fill")

            yoloGroup
            terminalAutoFollowGroup
            chatSummaryGroup(historyEntryLimits: historyEntryLimits, historyMarkdownLimits: historyMarkdownLimits)
            appUpdatesGroup
            autoApproveToolsGroup
            planHistoryGroup(entryLimits: historyEntryLimits, markdownLimits: historyMarkdownLimits)
        }
        .onChange(of: behaviorConfig.globalYolo) { _ in
            syncCoordinator.syncCodex()
            syncCoordinator.syncPlanProvider()
            syncCoordinator.syncCodeReview()
        }
        .onChange(of: behaviorConfig.appUpdateCheckEnabled) { isEnabled in
            appUpdateCenter.setUpdateCheckEnabled(isEnabled)
        }
        .onChange(of: behaviorConfig.appUpdateManifestURL) { newURL in
            appUpdateCenter.setManifestURL(newURL)
        }
    }
}

// MARK: - Subviews

private extension BehaviorSettingsSection {
    var yoloGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("YOLO Mode (full auto)", isOn: $behaviorConfig.globalYolo)
                settingsHintBox("When enabled, the agent runs commands and edits files without confirmation. Useful for automation, but potentially destructive.")
            }
        }
    }

    var terminalAutoFollowGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Auto-follow terminal output", isOn: $behaviorConfig.terminalAutoFollowOutput)
                settingsHintBox("Automatically follows terminal output while commands are running.")
            }
        }
    }

    func chatSummaryGroup(historyEntryLimits _: [Int], historyMarkdownLimits _: [Int]) -> some View {
        GroupBox("Automatic chat summary") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable automatic summary", isOn: Binding(
                    get: { behaviorConfig.summarizeThreshold < 1.0 },
                    set: { behaviorConfig.summarizeThreshold = $0 ? 0.8 : 1.0 }
                ))
                if behaviorConfig.summarizeThreshold < 1.0 {
                    HStack {
                        settingsFieldLabel("Context threshold")
                        Slider(value: $behaviorConfig.summarizeThreshold, in: 0.3...0.95, step: 0.05)
                        Text("\(Int(behaviorConfig.summarizeThreshold * 100))%").font(.caption).foregroundStyle(.secondary)
                    }
                    Stepper("Keep last \(behaviorConfig.summarizeKeepLast) messages", value: $behaviorConfig.summarizeKeepLast, in: 2...20)
                }
                settingsHintBox("Automatically summarizes chat when context exceeds the threshold, keeping the latest messages untouched.")
            }.padding(4)
        }
    }

    var appUpdatesGroup: some View {
        GroupBox("Application updates") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Controlla aggiornamenti all'avvio", isOn: $behaviorConfig.appUpdateCheckEnabled)
                TextField("URL manifest aggiornamenti", text: $behaviorConfig.appUpdateManifestURL)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    Button("Ripristina URL predefinito") {
                        behaviorConfig.appUpdateManifestURL = AppUpdateCenter.defaultManifestURL
                        appUpdateCenter.setManifestURL(behaviorConfig.appUpdateManifestURL)
                    }
                    Button("Controlla ora") {
                        Task {
                            appUpdateCenter.setManifestURL(behaviorConfig.appUpdateManifestURL)
                            appUpdateCenter.setUpdateCheckEnabled(behaviorConfig.appUpdateCheckEnabled)
                            await appUpdateCenter.checkForUpdates(force: true)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                updateStatusView
                if let last = appUpdateCenter.lastCheckedAt {
                    Text("Ultimo controllo: \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }.padding(4)
        }
    }

    @ViewBuilder
    var updateStatusView: some View {
        switch appUpdateCenter.state {
        case .idle:
            Text(appUpdateCenter.statusSummary)
        case .checking:
            Text(appUpdateCenter.statusSummary)
        case .disabled:
            Text(appUpdateCenter.statusSummary)
        case .upToDate:
            Text(appUpdateCenter.statusSummary)
        case .available(let manifest):
            Text("New update: \(manifest.version) (\(manifest.displayBuild))")
        case .failed(let error):
            Text(error).foregroundStyle(.red)
        }
    }

    var autoApproveToolsGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Auto-approve tools", isOn: $behaviorConfig.fullAutoTools)
                settingsHintBox("Automatically approves tool calls (files, terminal, etc.) without interactive confirmation.")
            }
        }
    }

    func planHistoryGroup(entryLimits: [Int], markdownLimits: [Int]) -> some View {
        GroupBox("Plan history limits") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    settingsFieldLabel("Max entries")
                    Spacer()
                    Picker("Max entries", selection: $behaviorConfig.planHistoryMaxEntries) {
                        ForEach(entryLimits, id: \.self) { limit in
                            Text("\(limit)").tag(limit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }

                HStack {
                    settingsFieldLabel("Max markdown chars")
                    Spacer()
                    Picker("Max markdown chars", selection: $behaviorConfig.planHistoryMaxMarkdownLength) {
                        ForEach(markdownLimits, id: \.self) { limit in
                            Text("\(limit)").tag(limit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }

                settingsHintBox("Controls how many plan snapshots are retained and their maximum markdown size. Existing history is trimmed immediately when lowering limits.")
            }
        }
    }
}
