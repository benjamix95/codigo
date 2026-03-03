import SwiftUI

extension SkillsPluginsSection {
    var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Skills & Plugins").font(.title3.weight(.semibold))
                Text("Installed tools detected on this system").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var itemsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            let grouped = Dictionary(grouping: items, by: \.source)
            ForEach([DetectedSkillItem.SkillSource.claude, .codex, .gemini, .mcp], id: \.rawValue) { source in
                if let group = grouped[source], !group.isEmpty {
                    Text(source.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 6)

                    ForEach(group) { item in
                        skillRow(item)
                    }
                }
            }
        }
    }

    func skillRow(_ item: DetectedSkillItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                    Text(item.kind.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(kindColor(item.kind).opacity(0.15), in: Capsule())
                        .foregroundStyle(kindColor(item.kind))
                }
                Text(item.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    func kindColor(_ kind: DetectedSkillItem.SkillKind) -> Color {
        switch kind {
        case .skill: return .blue
        case .plugin: return .purple
        case .prompt: return .orange
        case .command: return .green
        }
    }

    func hintBox(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary).font(.caption)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
