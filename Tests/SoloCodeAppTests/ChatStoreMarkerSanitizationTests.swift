import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class ChatStoreMarkerSanitizationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", reviewCoreLibraryPath(from: #filePath), 1)
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
        ReviewCoreBridge.resetForTests()
    }

    override func tearDown() {
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
        ReviewCoreBridge.resetForTests()
        super.tearDown()
    }

    private func withSwiftReviewCoreFallback<T>(_ body: () throws -> T) rethrows -> T {
        let original = getenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT").map { String(cString: $0) }
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
        defer {
            if let original {
                setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", original, 1)
            } else {
                unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            }
            ReviewCoreBridge.resetForTests()
        }
        return try body()
    }

    func testStripCoderideMarkersRemovesCompleteAndIncompleteMarkers() {
        let input = """
        Before [CODERIDE:read|path=Sources/A.swift] after
        half [CODERIDE:grep|query=foo
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertFalse(sanitized.contains("CODERIDE"))
        XCTAssertTrue(sanitized.contains("Before"))
        XCTAssertTrue(sanitized.contains("after"))
        XCTAssertTrue(sanitized.contains("half"))
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
        Proceeding with task t1.
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertFalse(sanitized.contains("id=t1|"))
        XCTAssertFalse(sanitized.contains("status=pending"))
        XCTAssertFalse(sanitized.contains("priority=medium"))
        XCTAssertFalse(sanitized.contains("files=Package.swift"))
        XCTAssertTrue(sanitized.contains("Proceeding with task t1."))
    }

    func testStripCoderideMarkersRemovesPlanningBugReviewWorkflow() {
        let input = """
        Planning bug review workflow

        Here is my analysis of the code...
        """
        let sanitized = ChatStore.stripCoderideMarkers(input)
        XCTAssertFalse(sanitized.contains("Planning bug review workflow"))
        XCTAssertTrue(sanitized.contains("Here is my analysis"))
    }

    func testStripCoderideMarkersRemovesInlineMarkerPrefixAndKeepsReadableSpacing() {
        let input = """
        Initiating workflow with markers:todo_write|files=README.md,Package.swift|Starting with a non-invasive repository verification.
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertFalse(sanitized.contains("markers:todo_write"))
        XCTAssertFalse(sanitized.contains("files=README.md"))
        XCTAssertTrue(sanitized.contains("Initiating workflow with"))
        XCTAssertTrue(sanitized.contains("Starting with a"))
        XCTAssertFalse(sanitized.contains("workflow withInizio"))
    }

    func testStripCoderideMarkersRemovesPlanStepInlineMarkerVariant() {
        let input = """
        Proceeding markers:plan_step|step_id=1|status=running|then continuing with the analysis.
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertFalse(sanitized.contains("plan_step|"))
        XCTAssertFalse(sanitized.contains("step_id=1"))
        XCTAssertFalse(sanitized.contains("status=running"))
        XCTAssertTrue(sanitized.contains("Proceeding"))
        XCTAssertTrue(sanitized.contains("then continuing with the analysis"))
    }

    func testStripCoderideMarkersRemovesPlanLifecycleInlineMarkerVariant() {
        let input = """
        Proceeding markers:plan_step_upsert|step_id=2|status=running|title=Apply patch|and continuing with checks.
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertFalse(sanitized.contains("plan_step_upsert|"))
        XCTAssertFalse(sanitized.contains("step_id=2"))
        XCTAssertFalse(sanitized.contains("status=running"))
        XCTAssertFalse(sanitized.contains("title=Apply patch"))
        XCTAssertTrue(sanitized.contains("Proceeding"))
        XCTAssertTrue(sanitized.contains("and continuing with checks"))
    }

    func testStripCoderideMarkersRemovesPlanLifecycleTechnicalEventTokens() {
        let input = """
        plan_create plan_step_batch_update plan_request_user_input
        Final useful response.
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertFalse(sanitized.contains("plan_create"))
        XCTAssertFalse(sanitized.contains("plan_step_batch_update"))
        XCTAssertFalse(sanitized.contains("plan_request_user_input"))
        XCTAssertTrue(sanitized.contains("Final useful response."))
    }

    func testStripCoderideMarkersKeepsFollowingLinesWhenMarkerIsIncomplete() {
        let input = """
        [CODERIDE:todo_write|id=t1|title=Init
        Useful response visible during streaming.
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertFalse(sanitized.contains("CODERIDE"))
        XCTAssertTrue(sanitized.contains("Useful response visible during streaming."))
    }

    func testStripCoderideMarkersRemovesInlineOperationalPrefixButKeepsNaturalLanguageContent() {
        // Italian kept: initBoilerplate strips English "Starting task panel..." and removes the whole line
        // when followed by English; non-English content after the prefix survives.
        let input = """
        Starting task panel and todo update Procedo con l'implementazione dell'opzione selezionata: prima metto il TODO 1 in in_progress, poi individuo i test esistenti.
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertFalse(sanitized.lowercased().contains("starting task panel and todo update"))
        XCTAssertTrue(sanitized.contains("Procedo con l'implementazione dell'opzione selezionata"))
        XCTAssertTrue(sanitized.contains("TODO 1 in in_progress"))
    }

    func testStripCoderideMarkersRemovesCliProgressTraceLines() {
        let input = """
        Explored 2 files
        Inspecting related test files
        Ran codex --version

        Final useful response.
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertFalse(sanitized.contains("Explored 2 files"))
        XCTAssertFalse(sanitized.contains("Inspecting related test files"))
        XCTAssertFalse(sanitized.contains("Ran codex --version"))
        XCTAssertTrue(sanitized.contains("Final useful response."))
    }

    func testNonAggressiveSanitizationKeepsGenericKeyValueText() {
        let input = """
        Current config:
        status=ok
        id=abc123
        notes=visible value
        """

        let sanitized = ChatStore.stripCoderideMarkers(input, aggressive: false)

        XCTAssertTrue(sanitized.contains("status=ok"))
        XCTAssertTrue(sanitized.contains("id=abc123"))
        XCTAssertTrue(sanitized.contains("notes=visible value"))
    }

    func testNonAggressiveSanitizationRemovesExplicitCodexMarkersButKeepsText() {
        let input = """
        Before the marker [CODERIDE:todo_read]
        todo_write|id=t1|title=Task|
        Visible content.
        """

        let sanitized = ChatStore.stripCoderideMarkers(input, aggressive: false)

        XCTAssertFalse(sanitized.contains("CODERIDE"))
        XCTAssertFalse(sanitized.contains("todo_write|"))
        XCTAssertTrue(sanitized.contains("Visible content."))
    }

    func testStripCoderideMarkersDoesNotAlterCodeFenceContent() {
        let input = """
        Before

        ```swift
        let marker = "[CODERIDE:keep]"
        ```

        After
        """

        let sanitized = ChatStore.stripCoderideMarkers(input)

        XCTAssertTrue(sanitized.contains("```swift"))
        XCTAssertTrue(sanitized.contains(#""[CODERIDE:keep]""#))
        XCTAssertTrue(sanitized.contains("Before"))
        XCTAssertTrue(sanitized.contains("After"))
    }

    func testExtractLastOperationalThinkingLineReturnsLastOperationalLine() {
        let input = """
        Done
        Explored files
        Reading config
        """

        XCTAssertEqual(
            ChatStore.extractLastOperationalThinkingLine(from: input),
            "Reading config"
        )
    }

    func testExtractLastOperationalThinkingLineReturnsNilWhenRustRuntimeIsUnavailable() {
        let input = """
        Done
        Explored files
        Reading config
        """

        withSwiftReviewCoreFallback {
            XCTAssertNil(ChatStore.extractLastOperationalThinkingLine(from: input))
        }
    }

    func testStripCoderideMarkersDoesNotCrashWhenRustRuntimeIsUnavailable() {
        let input = """
        Before [CODERIDE:read|path=Sources/A.swift] after
        """

        withSwiftReviewCoreFallback {
            XCTAssertEqual(
                ChatStore.stripCoderideMarkers(input),
                "Before [CODERIDE:read|path=Sources/A.swift] after"
            )
        }
    }
}
