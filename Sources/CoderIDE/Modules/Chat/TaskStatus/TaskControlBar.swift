import CoderEngine
import SwiftUI

// MARK: - Task Control Bar (Fixed above composer)
/// Compact bar showing timer + pause/resume/stop controls.
/// Pinned between the messages scroll and the composer input.

struct TaskControlBar: View {
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var taskActivityStore: TaskActivityStore
    @ObservedObject var executionController: ExecutionController
    @ObservedObject var pipelineService: PipelineIntegrationService

    let conversationId: UUID?
    let coderMode: CoderMode
    let debugPhase: DebugFlowPhase
    let isSummarizing: Bool
    let activeModeColor: Color
    let onInterrupt: () -> Void

    private var pipelineSnapshot: PipelineConversationSnapshot? {
        pipelineService.snapshot(for: conversationId)
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)

            if let snapshot = pipelineSnapshot, snapshot.isRunning {
                pipelineStatusBar(snapshot: snapshot)
            } else if chatStore.isTaskActive(for: conversationId),
               let startDate = chatStore.taskStartDate(for: conversationId) {
                taskTimerBar(startDate: startDate)
            } else if isSummarizing {
                summarizingBanner
            }
        }
    }

    @ViewBuilder
    private func pipelineStatusBar(snapshot: PipelineConversationSnapshot) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(snapshot.circuitBreakerActive ? Color.orange : activeModeColor)
                .frame(width: 6, height: 6)
                .modifier(PulseModifier())

            Text("Pipeline")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)

            Text("\(snapshot.completedTasks)/\(snapshot.totalTasks)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)

            Text(snapshot.jobState.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            if snapshot.circuitBreakerActive {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            Spacer()

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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
    }
}
