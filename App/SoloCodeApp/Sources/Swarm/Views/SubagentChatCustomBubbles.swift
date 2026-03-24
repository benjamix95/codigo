import SwiftUI

/// Custom bubble views unique to sub-agent chats (no equivalent in main chat).
/// The task prompt bubble and result bubble are sub-agent specific.
extension SubagentChatView {

    // MARK: - Task Prompt (user message)

    func taskPromptBubble(text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "person.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.swarmColor)
                Text("TASK ASSEGNATO")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.swarmColor.opacity(0.8))
                    .tracking(0.5)
            }
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.primary.opacity(0.85))
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignSystem.Colors.swarmColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DesignSystem.Colors.swarmColor.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Result (completion summary)

    func resultBubble(text: String, timestamp: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green.opacity(0.7))
                Text("Risultato")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green.opacity(0.7))
                Spacer()
                if let ts = timestamp {
                    Text(ts.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
            }
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.primary.opacity(0.85))
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.green.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.green.opacity(0.12), lineWidth: 0.5)
        )
    }
}
