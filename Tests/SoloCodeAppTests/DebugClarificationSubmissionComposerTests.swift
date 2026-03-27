import XCTest
@testable import CoderIDE

final class DebugClarificationSubmissionComposerTests: XCTestCase {
    func testComposeMasksChatDisplayTextButKeepsAgentPayload() {
        let parsed = DebugClarificationPromptParser.Parsed(
            preamble: "Quando succede?",
            options: [
                .init(id: "a", letter: "a", text: "Solo in streaming"),
                .init(id: "b", letter: "b", text: "Sempre"),
            ]
        )

        let submission = DebugClarificationSubmissionComposer.compose(
            parsed: parsed,
            selectedLetter: "a",
            customNotes: "Succede con Claude su stream lungo."
        )

        XCTAssertEqual(submission?.chatDisplayText, "altro")
        XCTAssertTrue(submission?.agentPrompt.contains("Scelta: (a) Solo in streaming") == true)
        XCTAssertTrue(submission?.agentPrompt.contains("Dettagli / contesto: Succede con Claude su stream lungo.") == true)
    }

    func testComposeReturnsNilWithoutSelectionOrCustomText() {
        let parsed = DebugClarificationPromptParser.Parsed(
            preamble: "Domanda libera",
            options: []
        )

        let submission = DebugClarificationSubmissionComposer.compose(
            parsed: parsed,
            selectedLetter: nil,
            customNotes: "   "
        )

        XCTAssertNil(submission)
    }
}
