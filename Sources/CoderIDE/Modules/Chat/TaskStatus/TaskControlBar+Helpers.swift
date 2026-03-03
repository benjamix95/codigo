import CoderEngine
import SwiftUI

extension TaskControlBar {
    @ViewBuilder
    internal func taskTimerBar(startDate: Date) -> some View {
        TimelineView(.periodic(from: startDate, by: 1.0)) { (context: TimelineViewDefaultContext) in
            let elapsed = Int(context.date.timeIntervalSince(startDate))
            taskTimerView(elapsed: elapsed)
        }
    }

    @ViewBuilder
    private func taskTimerView(elapsed: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(activeModeColor)
                .frame(width: 6, height: 6)
                .modifier(PulseModifier())

            Text(formatElapsed(elapsed))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)

            if let lastActivity = TaskActivityStore.lastConcreteNonSwarmActivity(
                in: taskActivityStore.activities
            ) {
                Text("•")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
                Image(systemName: phaseIcon(lastActivity.phase))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(phaseColor(lastActivity.phase))
                Text(lastActivity.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textShimmer(active: lastActivity.isRunning)
            }

            if taskActivityStore.activeOperationsCount > 0 {
                Text("(\(taskActivityStore.activeOperationsCount) op)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            taskControlButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
    }

    @ViewBuilder
    internal var taskControlButtons: some View {
        let scope = executionScope

        HStack(spacing: 6) {
            if executionController.runState == .paused {
                Button {
                    executionController.resume(scope: scope)
                    taskActivityStore.markResumed()
                    taskActivityStore.addActivity(
                        TaskActivity(
                            type: "process_resumed",
                            title: "Process resumed",
                            detail: "Execution resumed by user",
                            payload: [:],
                            phase: .executing,
                            isRunning: true
                        )
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                        Text("Resume")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    executionController.pause(scope: scope)
                    taskActivityStore.markPaused()
                    taskActivityStore.addActivity(
                        TaskActivity(
                            type: "process_paused",
                            title: "Process paused",
                            detail: "Execution paused by user",
                            payload: [:],
                            phase: .planning,
                            isRunning: false
                        )
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9))
                        Text("Pause")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                onInterrupt()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                    Text("Stop")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
    }

    internal var summarizingBanner: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Compressing context…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    internal var executionScope: ExecutionScope {
        switch coderMode {
        case .codeReviewMultiSwarm:
            return .review
        case .plan:
            return .plan
        default:
            return .agent
        }
    }

    internal func formatElapsed(_ s: Int) -> String {
        let m = s / 60
        let sec = s % 60
        return m > 0 ? String(format: "%d:%02d", m, sec) : "\(sec)s"
    }

    internal func phaseIcon(_ phase: ActivityPhase) -> String {
        switch phase {
        case .executing: return "terminal"
        case .editing: return "pencil"
        case .searching: return "magnifyingglass"
        case .planning: return "list.bullet.rectangle"
        case .thinking: return "gearshape"
        }
    }

    internal func phaseColor(_ phase: ActivityPhase) -> Color {
        switch phase {
        case .executing:
            return .secondary
        case .editing:
            return .secondary
        case .searching:
            return .secondary
        case .planning:
            return .secondary
        case .thinking:
            return .secondary
        }
    }
}
