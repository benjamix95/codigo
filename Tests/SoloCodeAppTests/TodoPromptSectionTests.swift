import XCTest
@testable import CoderIDE

final class TodoPromptSectionTests: XCTestCase {
    func testCurrentTodoPromptSectionTextPreservesIncomingSequence() {
        let text = currentTodoPromptSectionText(
            for: [
                TodoItem(title: "Definire scope", status: .done),
                TodoItem(title: "Scansionare servizi runtime", status: .inProgress),
                TodoItem(title: "Doc Writer", status: .pending),
            ]
        )

        let lines = text
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("- [") }

        XCTAssertEqual(
            lines,
            [
                "- [x] Definire scope (done)",
                "- [ ] Scansionare servizi runtime (in_progress)",
                "- [ ] Doc Writer (pending)",
            ]
        )
    }
}
