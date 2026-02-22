import XCTest
@testable import CoderIDE

@MainActor
final class AssistantTimelineRenderPolicyTests: XCTestCase {
    func testLoadingWithFallbackAndWhitespacePendingShowsFallbackOnly() {
        let policy = assistantTimelineRenderPolicy(
            fallbackContent: "Risposta live",
            pendingChunk: "   \n\t",
            isLoading: true
        )

        XCTAssertTrue(policy.showFallback)
        XCTAssertFalse(policy.showPending)
    }

    func testLoadingWithFallbackAndPendingTextPrioritizesFallback() {
        let policy = assistantTimelineRenderPolicy(
            fallbackContent: "Risposta completa",
            pendingChunk: "chunk pendente",
            isLoading: true
        )

        XCTAssertTrue(policy.showFallback)
        XCTAssertFalse(policy.showPending)
    }

    func testLoadingWithoutFallbackAndWithPendingShowsPending() {
        let policy = assistantTimelineRenderPolicy(
            fallbackContent: "   ",
            pendingChunk: "chunk pendente",
            isLoading: true
        )

        XCTAssertFalse(policy.showFallback)
        XCTAssertTrue(policy.showPending)
    }

    func testLoadingWithoutFallbackAndPendingShowsNothing() {
        let policy = assistantTimelineRenderPolicy(
            fallbackContent: " \n ",
            pendingChunk: " \t ",
            isLoading: true
        )

        XCTAssertFalse(policy.showFallback)
        XCTAssertFalse(policy.showPending)
    }

    func testRenderableAssistantTextStripsCoderideMarkersAndKeepsUserText() {
        let raw = """
        [CODERIDE:show_task_panel]
        Risposta utile per l'utente.
        """

        let rendered = renderableAssistantText(raw)

        XCTAssertFalse(rendered.contains("CODERIDE"))
        XCTAssertTrue(rendered.contains("Risposta utile per l'utente."))
        XCTAssertFalse(rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testNonLoadingPolicyDoesNotForceFallback() {
        let policy = assistantTimelineRenderPolicy(
            fallbackContent: "Risposta finale",
            pendingChunk: nil,
            isLoading: false
        )

        XCTAssertFalse(policy.showFallback)
    }
}
