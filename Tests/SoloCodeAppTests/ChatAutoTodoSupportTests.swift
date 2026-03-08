import XCTest
@testable import CoderIDE

final class ChatAutoTodoSupportTests: XCTestCase {
    func testAutoTodoRuntimeNotesReflectTrackingLifecycle() {
        XCTAssertEqual(
            autoTodoRuntimeNotes(operationCount: 0),
            "Auto-generated: execution started before an explicit todo was created."
        )
        XCTAssertEqual(
            autoTodoRuntimeNotes(operationCount: 1),
            "Auto-generated: tracking live operational activity until the agent publishes an explicit todo."
        )
        XCTAssertEqual(
            autoTodoRuntimeNotes(operationCount: 3),
            "Auto-generated: tracking 3 operational steps until the agent publishes an explicit todo."
        )
    }

    func testPreferredAutoTodoTitleUpgradesGenericFallback() {
        XCTAssertEqual(
            preferredAutoTodoTitle(
                currentTitle: autoTodoGenericFallbackTitle,
                candidateTitle: "Complete changes on ChatPanelView.swift"
            ),
            "Complete changes on ChatPanelView.swift"
        )
        XCTAssertEqual(
            preferredAutoTodoTitle(
                currentTitle: "Inspect relevant files",
                candidateTitle: "Complete changes on ChatPanelView.swift"
            ),
            "Inspect relevant files"
        )
    }

    func testPreferredAutoTodoActiveFormPrefersImmediateLabelThenCurrentThenTitle() {
        XCTAssertEqual(
            preferredAutoTodoActiveForm(
                currentActiveForm: "",
                immediateLabel: "Editing code",
                title: "Apply requested code changes"
            ),
            "Editing code"
        )
        XCTAssertEqual(
            preferredAutoTodoActiveForm(
                currentActiveForm: "Searching codebase",
                immediateLabel: "",
                title: "Inspect implementation details"
            ),
            "Searching codebase"
        )
        XCTAssertEqual(
            preferredAutoTodoActiveForm(
                currentActiveForm: "",
                immediateLabel: "",
                title: "Inspect implementation details"
            ),
            "Inspect implementation details"
        )
    }

    func testMergedAutoTodoLinkedFilesDeduplicatesAndSorts() {
        XCTAssertEqual(
            mergedAutoTodoLinkedFiles(
                existing: ["Sources/B.swift", "Sources/A.swift"],
                incoming: ["Sources/A.swift", "Tests/Z.swift"]
            ),
            ["Sources/A.swift", "Sources/B.swift", "Tests/Z.swift"]
        )
    }
}
