import SwiftUI
import CoderEngine

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
                Text("Configure MCP server")
                    .font(.title3)
                Spacer()
            }

            Form {
                TextField("Name", text: $name)
                TextField("Command (e.g. npx, /usr/bin/codex)", text: $command)
                    .font(.body.monospaced())
                TextField("Args (comma-separated)", text: $argsText)
                    .font(.body.monospaced())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Env (key=value, one per line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $envText)
                        .font(.body.monospaced())
                        .frame(height: 80)
                }

                Toggle("Enabled", isOn: $enabled)
            }
            .formStyle(.grouped)

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save") {
                    let args = argsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    var env: [String: String] = [:]
                    for line in envText.components(separatedBy: .newlines) {
                        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                        if parts.count == 2 {
                            env[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
                        }
                    }
                    var updated = server
                    updated.name = name
                    updated.command = command
                    updated.args = args
                    updated.env = env
                    updated.enabled = enabled
                    onSave(updated)
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
