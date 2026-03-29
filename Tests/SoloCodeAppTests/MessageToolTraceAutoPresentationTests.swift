import XCTest
@testable import CoderIDE

final class MessageToolTraceAutoPresentationTests: XCTestCase {
    func testReconcileDoesNotAutoExpandWhileRunning() {
        let current = MessageToolTraceAutoPresentationState(
            isExpanded: false,
            didAutoCompactAfterCompletion: true,
            userDidManuallyExpand: false,
            userDidManuallyCollapseWhileRunning: false,
            isCompactDiffExpanded: false,
            isCompactDiffLoading: false
        )

        let next = MessageToolTraceAutoPresentation.reconcile(
            current: current,
            hasRunningEvent: true,
            hasOrderedEvents: true
        )

        XCTAssertFalse(next.isExpanded)
        XCTAssertFalse(next.didAutoCompactAfterCompletion)
    }

    func testReconcileAutoCompactsOnceAfterCompletion() {
        let current = MessageToolTraceAutoPresentationState(
            isExpanded: true,
            didAutoCompactAfterCompletion: false,
            userDidManuallyExpand: true,
            userDidManuallyCollapseWhileRunning: true,
            isCompactDiffExpanded: true,
            isCompactDiffLoading: true
        )

        let next = MessageToolTraceAutoPresentation.reconcile(
            current: current,
            hasRunningEvent: false,
            hasOrderedEvents: true
        )

        XCTAssertFalse(next.isExpanded)
        XCTAssertTrue(next.didAutoCompactAfterCompletion)
        XCTAssertFalse(next.userDidManuallyExpand)
        XCTAssertFalse(next.userDidManuallyCollapseWhileRunning)
        XCTAssertFalse(next.isCompactDiffExpanded)
        XCTAssertFalse(next.isCompactDiffLoading)
    }

    func testCompactDiffNeverAutoExpands() {
        XCTAssertFalse(
            MessageToolTraceAutoPresentation.shouldAutoExpandCompactDiff(
                isTraceExpanded: true,
                hasPreview: true
            )
        )
    }

    func testEventsChangeTokenChangesWhenMiddleEventCompletes() {
        let runningEvents = [
            makeEvent(sequence: 1, toolUseId: "read-1", isRunning: false, status: "completed"),
            makeEvent(sequence: 2, toolUseId: "bash-1", isRunning: true, status: "started"),
            makeEvent(sequence: 3, toolUseId: "edit-1", isRunning: false, status: "completed"),
        ]
        let completedEvents = [
            makeEvent(sequence: 1, toolUseId: "read-1", isRunning: false, status: "completed"),
            makeEvent(sequence: 2, toolUseId: "bash-1", isRunning: false, status: "completed"),
            makeEvent(sequence: 3, toolUseId: "edit-1", isRunning: false, status: "completed"),
        ]

        let runningView = MessageToolTraceView(events: runningEvents, workspaceHints: [], onOpenFile: { _ in })
        let completedView = MessageToolTraceView(events: completedEvents, workspaceHints: [], onOpenFile: { _ in })

        XCTAssertNotEqual(runningView.eventsChangeToken, completedView.eventsChangeToken)
    }

    private func makeEvent(
        sequence: Int,
        toolUseId: String,
        isRunning: Bool,
        status: String
    ) -> ToolTraceEvent {
        ToolTraceEvent(
            sequence: sequence,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            providerId: "codex-cli",
            conversationId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            assistantMessageId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            type: "command_execution",
            title: "bash",
            detail: nil,
            payload: [
                "id": toolUseId,
                "status": status,
                "command": "echo \(sequence)",
            ],
            phase: .executing,
            isRunning: isRunning,
            groupId: nil,
            rawKind: "raw"
        )
    }
}
