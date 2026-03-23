import XCTest
@testable import CoderIDE

final class ToolTraceFileChangeMapperTests: XCTestCase {
    func testMapperUsesPayloadChangeTypeAndCounters() {
        let event = makeEvent(
            title: "Edit • file",
            payload: [
                "path": "App/SoloCodeApp/Sources/File.swift",
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
                "path": "App/SoloCodeApp/Sources/NewFeature.swift",
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
                "path": "App/SoloCodeApp/Sources/Obsolete.swift",
            ]
        )

        let mapped = ToolTraceFileChangeMapper.from(event: event)

        XCTAssertEqual(mapped?.kind, .deleted)
    }

    func testCollectPrefersCompletedStateOverRunningDuplicate() {
        let basePath = "App/SoloCodeApp/Sources/MessageToolTraceView.swift"
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

    func testMapperAcceptsStrReplaceEventType() {
        let event = makeEvent(
            type: "str_replace",
            title: "Edited Config.swift",
            payload: [
                "path": "App/SoloCodeApp/Sources/Config.swift",
                "tool": "str_replace",
                "diffPreview": "@@ -1 +1 @@\n-let debug = false\n+let debug = true",
            ]
        )

        let mapped = ToolTraceFileChangeMapper.from(event: event)

        XCTAssertNotNil(mapped)
        XCTAssertEqual(mapped?.path, "App/SoloCodeApp/Sources/Config.swift")
        XCTAssertEqual(mapped?.added, 1)
        XCTAssertEqual(mapped?.removed, 1)
    }

    func testMapperInfersCountersFromDiffWhenPayloadCountsMissing() {
        let event = makeEvent(
            title: "Edited Sample.swift",
            payload: [
                "path": "App/SoloCodeApp/Sources/Sample.swift",
                "diffPreview": """
                --- old
                +++ new
                @@ -1,2 +1,2 @@
                -let a = 1
                +let a = 2
                +let b = 3
                """,
            ]
        )

        let mapped = ToolTraceFileChangeMapper.from(event: event)

        XCTAssertEqual(mapped?.added, 2)
        XCTAssertEqual(mapped?.removed, 1)
        XCTAssertEqual(mapped?.diffSource, .payload)
    }

    func testMapperMarksGitFallbackDiffSourceAsDerived() {
        let event = makeEvent(
            title: "Edited Derived.swift",
            payload: [
                "path": "App/SoloCodeApp/Sources/Derived.swift",
                "linesAdded": "4",
                "linesRemoved": "1",
                "diff_source": "git_head_fallback",
                "diffPreview": "@@ -1 +1 @@\n-old\n+new",
            ]
        )

        let mapped = ToolTraceFileChangeMapper.from(event: event)

        XCTAssertEqual(mapped?.diffSource, .gitFallback)
    }

    func testMapperMarksUnknownDiffSourceWhenCountersAndDiffAreMissing() {
        let event = makeEvent(
            title: "Edited Unknown.swift",
            payload: [
                "path": "App/SoloCodeApp/Sources/Unknown.swift",
            ]
        )

        let mapped = ToolTraceFileChangeMapper.from(event: event)

        XCTAssertEqual(mapped?.diffSource, .unknown)
    }

    func testMapperTreatsApplyPatchAsFileChangeEvenWhenTypeIsCommandExecution() {
        let event = makeEvent(
            type: "command_execution",
            title: "apply_patch",
            payload: [
                "tool": "functions.apply_patch",
                "path": "App/SoloCodeApp/Sources/Trace.swift",
                "patch": """
                @@ -1 +1 @@
                -let old = 1
                +let old = 2
                """,
            ]
        )

        let mapped = ToolTraceFileChangeMapper.from(event: event)

        XCTAssertNotNil(mapped)
        XCTAssertEqual(mapped?.path, "App/SoloCodeApp/Sources/Trace.swift")
        XCTAssertEqual(mapped?.added, 1)
        XCTAssertEqual(mapped?.removed, 1)
    }

    func testStrReplacePayloadWithExplicitLineCountsUsesPayloadValues() {
        let event = makeEvent(
            type: "str_replace",
            title: "str_replace DesignSystem+Tokens.swift:42",
            payload: [
                "path": "App/SoloCodeApp/Sources/App/DesignSystem/DesignSystem+Tokens.swift",
                "tool": "str_replace",
                "linesAdded": "5",
                "linesRemoved": "3",
                "detail": "Replaced at line 42 (3 lines → 5 lines)",
                "diffPreview": "- let old1 = 1\n- let old2 = 2\n- let old3 = 3\n+ let new1 = 1\n+ let new2 = 2\n+ let new3 = 3\n+ let new4 = 4\n+ let new5 = 5",
            ]
        )

        let mapped = ToolTraceFileChangeMapper.from(event: event)

        XCTAssertNotNil(mapped)
        XCTAssertEqual(mapped?.added, 5, "str_replace deve usare linesAdded esplicito dal payload")
        XCTAssertEqual(mapped?.removed, 3, "str_replace deve usare linesRemoved esplicito dal payload")
        XCTAssertEqual(mapped?.diffSource, .payload)
    }

    func testCreateFilePayloadIncludesZeroLinesRemoved() {
        let event = makeEvent(
            type: "create_file",
            title: "Created NewFile.swift",
            payload: [
                "path": "App/SoloCodeApp/Sources/NewFile.swift",
                "tool": "create_file",
                "linesAdded": "25",
                "linesRemoved": "0",
                "detail": "Created 25 lines",
            ]
        )

        let mapped = ToolTraceFileChangeMapper.from(event: event)

        XCTAssertNotNil(mapped)
        XCTAssertEqual(mapped?.kind, .created)
        XCTAssertEqual(mapped?.added, 25)
        XCTAssertEqual(mapped?.removed, 0)
        XCTAssertEqual(mapped?.diffSource, .payload)
    }

    func testMapperUsesPathAndDiffHeuristicForUntypedFileChanges() {
        let event = makeEvent(
            type: "command_execution",
            title: "unknown",
            payload: [
                "path": "App/SoloCodeApp/Sources/Unknown.swift",
                "diffPreview": "-a\n+b",
            ]
        )

        let mapped = ToolTraceFileChangeMapper.from(event: event)

        XCTAssertNotNil(mapped)
        XCTAssertEqual(mapped?.basename, "Unknown.swift")
        XCTAssertEqual(mapped?.added, 1)
        XCTAssertEqual(mapped?.removed, 1)
    }

    private func makeEvent(
        type: String = "file_change",
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
            type: type,
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
