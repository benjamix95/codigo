import SwiftUI

struct SubagentSnapshotCardView: View {
    let snapshot: SubagentCardSnapshot

    @State private var isExpanded = false
    @State private var isHovered = false

    var title: String {
        if snapshot.title.isEmpty {
            return SubagentChatCardHelpers.roleDisplayName(from: snapshot.swarmId)
        }
        // Show "DisplayName - RoleType" if role info is available in swarmId
        let role = SubagentChatCardHelpers.roleDisplayName(from: snapshot.swarmId)
        if role != "Subagent" && !snapshot.title.lowercased().contains(role.lowercased()) {
            return "\(snapshot.title) - \(role)"
        }
        return snapshot.title
    }

    var subtitle: String {
        if let warningCount = snapshot.warningCount, warningCount > 0, snapshot.status != .failed {
            return "Done with warnings"
        }
        if let summary = snapshot.summary, !summary.isEmpty { return summary }
        switch snapshot.status {
        case .completed: return "Done"
        case .failed: return "Failed"
        default: return "Idle"
        }
    }

    var statusIcon: String {
        switch snapshot.status {
        case .completed:
            return (snapshot.warningCount ?? 0) > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .running:
            return "circle.dotted"
        case .idle:
            return "circle"
        }
    }

    var statusIconColor: Color {
        switch snapshot.status {
        case .completed:
            return (snapshot.warningCount ?? 0) > 0 ? DesignSystem.Colors.warning : .green.opacity(0.7)
        case .failed:
            return .red.opacity(0.7)
        case .running:
            return .secondary.opacity(0.5)
        case .idle:
            return .secondary.opacity(0.3)
        }
    }

    var body: some View {
        let previewText = snapshotPreviewText
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Group {
                    if snapshot.status == .running {
                        SpinningDottedCircle()
                    } else {
                        Image(systemName: statusIcon)
                            .font(.system(size: 14))
                            .foregroundStyle(statusIconColor)
                    }
                }
                .frame(width: 18, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                if isHovered || isExpanded, previewText != nil {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.quaternary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            // Task prompt section
            if let prompt = snapshot.taskPrompt, !prompt.isEmpty {
                Divider().opacity(0.08).padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TASK")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.6)
                    Text(prompt)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .lineLimit(isExpanded ? nil : 2)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }

            if let preview = previewText, !preview.isEmpty {
                if !isExpanded {
                    Divider().opacity(0.1).padding(.horizontal, 12)
                    Text(preview)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.55))
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                } else {
                    Divider().opacity(0.15).padding(.horizontal, 12)
                    ScrollView {
                        Text(preview)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.primary.opacity(0.7))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(isHovered || isExpanded ? 0.14 : 0.08),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .onTapGesture {
            guard previewText != nil else { return }
            withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
        }
    }

    private var snapshotPreviewText: String? {
        let transcriptPreview = snapshot.transcript?
            .suffix(isExpanded ? 20 : 6)
            .map(\.detail)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if let transcriptPreview, !transcriptPreview.isEmpty {
            return transcriptPreview
        }
        return snapshot.resultPreview
    }
}
