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
        showFooterBranchPicker: Bool,
        showProviderUsage: Bool,
        showContext: Bool,
        showTotal: Bool,
        showMessages: Bool
    ) -> some View {
        HStack(spacing: 6) {
            worktreeToggleButton
            gitButton
            if showFooterBranchPicker {
                footerBranchPicker
            }
            modelContextLabel
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

    var gitButton: some View {
        Button {
            gitPanelStore.isOpen.toggle()
        } label: {
            gitButtonLabel
        }
        .buttonStyle(.plain)
        .help(gitPanelStore.gitRoot == nil ? "No Git repository" : "Open Git panel")
    }

    /// Shows a compact label with the context window size of the active model
    /// (e.g. "1M", "200K", "128K") so the user always knows the token budget.
    var modelContextLabel: some View {
        let label = modelContextWindowLabel()
        return Group {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
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
        }
    }

    /// Returns a human-readable context window label based on the current model.
    private func modelContextWindowLabel() -> String {
        let model = effectiveContextModel
        // Models with 1M context
        if model.contains("[1m]") || model.contains("gpt-4.5") || model.contains("gpt-5") {
            return "1M"
        }
        // Claude Opus / Sonnet 200K
        if model.contains("opus") || model.contains("sonnet") {
            return "200K"
        }
        // Claude Haiku 200K
        if model.contains("haiku") {
            return "200K"
        }
        // Gemini models typically 1M
        if model.contains("gemini") {
            return "1M"
        }
        // GPT-4o 128K
        if model.contains("gpt-4o") {
            return "128K"
        }
        // GPT-4 / GPT-4 Turbo 128K
        if model.contains("gpt-4") {
            return "128K"
        }
        // o1, o3, o4-mini
        if model.contains("o1") || model.contains("o3") || model.contains("o4") {
            return "200K"
        }
        // Grok
        if model.contains("grok") {
            return "128K"
        }
        // Default
        return "128K"
    }

    var footerChangedFilesCount: Int {
        if !gitPanelStore.changedFiles.isEmpty {
            return gitPanelStore.changedFiles.count
        }
        return gitPanelStore.status?.changedFiles ?? 0
    }

    var gitButtonLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(gitPanelStore.isOpen ? DesignSystem.Colors.agentColor : .primary)
            if footerChangedFilesCount > 0 {
                Text("\(footerChangedFilesCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(DesignSystem.Colors.agentColor, in: Capsule())
            }
        }
        .padding(.horizontal, 6)
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
        .disabled(isWorktreeToggleDisabled || wt.isWorktreeActionInFlight)
        .help(worktreeToggleHelpText)
    }

    var totalUsageLabel: some View {
        Text(totalUsageText)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    var footerMessages: some View {
        if let success = wt.worktreeStatusMessage, !success.isEmpty {
            Text(success)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.success)
                .lineLimit(1)
        }
        if let err = wt.worktreeErrorMessage, !err.isEmpty {
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
