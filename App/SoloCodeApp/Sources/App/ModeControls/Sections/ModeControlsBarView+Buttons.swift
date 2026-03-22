import CoderEngine
import SwiftUI

extension ModeControlsBarView {
    // MARK: - Plan Icon Button (icon-only, far right)

    var planIconButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                planToggleEnabled.toggle()
            }
        } label: {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    planToggleEnabled
                        ? DesignSystem.Colors.planColor : .secondary
                )
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            planToggleEnabled
                                ? DesignSystem.Colors.planColor.opacity(0.14)
                                : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Toggle Plan panel")
    }

    var debugIconButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                debugToggleEnabled.toggle()
            }
        } label: {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    debugToggleEnabled
                        ? DesignSystem.Colors.debugColor : .secondary
                )
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            debugToggleEnabled
                                ? DesignSystem.Colors.debugColor.opacity(0.14)
                                : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Toggle Debug mode")
    }

    var browserIconButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                browserToggleEnabled.toggle()
            }
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    browserToggleEnabled
                        ? DesignSystem.Colors.browserColor : .secondary
                )
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            browserToggleEnabled
                                ? DesignSystem.Colors.browserColor.opacity(0.14)
                                : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Toggle Browser panel")
    }

    var codeReviewIconButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                codeReviewToggleEnabled.toggle()
            }
        } label: {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    codeReviewToggleEnabled
                        ? DesignSystem.Colors.reviewColor : .secondary
                )
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            codeReviewToggleEnabled
                                ? DesignSystem.Colors.reviewColor.opacity(0.14)
                                : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Toggle Code Review panel")
    }

    // MARK: - Swarm Icon Button (icon-only, far right)

    var swarmIconButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                swarmToggleEnabled.toggle()
            }
        } label: {
            Image(systemName: "ant.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    swarmToggleEnabled
                        ? DesignSystem.Colors.swarmColor : .secondary
                )
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            swarmToggleEnabled
                                ? DesignSystem.Colors.swarmColor.opacity(0.14)
                                : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Toggle Swarm panel")
    }

    // MARK: - Delegate to Agent Button

    var delegateAdAgentButton: some View {
        let msg = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastUser =
            chatStore.conversation(for: conversationId)?
            .messages.last(where: { $0.role == .user })?
            .content ?? ""
        let canDelegate =
            (!msg.isEmpty || !lastUser.isEmpty || !attachedImageURLs.isEmpty)
            && !chatStore.isTaskActive(for: conversationId)
        let agentOk = isAnyAgentProviderReady

        return Button {
            onDelegateToAgent()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12))
                Text("Delegate to Agent")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(
                (canDelegate && agentOk)
                    ? DesignSystem.Colors.agentColor : .secondary
            )
        }
        .buttonStyle(.plain)
        .disabled(!canDelegate || !agentOk)
        .help("Switch to Agent and send message (edit files, run commands)")
    }
}
