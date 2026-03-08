import SwiftUI

struct SkillsPluginsSection: View {
    @State var items: [DetectedSkillItem] = []
    @State var isScanning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            hintBox("Skills and plugins are automatically detected from Claude, Codex, Gemini, and MCP. They are available to all AI providers.")

            if isScanning {
                ProgressView("Scanning...")
                    .font(.caption)
                    .padding()
            } else if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "puzzlepiece")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No skills or plugins detected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Install skills in ~/.claude/skills/, ~/.codex/skills/, or configure MCP servers.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            } else {
                itemsList
            }

            HStack {
                Button { scanAll() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .onAppear { scanAll() }
    }

    func scanAll() {
        isScanning = true
        Task.detached {
            let results = SkillScanner.scan()
            await MainActor.run {
                items = results
                isScanning = false
            }
        }
    }
}
