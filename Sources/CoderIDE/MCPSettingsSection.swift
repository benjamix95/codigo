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
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Header
            HStack {
                Image(systemName: "server.rack")
                    .font(.body.bold())
                    .foregroundStyle(DesignSystem.Colors.primary)
                Text("Server MCP")
                    .font(DesignSystem.Typography.headline)
                Spacer()
                Text("Configura i server Model Context Protocol")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.secondary)
            }
            
            // Description
            Text("Server rilevati da ~/.codex/config.toml e aggiunti manualmente.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondary)
                .padding(.bottom, DesignSystem.Spacing.sm)
            
            // Detected servers
            if !detectedServers.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    sectionLabel("Rilevati automaticamente")
                    
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
            }
            
            // Manual servers
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                sectionLabel("Server manuali")
                
                if manualServers.isEmpty {
                    Text("Nessun server manuale configurato")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.secondary)
                        .padding(DesignSystem.Spacing.md)
                        .frame(maxWidth: .infinity)
                        .background(DesignSystem.Colors.backgroundTertiary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
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
                            Button("Elimina") { deleteManual(server) }
                        }
                    }
                }
            }
            
            // Add button
            Button(action: { showAddForm = true }) {
                Label("Aggiungi server MCP", systemImage: "plus.circle.fill")
                    .font(DesignSystem.Typography.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.primary)
            .padding(.top, DesignSystem.Spacing.sm)
            
            // Sheets
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
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .stroke(DesignSystem.Colors.divider, lineWidth: 1)
        )
        .onAppear {
            loadAll()
        }
    }
    
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
    
    private func loadAll() {
        detectedServers = MCPConfigLoader.loadFromCodexConfig()
        manualServers = MCPConfigLoader.loadManualServers()
    }
    
    private func toggleDetected(_ id: String) {
        var ids = disabledIds
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        if let data = try? JSONEncoder().encode(Array(ids)),
           let str = String(data: data, encoding: .utf8) {
            disabledIdsJson = str
        }
    }
    
    private func saveNew(_ server: MCPServerConfig) {
        var list = manualServers
        list.append(server)
        manualServers = list
        try? MCPConfigLoader.saveManualServers(list)
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
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack {
                    Text(name)
                        .font(DesignSystem.Typography.subheadline.bold())
                    Text("(\(source))")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundStyle(DesignSystem.Colors.secondary)
                }
                Text(command)
                    .font(DesignSystem.Typography.caption.monospaced())
                    .foregroundStyle(DesignSystem.Colors.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isDetected, let toggle = onToggle {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { _ in toggle() }
                ))
                .labelsHidden()
                .tint(DesignSystem.Colors.primary)
            } else if !isDetected, let edit = onEdit {
                Button(action: edit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DesignSystem.Colors.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.backgroundTertiary.opacity(isEnabled ? 0.5 : 0.2))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }
}

struct MCPEditFormView: View {
    let server: MCPServerConfig
    let onSave: (MCPServerConfig) -> Void
    let onCancel: () -> Void
    
    @State private var name: String = ""
    @State private var command: String = ""
    @State private var argsText: String = ""
    @State private var envText: String = ""
    @State private var enabled: Bool = true
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            // Header
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(DesignSystem.Colors.primary)
                Text("Configura server MCP")
                    .font(DesignSystem.Typography.title2)
                Spacer()
            }
            
            // Form
            VStack(spacing: DesignSystem.Spacing.lg) {
                formField("Nome") {
                    TextField("nome-server", text: $name)
                        .textFieldStyle(.plain)
                }
                
                formField("Command") {
                    TextField("es. npx, /usr/bin/codex", text: $command)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.code)
                }
                
                formField("Args (virgola separata)") {
                    TextField("es. -y, mcp-server", text: $argsText)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.code)
                }
                
                formField("Env (chiave=valore, uno per riga)") {
                    TextEditor(text: $envText)
                        .font(DesignSystem.Typography.code)
                        .frame(height: 80)
                        .scrollContentBackground(.hidden)
                        .background(DesignSystem.Colors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(DesignSystem.Colors.divider, lineWidth: 1)
                        )
                }
                
                Toggle("Abilitato", isOn: $enabled)
                    .font(DesignSystem.Typography.subheadline)
                    .tint(DesignSystem.Colors.primary)
            }
            
            // Actions
            HStack(spacing: DesignSystem.Spacing.lg) {
                Button("Annulla", role: .cancel, action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())
                
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
                    s.name = name
                    s.command = command
                    s.args = args
                    s.env = env
                    s.enabled = enabled
                    onSave(s)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.isEmpty || command.isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 450, height: 480)
        .background(DesignSystem.Colors.backgroundPrimary)
        .onAppear {
            name = server.name
            command = server.command
            argsText = server.args.joined(separator: ", ")
            envText = server.env.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
            enabled = server.enabled
        }
    }
    
    private func formField(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondary)
            content()
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .stroke(DesignSystem.Colors.divider, lineWidth: 1)
                )
        }
    }
}
