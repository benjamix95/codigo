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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Plan")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
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
                    Text("Expand plan")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.8)
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
