import SwiftUI
import CoderEngine

// MARK: - Gemini CLI Group

extension CLIToolsSettingsSection {
    var geminiGroup: some View {
        GroupBox("Gemini CLI") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    settingsFieldLabel("Path")
                    TextField("Auto-detect", text: $cliConfig.geminiCliPath).textFieldStyle(.roundedBorder)
                    settingsStatusBadge(
                        connected: geminiState.status.isInstalled,
                        label: geminiState.status.isInstalled ? "Installed" : "Not found"
                    )
                }
                if !geminiState.status.isInstalled {
                    Button("Connect to Gemini") {
                        geminiState.refresh()
                        if geminiState.status.isInstalled { syncCoordinator.syncGemini() }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }.padding(4)
        }
    }
}

// MARK: - Kilo CLI Group

extension CLIToolsSettingsSection {
    var kiloGroup: some View {
        GroupBox("Kilo CLI") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    settingsFieldLabel("Path")
                    TextField("Auto-detect", text: $cliConfig.kiloPath).textFieldStyle(.roundedBorder)
                    settingsStatusBadge(
                        connected: kiloState.status.isInstalled,
                        label: kiloState.status.isInstalled ? "Installed" : "Not found"
                    )
                }
                if !kiloState.status.isInstalled {
                    Button("Detect Kilo") {
                        kiloState.refresh()
                        if kiloState.status.isInstalled { syncCoordinator.syncKilo() }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                }
                Divider()
                settingsFieldLabel("Model")
                Picker("", selection: $cliConfig.kiloModel) {
                    Text("Auto").tag("")
                    ForEach(kiloModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .labelsHidden()
            }.padding(4)
        }
    }
}
