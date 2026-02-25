import XCTest
@testable import CoderIDE

final class ToolTraceFileChangeMapperTests: XCTestCase {
    func testMapperUsesPayloadChangeTypeAndCounters() {
        let event = makeEvent(
            title: "Edit • file",
            payload: [
                "path": "Sources/CoderIDE/File.swift",
                "change_type": "create",
                "linesAdded": "12",
                "linesRemoved": "2",
                "diffPreview": "@@ -1 +1 @@",
            ]
        )

        let mapped = ToolTraceFileChangeMapper.from(event: event)

        XCTAssertEqual(mapped?.kind, .created)
        XCTAssertEqual(mapped?.basename, "File.swift")
        XCTAssertEqual(mapped?.added, 12)
        XCTAssertEqual(mapped?.removed, 2)
        XCTAssertEqual(mapped?.diffPreview, "@@ -1 +1 @@")
    }

    func testMapperTreatsCreateFileToolAsCreated() {
        let event = makeEvent(
            title: "Edited file",
            payload: [
                "path": "Sources/CoderIDE/NewFeature.swift",
                "tool": "create_file",
            ]
        )

        let mapped = ToolTraceFileChangeMapper.from(event: event)

        XCTAssertEqual(mapped?.kind, .created)
        XCTAssertEqual(mapped?.basename, "NewFeature.swift")
    }

    func testMapperFallsBackToTitlePrefixForDeleted() {
        let event = makeEvent(
            title: "Deleted Obsolete.swift",
            payload: [
                "path": "Sources/CoderIDE/Obsolete.swift",
            ]
        )

        let mapped = ToolTraceFileChangeMapper.from(event: event)

        XCTAssertEqual(mapped?.kind, .deleted)
    }

    func testCollectPrefersCompletedStateOverRunningDuplicate() {
        let basePath = "Sources/CoderIDE/MessageToolTraceView.swift"
        let running = makeEvent(
            title: "Edited MessageToolTraceView.swift",
            payload: ["path": basePath, "linesAdded": "1"],
            sequence: 1,
            isRunning: true
        )
        let completed = makeEvent(
            title: "Edited MessageToolTraceView.swift",
            payload: ["path": basePath, "linesAdded": "8", "linesRemoved": "2"],
            sequence: 2,
            isRunning: false
        )

        let changes = ToolTraceFileChangeMapper.collect(from: [running, completed])

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.added, 8)
        XCTAssertEqual(changes.first?.removed, 2)
        XCTAssertEqual(changes.first?.isRunning, false)
    }

    private func makeEvent(
        title: String,
        payload: [String: String],
        sequence: Int = 1,
        isRunning: Bool = false
    ) -> ToolTraceEvent {
        ToolTraceEvent(
            sequence: sequence,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            providerId: "codex-cli",
            conversationId: UUID(),
            assistantMessageId: UUID(),
            type: "file_change",
            title: title,
            detail: payload["path"],
            payload: payload,
            phase: .editing,
            isRunning: isRunning,
            groupId: nil,
            rawKind: "item.completed"
        )
    }
}
