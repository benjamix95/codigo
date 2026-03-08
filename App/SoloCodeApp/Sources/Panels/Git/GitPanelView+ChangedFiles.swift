import SwiftUI

extension GitPanelView {
    // MARK: - Changed Files (Staged / Unstaged split)

    var changedFilesSection: some View {
        VStack(spacing: 0) {
            if store.changedFiles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(DesignSystem.Colors.success.opacity(0.5))
                    Text("No changed files")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Staged section
                        if !store.stagedFiles.isEmpty {
                            fileSectionHeader(
                                title: "Staged Changes",
                                count: store.stagedFiles.count,
                                color: DesignSystem.Colors.success,
                                action: { store.unstageAll() },
                                actionLabel: "Unstage All",
                                actionIcon: "minus.circle"
                            )
                            ForEach(store.stagedFiles) { file in
                                fileRow(file, staged: true)
                            }
                        }

                        // Unstaged section
                        fileSectionHeader(
                            title: "Changes",
                            count: store.unstagedFiles.count,
                            color: .secondary,
                            action: { store.stageAll() },
                            actionLabel: "Stage All",
                            actionIcon: "plus.circle"
                        )
                        ForEach(store.unstagedFiles) { file in
                            fileRow(file, staged: false)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileSectionHeader(
        title: String,
        count: Int,
        color: Color,
        action: @escaping () -> Void,
        actionLabel: String,
        actionIcon: String
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(color.opacity(0.15), in: Capsule())
                .foregroundStyle(color)
            Spacer()
            Button(action: action) {
                HStack(spacing: 3) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 9, weight: .bold))
                    Text(actionLabel)
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
    }

    private func fileRow(_ file: GitChangedFile, staged: Bool) -> some View {
        HStack(spacing: 8) {
            // Status badge
            Text(file.status)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(statusColor(file.status))
                .frame(width: 18, height: 18)
                .background(statusColor(file.status).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            // File name
            Button {
                onOpenFile(file.path)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text((file.path as NSString).lastPathComponent)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    let dir = (file.path as NSString).deletingLastPathComponent
                    if !dir.isEmpty {
                        Text(dir)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Diff stats
            HStack(spacing: 3) {
                Text("+\(file.added)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("-\(file.removed)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.error)
            }

            // Stage / Unstage button
            if staged {
                Button { store.unstageFile(path: file.path) } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.warning)
                }
                .buttonStyle(.plain)
                .help("Unstage")
            } else {
                Button { store.stageFile(path: file.path) } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.success)
                }
                .buttonStyle(.plain)
                .help("Stage")

                // Undo button (only for unstaged)
                Button { store.undo(path: file.path) } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Discard changes")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .hoverHighlight(Color.primary.opacity(0.04))
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "A", "??": return DesignSystem.Colors.success
        case "D": return DesignSystem.Colors.error
        case "M": return DesignSystem.Colors.warning
        case "R": return DesignSystem.Colors.info
        default: return .secondary
        }
    }
}

