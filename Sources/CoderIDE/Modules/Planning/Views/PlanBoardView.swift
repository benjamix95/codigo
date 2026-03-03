import SwiftUI

struct PlanBoardView: View {
    let board: PlanBoard
    let onSelectOption: (PlanOption) -> Void

    private var progress: Double {
        guard !board.steps.isEmpty else { return 0 }
        let done = Double(board.steps.filter { $0.status == .done }.count)
        return done / Double(board.steps.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Built Plan")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(board.goal)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)

            ProgressView(value: progress)
                .progressViewStyle(.linear)

            if !board.options.isEmpty {
                Text("Options")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                ForEach(board.options.prefix(3)) { option in
                    Button {
                        onSelectOption(option)
                    } label: {
                        HStack {
                            Text("\(option.id). \(option.title)")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            if normalizedForComparison(board.chosenPath) == normalizedForComparison(option.fullText) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Execution Steps")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            ForEach(board.steps.prefix(8)) { step in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: step.status))
                            .frame(width: 7, height: 7)
                        Text(step.title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                        Text(step.status.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    if !step.dependsOn.isEmpty || !step.linkedFiles.isEmpty {
                        HStack(spacing: 8) {
                            if !step.dependsOn.isEmpty {
                                Text("deps: \(step.dependsOn.count)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            if !step.linkedFiles.isEmpty {
                                Text("files: \(step.linkedFiles.count)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func normalizedForComparison(_ text: String?) -> String {
        (text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func color(for status: PlanStepStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .running: return .orange
        case .done: return .green
        case .failed: return .red
        }
    }
}
