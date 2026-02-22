import SwiftUI

struct PlanChatCardView: View {
    let entry: PlanHistoryEntry
    let onDownload: () -> Void
    let onDuplicate: () -> Void
    let onRebuild: () -> Void
    let onOpenInPanel: () -> Void
    let onRemove: () -> Void
    let onExpandPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Plan")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 12) {
                    toolbarButton(icon: "arrow.down.to.line", help: "Download plan", action: onDownload)
                    toolbarButton(icon: "doc.on.doc", help: "Duplica planning", action: onDuplicate)
                    Menu {
                        Button("Rebuild ora", action: onRebuild)
                        Button("Apri nello storico", action: onOpenInPanel)
                        Divider()
                        Button("Rimuovi dallo storico", role: .destructive, action: onRemove)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            MarkdownContentView(
                content: entry.markdown,
                context: nil,
                onFileClicked: { _ in },
                textAlignment: .leading
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button(action: onExpandPlan) {
                    HStack(spacing: 6) {
                        Text("Apri piano completo")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(DesignSystem.Colors.border.opacity(0.45), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.5), lineWidth: 0.6)
        )
    }

    private func toolbarButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
