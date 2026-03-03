import CoderEngine
import SwiftUI

// MARK: - Task Control Bar (Fixed above composer)
/// Compact bar showing timer + pause/resume/stop controls.
/// Pinned between the messages scroll and the composer input.

struct TaskControlBar: View {
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var taskActivityStore: TaskActivityStore
    @ObservedObject var executionController: ExecutionController

    let conversationId: UUID?
    let coderMode: CoderMode
    let debugPhase: DebugFlowPhase
    let isSummarizing: Bool
    let activeModeColor: Color
    let onInterrupt: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)

            if chatStore.isTaskActive(for: conversationId),
               let startDate = chatStore.taskStartDate(for: conversationId) {
                taskTimerBar(startDate: startDate)
            } else if isSummarizing {
                summarizingBanner
            }
        }
    }
}
