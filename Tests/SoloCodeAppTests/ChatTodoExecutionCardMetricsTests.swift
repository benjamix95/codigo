import XCTest
@testable import CoderIDE

final class ChatTodoExecutionCardMetricsTests: XCTestCase {
    func testBuildAggregatesTodoAndFileChangeCounters() {
        let items = [
            TodoItem(title: "Uno", status: .done, isPlanCanonical: true, planOrder: 0),
            TodoItem(title: "Due", status: .pending, isPlanCanonical: true, planOrder: 1),
            TodoItem(title: "Tre", status: .inProgress, isPlanCanonical: true, planOrder: 2),
        ]
        let fileChanges = [
            ToolTraceFileChange(
                eventId: UUID(),
                path: "/tmp/A.swift",
                basename: "A.swift",
                kind: .edited,
                added: 12,
                removed: 3,
                diffPreview: nil,
                rawOutput: nil,
                diffSource: .payload,
                sequence: 1,
                timestamp: .now,
                isRunning: false
            ),
            ToolTraceFileChange(
                eventId: UUID(),
                path: "/tmp/B.swift",
                basename: "B.swift",
                kind: .edited,
                added: 4,
                removed: 7,
                diffPreview: nil,
                rawOutput: nil,
                diffSource: .payload,
                sequence: 2,
                timestamp: .now,
                isRunning: false
            ),
        ]

        let metrics = ChatTodoExecutionCardMetrics.build(items: items, fileChanges: fileChanges)

        XCTAssertEqual(metrics.doneCount, 1)
        XCTAssertEqual(metrics.totalCount, 3)
        XCTAssertEqual(metrics.fileCount, 2)
        XCTAssertEqual(metrics.linesAdded, 16)
        XCTAssertEqual(metrics.linesRemoved, 10)
    }

    func testShouldStartExpandedAlwaysStartsCollapsed() {
        XCTAssertFalse(
            ChatTodoExecutionCardMetrics.shouldStartExpanded(
                items: [TodoItem(title: "In corso", status: .inProgress)]
            )
        )
        XCTAssertFalse(
            ChatTodoExecutionCardMetrics.shouldStartExpanded(
                items: [TodoItem(title: "Bloccato", status: .blocked)]
            )
        )
        XCTAssertFalse(
            ChatTodoExecutionCardMetrics.shouldStartExpanded(
                items: [TodoItem(title: "Fatto", status: .done)]
            )
        )
        XCTAssertFalse(
            ChatTodoExecutionCardMetrics.shouldStartExpanded(
                items: [
                    TodoItem(title: "Analizza", status: .inProgress),
                    TodoItem(title: "Blocco", status: .blocked),
                    TodoItem(title: "Chiudi", status: .done),
                ]
            )
        )
    }
}
