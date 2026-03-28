import XCTest
@testable import CoderIDE

final class InlineToolTraceEventViewDisplayTests: XCTestCase {
    func testPrimaryTitleUsesFileChangePresentationTitle() {
        let event = ToolTraceEvent(
            sequence: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            providerId: "codex-cli",
            conversationId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            assistantMessageId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            type: "command_execution",
            title: "apply_patch",
            detail: nil,
            payload: [
                "tool": "functions.apply_patch",
                "path": "App/SoloCodeApp/Sources/Trace.swift",
                "patch": "@@ -1 +1 @@\n-old\n+new",
            ],
            phase: .executing,
            isRunning: false,
            groupId: nil,
            rawKind: "raw"
        )

        let view = InlineToolTraceEventView(
            event: event,
            workspaceHints: [],
            onOpenFile: { _ in }
        )

        XCTAssertEqual(view.primaryTitle(), "Edited Trace.swift")
    }
}
