import SwiftUI

extension UsageFooterView {
    /// Branch attuale subito prima dell’indicatore finestra contesto (es. "1M"), con menu per checkout rapido.
    @ViewBuilder
    var footerBranchPicker: some View {
        if gitPanelStore.gitRoot != nil {
            Menu {
                if sortedFooterBranches.isEmpty {
                    Text("No local branches")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedFooterBranches) { branch in
                        Button {
                            if !branch.isCurrent {
                                gitPanelStore.switchBranch(branch.name)
                            }
                        } label: {
                            HStack {
                                Text(branch.name)
                                if branch.isCurrent {
                                    Spacer(minLength: 8)
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Divider()
                Button {
                    gitPanelStore.isOpen = true
                } label: {
                    Label("Open Git panel", systemImage: "sidebar.right")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(footerBranchDisplayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(maxWidth: 160, alignment: .leading)
                .background(
                    Color(nsColor: .controlBackgroundColor).opacity(0.55),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        DesignSystem.Colors.borderSubtle,
                        lineWidth: 0.8
                    )
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(gitPanelStore.isBusy)
            .opacity(gitPanelStore.isBusy ? 0.55 : 1)
            .help("Switch branch")
        }
    }

    private var sortedFooterBranches: [GitBranch] {
        gitPanelStore.branches.sorted { a, b in
            if a.isCurrent != b.isCurrent { return a.isCurrent && !b.isCurrent }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private var footerBranchDisplayName: String {
        let name = gitPanelStore.currentBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "-" { return "—" }
        return name
    }
}
