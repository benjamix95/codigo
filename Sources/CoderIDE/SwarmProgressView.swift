import SwiftUI

struct SwarmProgressView: View {
    @ObservedObject var store: SwarmProgressStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Swarm \(store.steps.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            ForEach(store.steps) { step in
                SwarmStepRow(step: step)
            }
        }
        .padding(8)
        .frame(maxHeight: 140)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct SwarmStepRow: View {
    let step: SwarmStep

    private var statusIcon: String {
        switch step.status {
        case .completed: return "checkmark.circle.fill"
        case .inProgress: return "arrow.right.circle"
        case .pending: return "circle"
        }
    }

    private var statusColor: Color {
        switch step.status {
        case .completed: return .green
        case .inProgress: return .orange
        case .pending: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: statusIcon)
                .font(.subheadline)
                .foregroundStyle(statusColor)

            Text(step.name)
                .font(step.status == .inProgress ? .subheadline.weight(.medium) : .subheadline)
                .foregroundStyle(step.status == .completed ? .secondary : .primary)
                .strikethrough(step.status == .completed)
                .opacity(step.status == .completed ? 0.6 : 1)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}
