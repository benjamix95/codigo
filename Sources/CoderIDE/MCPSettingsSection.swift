import SwiftUI
import CoderEngine

struct MCPSettingsSection: View {
    @State private var manualServers: [MCPServerConfig] = []
    @State private var detectedServers: [MCPConfigLoader.DetectedServer] = []
    @State private var showAddForm = false
    @State private var editingServer: MCPServerConfig?
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
            Text("Configura i server Model Context Protocol")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !detectedServers.isEmpty {
                Text("Rilevati automaticamente")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(detectedServers) { server in
                    MCPRowView(
                        name: server.name,
                        command: server.command,
                        source: server.source,
                        isEnabled: !disabledIds.contains(server.id),
                        isDetected: true,
                        onToggle: { toggleDetected(server.id) },
                        onEdit: nil
                    )
                }
            }

            Text("Server manuali")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if manualServers.isEmpty {
                Text("Nessun server manuale configurato")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(manualServers) { server in
                    MCPRowView(
                        name: server.name,
                        command: server.command,
                        source: "Manuale",
                        isEnabled: server.enabled,
                        isDetected: false,
                        onToggle: nil,
                        onEdit: { editingServer = server }
                    )
                    .contextMenu {
                        Button("Elimina", role: .destructive) { deleteManual(server) }
                    }
                }
            }

            Button { showAddForm = true } label: {
                Label("Aggiungi server MCP", systemImage: "plus.circle.fill")
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

    private func toggleDetected(_ id: String) {
        var ids = disabledIds
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        if let data = try? JSONEncoder().encode(Array(ids)),
           let str = String(data: data, encoding: .utf8) {
            disabledIdsJson = str
        }
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
}

private struct MCPRowView: View {
    let name: String
    let command: String
    let source: String
    let isEnabled: Bool
    let isDetected: Bool
    let onToggle: (() -> Void)?
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
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(isEnabled ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MCPEditFormView: View {
    let server: MCPServerConfig
    let onSave: (MCPServerConfig) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var command = ""
    @State private var argsText = ""
    @State private var envText = ""
    @State private var enabled = true

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                Text("Configura server MCP")
                    .font(.title3)
                Spacer()
            }

            Form {
                TextField("Nome", text: $name)
                TextField("Command (es. npx, /usr/bin/codex)", text: $command)
                    .font(.body.monospaced())
                TextField("Args (virgola separata)", text: $argsText)
                    .font(.body.monospaced())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Env (chiave=valore, uno per riga)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $envText)
                        .font(.body.monospaced())
                        .frame(height: 80)
                }

                Toggle("Abilitato", isOn: $enabled)
            }
            .formStyle(.grouped)

            HStack(spacing: 12) {
                Button("Annulla", role: .cancel, action: onCancel)
                Button("Salva") {
                    let args = argsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    var env: [String: String] = [:]
                    for line in envText.components(separatedBy: .newlines) {
                        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                        if parts.count == 2 {
                            env[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
                        }
                    }
                    var s = server
                    s.name = name; s.command = command; s.args = args; s.env = env; s.enabled = enabled
                    onSave(s)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || command.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 450, height: 480)
        .onAppear {
            name = server.name
            command = server.command
            argsText = server.args.joined(separator: ", ")
            envText = server.env.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
            enabled = server.enabled
        }
    }
}
