import SwiftUI
import CoderEngine

struct MCPSettingsSection: View {
    @State private var manualServers: [MCPServerConfig] = []
    @State private var detectedServers: [MCPConfigLoader.DetectedServer] = []
    @State private var showAddForm = false
    @State private var editingServer: MCPServerConfig?
    @State private var restartingServerIds: Set<String> = []
    @State private var restartErrors: [String: String] = [:]
    @AppStorage("mcp_disabled_ids") private var disabledIdsJson: String = "[]"

    private var disabledIds: Set<String> {
        get {
            guard let data = disabledIdsJson.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return Set(arr)
        }
        set {
            if let data = try? JSONEncoder().encode(Array(newValue)),
               let str = String(data: data, encoding: .utf8) {
                disabledIdsJson = str
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configure Model Context Protocol servers")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !detectedServers.isEmpty {
                Text("Auto-detected")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(detectedServers) { server in
                    let serverId = server.id
                    MCPRowView(
                        name: server.name,
                        command: server.command,
                        source: server.source,
                        isEnabled: isDetectedEnabled(server),
                        isDetected: true,
                        isRestarting: restartingServerIds.contains(serverId),
                        restartError: restartErrors[serverId],
                        onToggle: { toggleDetected(server) },
                        onRestart: { restartServer(serverId) },
                        onEdit: nil
                    )
                }
            }

            Text("Manual servers")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if manualServers.isEmpty {
                Text("No manual servers configured")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(manualServers) { server in
                    let serverId = runtimeServerID(for: server)
                    MCPRowView(
                        name: server.name,
                        command: server.command,
                        source: "Manual",
                        isEnabled: server.enabled,
                        isDetected: false,
                        isRestarting: restartingServerIds.contains(serverId),
                        restartError: restartErrors[serverId],
                        onToggle: nil,
                        onRestart: { restartServer(serverId) },
                        onEdit: { editingServer = server }
                    )
                    .contextMenu {
                        Button("Delete", role: .destructive) { deleteManual(server) }
                    }
                }
            }

            Button { showAddForm = true } label: {
                Label("Add MCP server", systemImage: "plus.circle.fill")
                    .font(.subheadline)
            }
            .sheet(isPresented: $showAddForm) {
                MCPEditFormView(
                    server: MCPServerConfig(),
                    onSave: { saveNew($0) },
                    onCancel: { showAddForm = false }
                )
            }
            .sheet(item: $editingServer) { server in
                MCPEditFormView(
                    server: server,
                    onSave: { updateManual($0) },
                    onCancel: { editingServer = nil }
                )
            }
        }
        .onAppear { loadAll() }
    }

    private func loadAll() {
        detectedServers = MCPConfigLoader.loadDetectedServers()
        manualServers = MCPConfigLoader.loadManualServers()
    }

    private func toggleDetected(_ server: MCPConfigLoader.DetectedServer) {
        var ids = disabledIds
        let identifiers = [server.id, server.legacyID].compactMap { $0 }
        let isCurrentlyDisabled = identifiers.contains { ids.contains($0) }
        if isCurrentlyDisabled {
            for identifier in identifiers {
                ids.remove(identifier)
            }
        } else {
            ids.insert(server.id)
        }
        if let data = try? JSONEncoder().encode(Array(ids)),
           let str = String(data: data, encoding: .utf8) {
            disabledIdsJson = str
        }
    }

    private func isDetectedEnabled(_ server: MCPConfigLoader.DetectedServer) -> Bool {
        if disabledIds.contains(server.id) { return false }
        if let legacyID = server.legacyID, disabledIds.contains(legacyID) { return false }
        return true
    }

    private func saveNew(_ server: MCPServerConfig) {
        manualServers.append(server)
        try? MCPConfigLoader.saveManualServers(manualServers)
        showAddForm = false
    }

    private func updateManual(_ server: MCPServerConfig) {
        if let idx = manualServers.firstIndex(where: { $0.id == server.id }) {
            manualServers[idx] = server
            try? MCPConfigLoader.saveManualServers(manualServers)
        }
        editingServer = nil
    }

    private func deleteManual(_ server: MCPServerConfig) {
        manualServers.removeAll { $0.id == server.id }
        try? MCPConfigLoader.saveManualServers(manualServers)
    }

    private func runtimeServerID(for server: MCPServerConfig) -> String {
        "manual-\(server.id.uuidString.lowercased())"
    }

    private func restartServer(_ serverId: String) {
        guard !restartingServerIds.contains(serverId) else { return }
        restartingServerIds.insert(serverId)
        restartErrors.removeValue(forKey: serverId)

        Task {
            do {
                try await MCPServerControlService.restart(serverId: serverId)
                await MainActor.run {
                    loadAll()
                }
                await MainActor.run {
                    CodexMCPHealthStore.shared.refresh()
                }
            } catch {
                await MainActor.run {
                    restartErrors[serverId] = error.localizedDescription
                }
            }
            _ = await MainActor.run {
                restartingServerIds.remove(serverId)
            }
        }
    }
}

private struct MCPRowView: View {
    let name: String
    let command: String
    let source: String
    let isEnabled: Bool
    let isDetected: Bool
    let isRestarting: Bool
    let restartError: String?
    let onToggle: (() -> Void)?
    let onRestart: (() -> Void)?
    let onEdit: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name).font(.subheadline.weight(.medium))
                    Text("(\(source))").font(.caption2).foregroundStyle(.secondary)
                }
                Text(command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    if let restart = onRestart {
                        Button(action: restart) {
                            if isRestarting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Riavvia", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRestarting || !isEnabled)
                    }

                    if isDetected, let toggle = onToggle {
                        Toggle("", isOn: Binding(get: { isEnabled }, set: { _ in toggle() }))
                            .labelsHidden()
                    } else if !isDetected, let edit = onEdit {
                        Button(action: edit) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let restartError, !restartError.isEmpty {
                    Text("Riavvio fallito")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .help(restartError)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(isEnabled ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
