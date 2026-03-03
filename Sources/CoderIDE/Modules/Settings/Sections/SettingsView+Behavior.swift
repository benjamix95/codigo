import SwiftUI

extension SettingsView {
    var behaviorSection: some View {
        let historyEntryLimits = [50, 100, 200]
        let historyMarkdownLimits = [32_768, 49_152, 65_536]
        return VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Behavior", subtitle: "Agent and terminal behavior", icon: "bolt.fill")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("YOLO Mode (full auto)", isOn: $globalYolo)
                    hintBox("When enabled, the agent runs commands and edits files without confirmation. Useful for automation, but potentially destructive.")
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-follow terminal output", isOn: $terminalAutoFollowOutput)
                    hintBox("Automatically follows terminal output while commands are running.")
                }
            }

            GroupBox("Automatic chat summary") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable automatic summary", isOn: Binding(
                        get: { summarizeThreshold < 1.0 },
                        set: { summarizeThreshold = $0 ? 0.8 : 1.0 }
                    ))
                    if summarizeThreshold < 1.0 {
                        HStack {
                            fieldLabel("Context threshold")
                            Slider(value: $summarizeThreshold, in: 0.3...0.95, step: 0.05)
                            Text("\(Int(summarizeThreshold * 100))%").font(.caption).foregroundStyle(.secondary)
                        }
                        Stepper("Keep last \(summarizeKeepLast) messages", value: $summarizeKeepLast, in: 2...20)
                    }
                    hintBox("Automatically summarizes chat when context exceeds the threshold, keeping the latest messages untouched.")
                }.padding(4)
            }

            GroupBox("Application updates") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Controlla aggiornamenti all'avvio", isOn: $appUpdateCheckEnabled)
                    TextField("URL manifest aggiornamenti", text: $appUpdateManifestURL)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        Button("Ripristina URL predefinito") {
                            appUpdateManifestURL = AppUpdateCenter.defaultManifestURL
                            appUpdateCenter.setManifestURL(appUpdateManifestURL)
                        }
                        Button("Controlla ora") {
                            Task {
                                appUpdateCenter.setManifestURL(appUpdateManifestURL)
                                appUpdateCenter.setUpdateCheckEnabled(appUpdateCheckEnabled)
                                await appUpdateCenter.checkForUpdates(force: true)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
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
                    if let last = appUpdateCenter.lastCheckedAt {
                        Text("Ultimo controllo: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }.padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-approve tools", isOn: $fullAutoTools)
                    hintBox("Automatically approves tool calls (files, terminal, etc.) without interactive confirmation.")
                }
            }

            GroupBox("Plan history limits") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel("Max entries")
                        Spacer()
                        Picker("Max entries", selection: $planHistoryMaxEntries) {
                            ForEach(historyEntryLimits, id: \.self) { limit in
                                Text("\(limit)").tag(limit)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }

                    HStack {
                        fieldLabel("Max markdown chars")
                        Spacer()
                        Picker("Max markdown chars", selection: $planHistoryMaxMarkdownLength) {
                            ForEach(historyMarkdownLimits, id: \.self) { limit in
                                Text("\(limit)").tag(limit)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }

                    hintBox("Controls how many plan snapshots are retained and their maximum markdown size. Existing history is trimmed immediately when lowering limits.")
                }
            }
        }
    }
}
