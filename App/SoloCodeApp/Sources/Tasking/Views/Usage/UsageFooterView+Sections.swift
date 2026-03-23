import CoderEngine
import SwiftUI

func shouldShowFooterUsageDivider(
    showProviderUsage: Bool,
    showContext: Bool,
    showTotal: Bool,
    indexProgress: IndexingProgress?
) -> Bool {
    showProviderUsage || showContext || showTotal || indexProgress != nil
}

extension UsageFooterView {
    func footerTier(
        showBranch: Bool,
        showProviderUsage: Bool,
        showContext: Bool,
        showTotal: Bool,
        showMessages: Bool
    ) -> some View {
        HStack(spacing: 6) {
            worktreeToggleButton
            gitButton(showBranch: showBranch)
            if shouldShowFooterUsageDivider(
                showProviderUsage: showProviderUsage,
                showContext: showContext,
                showTotal: showTotal,
                indexProgress: workspaceStore.indexProgress
            ) {
                Divider().frame(height: 12)
            }
            if showProviderUsage {
                providerUsageSection.fixedSize()
            }
            if showContext {
                contextSection.fixedSize()
            }
            if showTotal {
                totalUsageLabel.fixedSize()
            }
            indexProgressLabel.fixedSize()
            Spacer(minLength: 0)
            if showMessages {
                footerMessages
            }
        }
    }

    func gitButton(showBranch: Bool) -> some View {
        Button {
            gitPanelStore.isOpen.toggle()
        } label: {
            gitButtonLabel(showBranch: showBranch)
        }
        .buttonStyle(.plain)
        .help(gitPanelStore.gitRoot == nil ? "No Git repository" : "Open Git panel")
    }

    func gitButtonLabel(showBranch: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(gitPanelStore.isOpen ? DesignSystem.Colors.agentColor : .primary)
            if showBranch {
                Text(gitPanelStore.currentBranch)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            if !gitPanelStore.changedFiles.isEmpty {
                Text("\(gitPanelStore.changedFiles.count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(DesignSystem.Colors.agentColor, in: Capsule())
            }
        }
        .padding(.horizontal, showBranch ? 10 : 6)
        .padding(.vertical, 5)
        .background(
            (gitPanelStore.isOpen ? DesignSystem.Colors.agentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.55)),
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(
                gitPanelStore.isOpen ? DesignSystem.Colors.agentColor.opacity(0.3) : DesignSystem.Colors.borderSubtle,
                lineWidth: 0.8
            )
        )
    }

    var worktreeToggleButton: some View {
        Button {
            handleWorktreeToggleTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                Text(worktreeToggleTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
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
        .buttonStyle(.plain)
        .disabled(isWorktreeToggleDisabled || isWorktreeActionInFlight)
        .help(worktreeToggleHelpText)
    }

    var totalUsageLabel: some View {
        Text(totalUsageText)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    var footerMessages: some View {
        if let success = worktreeStatusMessage, !success.isEmpty {
            Text(success)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.success)
                .lineLimit(1)
        }
        if let err = worktreeErrorMessage, !err.isEmpty {
            Text(err)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.error)
                .lineLimit(1)
        }
        if let success = gitPanelStore.successMessage, !success.isEmpty {
            Text(success)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.success)
                .lineLimit(1)
        }
        if let err = gitPanelStore.error, !err.isEmpty {
            Text(err)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.error)
                .lineLimit(1)
        }
    }
}
