import XCTest
@testable import CoderIDE

@MainActor
final class AutoCodeReviewRoutingTests: XCTestCase {
    func testAutoCodeReviewRequestLeavesRegularPromptUntouched() {
        let request = makeAutoCodeReviewRequest(
            userText: "Spiegami questa funzione async.",
            coderMode: .agent
        )

        XCTAssertEqual(request.prompt, "Spiegami questa funzione async.")
        XCTAssertEqual(request.selectedModes, [])
        XCTAssertFalse(request.prefersCodeReviewRuntimeProvider)
    }

    func testAutoCodeReviewRequestWrapsSecurityReviewPrompt() {
        let request = makeAutoCodeReviewRequest(
            userText: "Fai una review di sicurezza del diff e cerca vulnerabilità authz.",
            coderMode: .agent
        )

        XCTAssertTrue(request.prefersCodeReviewRuntimeProvider)
        XCTAssertEqual(request.selectedModes, [.standard, .securityAudit])
        XCTAssertTrue(request.prompt.contains("[REVIEW_SCOPE:uncommitted]"))
        XCTAssertTrue(request.prompt.contains("Security focus:"))
        XCTAssertTrue(request.prompt.contains("Additional instructions:"))
    }

    func testAutoCodeReviewRequestWrapsBugHuntPrompt() {
        let request = makeAutoCodeReviewRequest(
            userText: "Fai bug hunt su queste modifiche e cerca regressioni o crash.",
            coderMode: .agent
        )

        XCTAssertTrue(request.prefersCodeReviewRuntimeProvider)
        XCTAssertEqual(request.selectedModes, [.bugFinder])
        XCTAssertTrue(request.prompt.contains("Bug focus:"))
    }

    func testAutoCodeReviewRequestSkipsSlashCommands() {
        let request = makeAutoCodeReviewRequest(
            userText: "/fast\n\nFai una review",
            coderMode: .agent
        )

        XCTAssertEqual(request.prompt, "/fast\n\nFai una review")
        XCTAssertEqual(request.selectedModes, [])
        XCTAssertFalse(request.prefersCodeReviewRuntimeProvider)
    }
}
