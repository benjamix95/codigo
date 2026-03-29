import XCTest
@testable import CoderIDE
import CoderEngine

/// Test che verificano l'INTEGRITÀ strutturale del reducer e delle invarianti
/// di interleaving. Se uno di questi test fallisce, il reducer ha subito una
/// modifica incompatibile con il contratto di interleaving.
///
/// REGOLA ASSOLUTA: MAI modificare questo file per far passare i test.
/// Se fallisce, il problema è nel reducer o nella pipeline, non in questo test.
final class CodexStreamingRegressionImmutabilityTests: XCTestCase {

    // MARK: - Helpers

    private func makeState() -> ChatTurnState {
        ChatTurnState(
            conversationId: UUID(),
            assistantMessageId: UUID(),
            turnId: UUID().uuidString,
            providerId: "codex-cli"
        )
    }

    private func evt(
        _ seq: Int,
        _ kind: ChatPipelineEventKind,
        _ payload: [String: String],
        state: ChatTurnState
    ) -> ChatPipelineEvent {
        ChatPipelineEvent(
            conversationId: state.conversationId,
            assistantMessageId: state.assistantMessageId,
            turnId: state.turnId,
            sequence: seq,
            source: "codex-cli",
            kind: kind,
            payload: payload
        )
    }

    // MARK: - Test 1: toolTraceArtifact crea SEMPRE un segmento toolUse distinto

    func testReducerToolTraceAlwaysCreatesDistinctToolSegment() {
        var state = makeState()

        // textDelta → segmento .text
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(1, .textDelta, ["stream_id": "main", "delta": "Prima"], state: state)
        )
        XCTAssertEqual(state.timelineSegments.last?.kind, .text,
            "Precondizione: ultimo segmento deve essere .text")

        // toolTraceArtifact → DEVE creare .toolUse
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(2, .toolTraceArtifact, [
                "artifact_id": "t1", "title": "coderide_read",
            ], state: state)
        )
        XCTAssertEqual(state.timelineSegments.last?.kind, .toolUse,
            "INVARIANTE VIOLATA: toolTraceArtifact DEVE creare un segmento .toolUse")

        // textDelta dopo tool → DEVE creare NUOVO segmento .text
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(3, .textDelta, ["stream_id": "main", "delta": "Dopo"], state: state)
        )
        XCTAssertEqual(state.timelineSegments.last?.kind, .text,
            "INVARIANTE VIOLATA: textDelta dopo toolUse deve creare nuovo segmento .text")
        XCTAssertEqual(state.textSegments.count, 2,
            "INVARIANTE VIOLATA: dopo tool, textDelta = nuovo segmento, non merge")
    }

    // MARK: - Test 2: conteggio segmenti esatto per sequenza nota

    func testTimelineSegmentCountInvariantForKnownSequence() {
        let toolCount = 3
        var state = makeState()
        var seq = 1

        for i in 0..<toolCount {
            state = ChatPipelineReducer.apply(
                state: state,
                event: evt(seq, .textDelta, ["stream_id": "main", "delta": "t\(i)"], state: state)
            )
            seq += 1
            state = ChatPipelineReducer.apply(
                state: state,
                event: evt(seq, .toolTraceArtifact, [
                    "artifact_id": "tool-\(i)", "title": "coderide_tool_\(i)",
                ], state: state)
            )
            seq += 1
        }
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(seq, .textDelta, ["stream_id": "main", "delta": "fine"], state: state)
        )

        // 3 tool + 4 testi = 7 segmenti totali
        XCTAssertEqual(state.timelineSegments.count, 7,
            "INVARIANTE VIOLATA: 3 tool + 4 testi = 7 segmenti, trovati \(state.timelineSegments.count)")

        let expectedPattern: [ChatTimelineSegmentKind] = [
            .text, .toolUse, .text, .toolUse, .text, .toolUse, .text,
        ]
        XCTAssertEqual(state.timelineSegments.map(\.kind), expectedPattern,
            "INVARIANTE VIOLATA: pattern segmenti non corrisponde")
    }

    // MARK: - Test 3: testi non vengono mai fusi attraverso confini tool

    func testTextSegmentsAreNeverMergedAcrossToolBoundaries() {
        var state = makeState()
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(1, .textDelta, ["stream_id": "main", "delta": "AAA"], state: state)
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(2, .toolTraceArtifact, [
                "artifact_id": "t1", "title": "read",
            ], state: state)
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(3, .textDelta, ["stream_id": "main", "delta": "BBB"], state: state)
        )

        XCTAssertEqual(state.textSegments, ["AAA", "BBB"],
            "INVARIANTE VIOLATA: testi separati da tool devono restare distinti, mai fusi in 'AAABBB'")
        XCTAssertFalse(state.textSegments.contains("AAABBB"),
            "INVARIANTE VIOLATA: rilevata fusione monolitica dei segmenti testo!")
    }

    // MARK: - Test 4: tool con detail vuoto inserisce comunque toolUse

    func testToolTraceWithEmptyDetailStillInsertsToolUseSegment() {
        var state = makeState()
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(1, .textDelta, ["stream_id": "main", "delta": "Prima"], state: state)
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(2, .toolTraceArtifact, [
                "artifact_id": "t-empty", "title": "coderide_read",
                // detail intenzionalmente ASSENTE
            ], state: state)
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(3, .textDelta, ["stream_id": "main", "delta": "Dopo"], state: state)
        )

        let toolCount = state.timelineSegments.filter { $0.kind == .toolUse }.count
        XCTAssertEqual(toolCount, 1,
            "INVARIANTE VIOLATA: toolTraceArtifact senza detail DEVE comunque creare segmento toolUse")
        XCTAssertEqual(state.textSegments.count, 2,
            "INVARIANTE VIOLATA: il testo deve essere diviso anche con tool senza detail")
    }

    // MARK: - Test 5: tool consecutivi producono segmenti distinti

    func testConsecutiveToolTracesEachProduceDistinctSegment() {
        var state = makeState()
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(1, .textDelta, ["stream_id": "main", "delta": "Inizio"], state: state)
        )
        // Due tool CONSECUTIVI senza testo tra loro
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(2, .toolTraceArtifact, [
                "artifact_id": "t1", "title": "coderide_read",
            ], state: state)
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(3, .toolTraceArtifact, [
                "artifact_id": "t2", "title": "coderide_grep",
            ], state: state)
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(4, .textDelta, ["stream_id": "main", "delta": "Fine"], state: state)
        )

        let toolCount = state.timelineSegments.filter { $0.kind == .toolUse }.count
        XCTAssertEqual(toolCount, 2,
            "INVARIANTE VIOLATA: 2 toolTraceArtifact consecutivi devono produrre 2 segmenti toolUse distinti")
    }

    // MARK: - Test 6: blocks riflette timelineSegments

    func testBlocksReflectTimelineSegmentsExactly() {
        var state = makeState()
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(1, .textDelta, ["stream_id": "main", "delta": "Testo A"], state: state)
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(2, .toolTraceArtifact, [
                "artifact_id": "t1", "title": "read", "detail": "ok",
            ], state: state)
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(3, .textDelta, ["stream_id": "main", "delta": "Testo B"], state: state)
        )

        let blocks = state.blocks
        let blockKinds = blocks.map(\.kind)

        XCTAssertTrue(blockKinds.contains(.primaryText),
            "INVARIANTE VIOLATA: blocks deve contenere primaryText")
        XCTAssertTrue(blockKinds.contains(.toolMarker),
            "INVARIANTE VIOLATA: blocks deve contenere toolMarker")

        let primaryBlocks = blocks.filter { $0.kind == .primaryText }
        XCTAssertEqual(primaryBlocks.count, 2,
            "INVARIANTE VIOLATA: 2 segmenti testo → 2 blocchi primaryText")
        XCTAssertEqual(primaryBlocks[0].text, "Testo A")
        XCTAssertEqual(primaryBlocks[1].text, "Testo B")
    }

    // MARK: - Test 7: textReplace non distrugge toolUse

    func testTextReplaceDoesNotDestroyExistingToolUseSegments() {
        var state = makeState()
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(1, .textDelta, ["stream_id": "main", "delta": "A"], state: state)
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(2, .toolTraceArtifact, [
                "artifact_id": "t1", "title": "read",
            ], state: state)
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(3, .textDelta, ["stream_id": "main", "delta": "B"], state: state)
        )

        let toolsBefore = state.timelineSegments.filter { $0.kind == .toolUse }.count

        state = ChatPipelineReducer.apply(
            state: state,
            event: evt(4, .textReplace, [
                "stream_id": "main", "replacement": "Nuovo",
            ], state: state)
        )

        let toolsAfter = state.timelineSegments.filter { $0.kind == .toolUse }.count
        XCTAssertEqual(toolsAfter, toolsBefore,
            "INVARIANTE VIOLATA: textReplace NON deve rimuovere segmenti toolUse")
        XCTAssertFalse(state.timelineSegments.isEmpty,
            "INVARIANTE VIOLATA: textReplace NON deve azzerare la timeline")
    }

    // MARK: - Test 8: helper di rilevamento monolitico è sound

    func testMonolithicRegressionDetectionHelperIsSound() {
        for expectedCount in 1...5 {
            // Stato sano: N tool events
            var healthy = makeState()
            var seq = 1
            for i in 0..<expectedCount {
                healthy = ChatPipelineReducer.apply(
                    state: healthy,
                    event: evt(seq, .textDelta, ["stream_id": "main", "delta": "t\(i)"], state: healthy)
                )
                seq += 1
                healthy = ChatPipelineReducer.apply(
                    state: healthy,
                    event: evt(seq, .toolTraceArtifact, [
                        "artifact_id": "tool-\(i)", "title": "t\(i)",
                    ], state: healthy)
                )
                seq += 1
            }

            XCTAssertFalse(
                CodexMonolithicRegressionGuardTests.isMonolithicRegression(
                    state: healthy, expectedToolCount: expectedCount
                ),
                "Stato sano con \(expectedCount) tool non deve essere segnalato come regressione"
            )

            // Stato monolitico: solo testo
            var monolithic = makeState()
            monolithic = ChatPipelineReducer.apply(
                state: monolithic,
                event: evt(1, .textDelta, ["stream_id": "main", "delta": "Solo testo"], state: monolithic)
            )

            XCTAssertTrue(
                CodexMonolithicRegressionGuardTests.isMonolithicRegression(
                    state: monolithic, expectedToolCount: expectedCount
                ),
                "Output monolitico con \(expectedCount) tool attesi DEVE essere rilevato come regressione"
            )
        }
    }
}
