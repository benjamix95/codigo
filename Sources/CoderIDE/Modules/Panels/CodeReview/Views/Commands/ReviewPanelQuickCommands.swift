import SwiftUI

/// Quick commands card showing built-in and custom panel commands.
struct ReviewPanelQuickCommands: View {
    @ObservedObject var store: CodeReviewPanelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.accent)
                Text("QUICK COMMANDS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
            }

            ForEach(store.allSlashCommands) { cmd in
                Button {
                    Task { await store.runQuickCommand(cmd) }
                } label: {
                    commandRow(cmd)
                }
                .buttonStyle(.plain)
                .disabled(store.isRunning)
            }

            bugHunterButtons
        }
    }

    private var bugHunterButtons: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                store.startBugHunterUncommitted()
            } label: {
                commandRow(
                    ReviewPanelSlashCommand(
                        id: "bughunter-uncommitted",
                        slash: "bughunter-uncommitted",
                        label: "BugHunter on uncommitted",
                        prompt: "",
                        isCustom: false
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(store.isRunning)

            Button {
                store.startBugHunterCommitWindow()
            } label: {
                commandRow(
                    ReviewPanelSlashCommand(
                        id: "bughunter-window",
                        slash: "bughunter-window",
                        label: "BugHunter on commit window",
                        prompt: "",
                        isCustom: false
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(store.isRunning || (store.selectedCommits.isEmpty && store.gitCommitLog.isEmpty))
        }
    }

    private func commandRow(_ cmd: ReviewPanelSlashCommand) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(cmd.isCustom ? DesignSystem.Colors.info.opacity(0.6) : store.accent.opacity(0.6))
                .frame(width: 2.5)
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(cmd.displayCommand)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(store.accent)
                    if cmd.isCustom {
                        Text("custom")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.info)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(DesignSystem.Colors.info.opacity(0.1), in: Capsule())
                    }
                }
                Text(cmd.label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 8)
            .padding(.vertical, 5)

            Spacer(minLength: 4)

            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.quaternary)
                .padding(.trailing, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
        )
    }
}
