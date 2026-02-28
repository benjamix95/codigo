import SwiftUI

struct PlanChatCardView: View {
    let entry: PlanHistoryEntry
    let onDownload: () -> Void
    let onDuplicate: () -> Void
    let onRebuild: () -> Void
    let onOpenInPanel: () -> Void
    let onRemove: () -> Void
    let onExpandPlan: () -> Void

    private var nonEmptyLines: [String] {
        entry.markdown
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var truncatedMarkdown: String {
        let raw = nonEmptyLines.prefix(12).joined(separator: "\n")
        return MermaidExtractor.stripMermaidBlocks(from: raw)
    }

    private var isTruncated: Bool {
        nonEmptyLines.count > 12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.planColor)
                Text(entry.title.isEmpty ? "Plan" : entry.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Menu {
                    Button(action: onRebuild) {
                        Label("Rebuild", systemImage: "arrow.clockwise")
                    }
                    Button(action: onDuplicate) {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    Button(action: onDownload) {
                        Label("Download", systemImage: "arrow.down.to.line")
                    }
                    Button(action: onOpenInPanel) {
                        Label("Open in history", systemImage: "clock")
                    }
                    Divider()
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            MarkdownContentView(
                content: truncatedMarkdown,
                context: nil,
                onFileClicked: { _ in },
                textAlignment: .leading
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if isTruncated {
                Button(action: onExpandPlan) {
                    HStack(spacing: 4) {
                        Text("View full plan")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(DesignSystem.Colors.planColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}
