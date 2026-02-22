import XCTest
@testable import CoderIDE

@MainActor
final class ChatStoreMarkerSanitizationTests: XCTestCase {
    func testStripCoderideMarkersRemovesCompleteAndIncompleteMarkers() {
        let input = """
        Prima [CODERIDE:read|path=Sources/A.swift] dopo
        metà [CODERIDE:grep|query=foo
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertFalse(sanitized.contains("CODERIDE"))
        XCTAssertTrue(sanitized.contains("Prima"))
        XCTAssertTrue(sanitized.contains("dopo"))
        XCTAssertTrue(sanitized.contains("metà"))
    }

    func testStripCoderideMarkersHandlesWhitespaceVariant() {
        let input = "x [   CODERIDE : tool_call|name=bash|command=ls ] y"
        let sanitized = ChatStore.stripCoderideMarkers(input)
        XCTAssertEqual(sanitized.trimmingCharacters(in: .whitespacesAndNewlines), "x y")
    }

    func testStripCoderideMarkersRemovesLeakedStructuredPayloads() {
        let input = """
        Planning Italian compliance and inspectione|id=t1|
        title=Mappare struttura progetto e componenti principali|
        status=pending|priority=medium|notes=Identificare entrypoint, moduli|
        files=Package.swift,README.md,Sources|
        Procedo con il task t1.
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertFalse(sanitized.contains("id=t1|"))
        XCTAssertFalse(sanitized.contains("status=pending"))
        XCTAssertFalse(sanitized.contains("priority=medium"))
        XCTAssertFalse(sanitized.contains("files=Package.swift"))
        XCTAssertTrue(sanitized.contains("Procedo con il task t1."))
    }

    func testStripCoderideMarkersRemovesPlanningBugReviewWorkflow() {
        let input = """
        Planning bug review workflow

        Ecco la mia analisi del codice...
        """
        let sanitized = ChatStore.stripCoderideMarkers(input)
        XCTAssertFalse(sanitized.contains("Planning bug review workflow"))
        XCTAssertTrue(sanitized.contains("Ecco la mia analisi"))
    }

    func testStripCoderideMarkersRemovesInlineMarkerPrefixAndKeepsReadableSpacing() {
        let input = """
        Initiating workflow with markers:todo_write|files=README.md,Package.swift|Inizio con una verifica non invasiva del repository.
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertFalse(sanitized.contains("markers:todo_write"))
        XCTAssertFalse(sanitized.contains("files=README.md"))
        XCTAssertTrue(sanitized.contains("Initiating workflow with"))
        XCTAssertTrue(sanitized.contains("Inizio con una verifica"))
        XCTAssertFalse(sanitized.contains("workflow withInizio"))
    }

    func testStripCoderideMarkersRemovesPlanStepInlineMarkerVariant() {
        let input = """
        Procedo markers:plan_step|step_id=1|status=running|poi continuo con l'analisi.
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertFalse(sanitized.contains("plan_step|"))
        XCTAssertFalse(sanitized.contains("step_id=1"))
        XCTAssertFalse(sanitized.contains("status=running"))
        XCTAssertTrue(sanitized.contains("Procedo"))
        XCTAssertTrue(sanitized.contains("poi continuo con l'analisi"))
    }

    func testStripCoderideMarkersKeepsFollowingLinesWhenMarkerIsIncomplete() {
        let input = """
        [CODERIDE:todo_write|id=t1|title=Init
        Risposta utile visibile durante lo streaming.
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertFalse(sanitized.contains("CODERIDE"))
        XCTAssertTrue(sanitized.contains("Risposta utile visibile durante lo streaming."))
    }
}
