import CoderEngine
import SwiftUI

extension ReviewPanelChatBubble {
    func bubbleHeader(
        title: String,
        icon: String,
        color: Color,
        isTrailing: Bool,
        showsProgress: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            if isTrailing {
                Spacer(minLength: 0)
            }
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(color)
            Text(title.uppercased())
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(color.opacity(0.85))
                .tracking(0.6)
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
            }
            if !isTrailing {
                Spacer(minLength: 0)
            }
        }
    }

    var systemBubbleFill: Color {
        switch message.kind {
        case .summary:
            return Color.black.opacity(0.20)
        case .findingMutation:
            return Color.black.opacity(0.18)
        case .statusNote, .plain, .commandInvocation, .reviewRun:
            return Color.black.opacity(0.24)
        }
    }

    var userBubbleFill: AnyShapeStyle {
        switch message.kind {
        case .commandInvocation:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.44),
                        accent.opacity(0.28),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        default:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        accent.opacity(0.82),
                        accent.opacity(0.64),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    var userBubbleBorder: Color {
        switch message.kind {
        case .commandInvocation:
            return accent.opacity(0.34)
        default:
            return accent.opacity(0.18)
        }
    }

    var systemBubbleAccent: Color {
        switch message.kind {
        case .summary:
            return accent
        case .findingMutation:
            return DesignSystem.Colors.info
        case .statusNote, .plain, .commandInvocation, .reviewRun:
            return .secondary
        }
    }

    var systemBubbleFont: Font {
        switch message.kind {
        case .summary:
            return .system(size: 9.5, weight: .medium, design: .monospaced)
        case .findingMutation:
            return .system(size: 9.5, weight: .medium)
        case .statusNote, .plain, .commandInvocation, .reviewRun:
            return .system(size: 9.5)
        }
    }

    var systemBubbleForeground: Color {
        switch message.kind {
        case .summary:
            return accent.opacity(0.96)
        case .findingMutation:
            return DesignSystem.Colors.info
        case .statusNote, .plain, .commandInvocation, .reviewRun:
            return .white.opacity(0.88)
        }
    }

    @ViewBuilder
    var assistantContentBody: some View {
        let sections = message.presentation?.sections
            ?? ReviewPanelChatStructuredContent.sections(for: message)
        if !sections.isEmpty {
            ReviewPanelChatStructuredSectionsView(
                sections: sections,
                accent: accent
            )
        } else {
            Text(message.content)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Color.black.opacity(0.28),
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            DesignSystem.Colors.border.opacity(0.28),
                            lineWidth: 0.5
                        )
                )
        }
    }

    @ViewBuilder
    var systemContentBody: some View {
        let sections = message.presentation?.sections
            ?? ReviewPanelChatStructuredContent.sections(for: message)
        if !sections.isEmpty {
            ReviewPanelChatStructuredSectionsView(
                sections: sections,
                accent: systemBubbleAccent
            )
        } else {
            Text(message.content)
                .font(systemBubbleFont)
                .foregroundStyle(systemBubbleForeground)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var fileTargets: [ReviewPanelChatMessageFileTarget] {
        ReviewPanelChatMessageContext.fileTargets(from: message.content)
    }

    var findingTargets: [ReviewPanelChatFindingTarget] {
        ReviewPanelChatMessageContext.findingTargets(from: message.content)
    }

    var hasActions: Bool {
        !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func actionBar(alignment: HorizontalAlignment) -> some View {
        let targets = fileTargets
        return VStack(alignment: alignment, spacing: 4) {
            if hasActions {
                HStack(spacing: 6) {
                    Button {
                        ReviewPanelChatMessageContext.copyToPasteboard(message.content)
                    } label: {
                        actionChip("Copy", systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)

                    ForEach(targets) { target in
                        Button {
                            if let onOpenFileAtLocation {
                                onOpenFileAtLocation(target.path, target.line)
                            } else {
                                onOpenFile?(target.path)
                            }
                        } label: {
                            actionChip(target.displayLabel, systemName: "arrow.up.forward.app")
                        }
                        .buttonStyle(.plain)
                        .disabled(onOpenFileAtLocation == nil && onOpenFile == nil)
                    }

                    ForEach(findingTargets) { target in
                        Button {
                            onSelectFinding?(target.findingId)
                        } label: {
                            actionChip(target.displayLabel, systemName: "scope")
                        }
                        .buttonStyle(.plain)
                        .disabled(onSelectFinding == nil)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    func actionChip(_ text: String, systemName: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 7, weight: .semibold))
            Text(text)
                .font(.system(size: 8.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            Capsule()
                .strokeBorder(DesignSystem.Colors.border.opacity(0.18), lineWidth: 0.5)
        )
    }
}
