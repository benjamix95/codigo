import SwiftUI

extension DebugPanelView {
    // MARK: - Streaming Banner

    var streamingBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .tint(accent)
                .padding(.top, 2)

            Text(debugStore.streamingContent)
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(accent.opacity(0.03))
    }

    // MARK: - Question Cards

    var questionCards: some View {
        Group {
            if debugStore.isAwaitingUserClarification {
                clarificationResponseCard(
                    parsed: DebugClarificationPromptParser.parse(debugStore.clarificationQuestions)
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(accent.opacity(0.1))
                                .frame(width: 26, height: 26)
                            Image(systemName: "questionmark.bubble.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(accent)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Agent needs your input")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            Text(phaseClarificationSubtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                    }

                    Text(debugStore.clarificationQuestions)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(accent.opacity(0.12), lineWidth: 0.5)
                        )
                }
                .padding(12)
                .background(accent.opacity(0.03))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    var phaseClarificationSubtitle: String {
        switch debugStore.phase {
        case .describing:    return "Help the agent understand the issue"
        case .reproducing:   return "Steps to reproduce the bug"
        case .fixing:        return "Clarification about the fix approach"
        case .instrumenting: return "Details about code behavior"
        case .verifying:     return "Confirm verification results"
        default:             return "Please answer the question below"
        }
    }

    // MARK: - Phase Action Area

    @ViewBuilder
    var phaseActionArea: some View {
        if debugStore.phase == .reproducing {
            divider
            reproduceAction
        }

        if debugStore.phase == .verifying {
            divider
            verifyAction
        }

        if debugStore.phase == .resolved {
            divider
            resolutionBanner
        }
    }

    var reproduceAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DesignSystem.Colors.warning.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.warning)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Reproduce the bug")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("Follow the steps below, then click Proceed")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            // Show reproduction steps from clarification questions
            if !debugStore.clarificationQuestions.isEmpty {
                Text(debugStore.clarificationQuestions)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignSystem.Colors.warning.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DesignSystem.Colors.warning.opacity(0.18), lineWidth: 0.5)
                    )
            }

            // Show collected runtime logs count
            let runtimeCount = debugStore.runtimeLogs.count
            if runtimeCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 9))
                    Text("\(runtimeCount) runtime log\(runtimeCount == 1 ? "" : "s") collected")
                        .font(.system(size: 10))
                }
                .foregroundStyle(accent.opacity(0.7))
            }

            Text("The agent will analyze collected logs and propose fix hypotheses.")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Button {
                debugStore.isAwaitingReproduceConfirmation = false
                debugStore.userConfirmedReproduce = true
                debugStore.clarificationQuestions = ""
                onProceed()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                    Text("Proceed")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(DesignSystem.Colors.warning.opacity(0.04))
    }

    var verifyAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DesignSystem.Colors.success.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.success)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Verification")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("Click 'Mark Fixed' to remove all debug markers and resolve")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            // Show verification instructions from clarification questions
            if !debugStore.clarificationQuestions.isEmpty {
                Text(debugStore.clarificationQuestions)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignSystem.Colors.success.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DesignSystem.Colors.success.opacity(0.18), lineWidth: 0.5)
                    )
            }

            HStack(spacing: 10) {
                Button(action: onFixed) {
                    HStack(spacing: 6) {
                        if debugStore.awaitingDebugClean {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                        }
                        Text(debugStore.awaitingDebugClean ? "Cleaning…" : "Mark Fixed")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        debugStore.awaitingDebugClean
                        ? DesignSystem.Colors.warning
                        : DesignSystem.Colors.success,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
                .disabled(debugStore.awaitingDebugClean)
            }

            let totalFiles = Set(
                debugStore.debugMarkers.map(\.filePath)
                + debugStore.instrumentationPoints.map(\.filePath)
            ).count
            if totalFiles > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.system(size: 9))
                    Text("Will clean \(totalFiles) file\(totalFiles == 1 ? "" : "s")")
                        .font(.system(size: 10))
                }
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.success.opacity(0.04))
    }

    var resolutionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.success.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DesignSystem.Colors.success)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Resolved")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.success)

                    if !debugStore.resolutionSummary.isEmpty {
                        Text(debugStore.resolutionSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .lineLimit(3)
                    }
                }

                Spacer()
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.success.opacity(0.04))
    }
}
