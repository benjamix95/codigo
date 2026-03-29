import XCTest
@testable import CoderIDE
import CoderEngine

// swiftlint:disable type_body_length

/// ⚠️ TEST IMMUTABILI — NON MODIFICARE QUESTI TEST ⚠️
///
/// Questi test proteggono invarianti fondamentali del sistema di interleaving.
/// Se un test fallisce, il BUG è nel codice applicativo, MAI nel test.
///
/// REGOLE:
/// 1. Questi test NON devono essere modificati per "farli passare"
/// 2. Se un test fallisce, correggere il CODICE, non il test
/// 3. Nessuna modifica a questi test senza revisione esplicita del proprietario
/// 4. Aggiungere nuovi test è consentito, ma non modificare quelli esistenti
final class CodexImmutableInterleavingGuardTests: XCTestCase {

    // MARK: - Helpers

    private func makeState() -> ChatTurnState {
        ChatTurnState(
            conversationId: UUID(),
            assistantMessageId: UUID(),
            turnId: UUID().uuidString,
            providerId: "codex-cli"
        )
    }

    private func apply(
        _ events: [(Int, ChatPipelineEventKind, [String: String])],
        to state: ChatTurnState
    ) -> ChatTurnState {
        var s = state
        for (seq, kind, payload) in events {
            s = ChatPipelineReducer.apply(
                state: s,
                event: ChatPipelineEvent(
                    conversationId: s.conversationId,
                    assistantMessageId: s.assistantMessageId,
                    turnId: s.turnId,
                    sequence: seq,
                    source: "codex-cli",
                    kind: kind,
                    payload: payload
                )
            )
        }
        return s
    }

    // MARK: - IMMUTABLE GUARD: Core Interleaving Invariants

    // IMMUTABLE GUARD — DO NOT MODIFY THIS TEST
    /// Invariante: text → tool → text DEVE produrre esattamente 3 segmenti [.text, .toolUse, .text].
    func testIMMUTABLE_TextToolTextSequenceMustProduceThreeSegments() {
        let state = apply([
            (1, .textDelta, ["stream_id": "main", "delta": "A"]),
            (2, .toolTraceArtifact, ["artifact_id": "t1", "title": "read"]),
            (3, .textDelta, ["stream_id": "main", "delta": "B"]),
        ], to: makeState())

        XCTAssertEqual(
            state.timelineSegments.map(\.kind),
            [.text, .toolUse, .text],
            "INVARIANTE VIOLATA: text → tool → text DEVE produrre [.text, .toolUse, .text]"
        )
        XCTAssertEqual(state.textSegments, ["A", "B"])
    }

    // IMMUTABLE GUARD — DO NOT MODIFY THIS TEST
    /// Invariante: N tool DEVONO produrre N segmenti toolUse e N+1 segmenti testo.
    func testIMMUTABLE_NToolsMustProduceNToolUseSegments() {
        for n in [1, 2, 3, 5, 10] {
            var events: [(Int, ChatPipelineEventKind, [String: String])] = []
            var seq = 1
            for i in 0..<n {
                events.append((seq, .textDelta, ["stream_id": "main", "delta": "T\(i)"]))
                seq += 1
                events.append((seq, .toolTraceArtifact, ["artifact_id": "tool-\(i)", "title": "t\(i)"]))
                seq += 1
            }
            events.append((seq, .textDelta, ["stream_id": "main", "delta": "Fine"]))

            let state = apply(events, to: makeState())

            let toolCount = state.timelineSegments.filter { $0.kind == .toolUse }.count
            XCTAssertEqual(
                toolCount, n,
                "INVARIANTE VIOLATA [N=\(n)]: \(n) tool → \(n) toolUse, trovati \(toolCount)"
            )
            XCTAssertEqual(
                state.textSegments.count, n + 1,
                "INVARIANTE VIOLATA [N=\(n)]: \(n) tool → \(n + 1) testi, trovati \(state.textSegments.count)"
            )
        }
    }

    // IMMUTABLE GUARD — DO NOT MODIFY THIS TEST
    /// Invariante: output monolitico (solo testo) DEVE avere zero toolUse e un solo testo.
    func testIMMUTABLE_MonolithicOutputMustHaveZeroToolSegments() {
        let state = apply([
            (1, .textDelta, ["stream_id": "main", "delta": "Risposta completa"]),
        ], to: makeState())

        XCTAssertEqual(
            state.timelineSegments.filter { $0.kind == .toolUse }.count, 0,
            "INVARIANTE VIOLATA: output senza tool → zero toolUse"
        )
        XCTAssertEqual(
            state.textSegments.count, 1,
            "INVARIANTE VIOLATA: output senza tool → un solo segmento testo"
        )
    }

    // IMMUTABLE GUARD — DO NOT MODIFY THIS TEST
    /// Invariante: tool trace DEVE dividere il testo — MAI fusione monolitica.
    func testIMMUTABLE_ToolTraceArtifactMustSplitTextStream() {
        let state = apply([
            (1, .textDelta, ["stream_id": "main", "delta": "Prima"]),
            (2, .toolTraceArtifact, ["artifact_id": "t1", "title": "read"]),
            (3, .textDelta, ["stream_id": "main", "delta": "Dopo"]),
        ], to: makeState())

        XCTAssertEqual(state.textSegments[0], "Prima")
        XCTAssertEqual(state.textSegments[1], "Dopo")
        XCTAssertNotEqual(
            state.textSegments, ["PrimaDopo"],
            "INVARIANTE VIOLATA: rilevata fusione monolitica — i testi sono stati uniti!"
        )
    }

    // IMMUTABLE GUARD — DO NOT MODIFY THIS TEST
    /// Invariante: blocks devono riflettere l'interleaving con primaryText e toolMarker.
    func testIMMUTABLE_BlocksKindsMustReflectInterleaving() {
        let state = apply([
            (1, .textDelta, ["stream_id": "main", "delta": "Inizio"]),
            (2, .toolTraceArtifact, ["artifact_id": "t1", "title": "read", "detail": "ok"]),
            (3, .textDelta, ["stream_id": "main", "delta": "Fine"]),
        ], to: makeState())

        let blocks = state.blocks
        let primaryBlocks = blocks.filter { $0.kind == .primaryText }
        let toolMarkers = blocks.filter { $0.kind == .toolMarker }

        XCTAssertGreaterThanOrEqual(
            primaryBlocks.count, 2,
            "INVARIANTE VIOLATA: blocks devono contenere >= 2 primaryText"
        )
        XCTAssertGreaterThanOrEqual(
            toolMarkers.count, 1,
            "INVARIANTE VIOLATA: blocks devono contenere >= 1 toolMarker"
        )
    }

    // IMMUTABLE GUARD — DO NOT MODIFY THIS TEST
    /// Invariante: textReplace dopo tool NON deve rimuovere i segmenti toolUse.
    func testIMMUTABLE_TextReplaceAfterToolMustNotRemoveToolSegments() {
        var state = apply([
            (1, .textDelta, ["stream_id": "main", "delta": "Prima"]),
            (2, .toolTraceArtifact, ["artifact_id": "t1", "title": "read"]),
            (3, .textDelta, ["stream_id": "main", "delta": "Dopo"]),
        ], to: makeState())

        let toolCountBefore = state.timelineSegments.filter { $0.kind == .toolUse }.count

        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: state.conversationId,
                assistantMessageId: state.assistantMessageId,
                turnId: state.turnId,
                sequence: 4,
                source: "codex-cli",
                kind: .textReplace,
                payload: ["stream_id": "main", "replacement": "Aggiornato"]
            )
        )

        let toolCountAfter = state.timelineSegments.filter { $0.kind == .toolUse }.count
        XCTAssertEqual(
            toolCountAfter, toolCountBefore,
            "INVARIANTE VIOLATA: textReplace ha rimosso segmenti toolUse"
        )
    }

    // IMMUTABLE GUARD — DO NOT MODIFY THIS TEST
    /// Invariante: toolTraceArtifact con detail vuoto DEVE creare marker.
    func testIMMUTABLE_EmptyDetailToolTraceStillCreatesMarker() {
        let state = apply([
            (1, .textDelta, ["stream_id": "main", "delta": "A"]),
            (2, .toolTraceArtifact, ["artifact_id": "t1", "title": "read"]),
            (3, .textDelta, ["stream_id": "main", "delta": "B"]),
        ], to: makeState())

        let toolCount = state.timelineSegments.filter { $0.kind == .toolUse }.count
        XCTAssertEqual(
            toolCount, 1,
            "INVARIANTE VIOLATA: toolTraceArtifact senza detail DEVE creare marker"
        )
    }

    // IMMUTABLE GUARD — DO NOT MODIFY THIS TEST
    /// Invariante: tool consecutivi senza testo DEVONO creare marker distinti.
    func testIMMUTABLE_ConsecutiveToolTracesCreateDistinctMarkers() {
        let state = apply([
            (1, .textDelta, ["stream_id": "main", "delta": "Start"]),
            (2, .toolTraceArtifact, ["artifact_id": "t1", "title": "read"]),
            (3, .toolTraceArtifact, ["artifact_id": "t2", "title": "grep"]),
            (4, .toolTraceArtifact, ["artifact_id": "t3", "title": "write"]),
            (5, .textDelta, ["stream_id": "main", "delta": "End"]),
        ], to: makeState())

        let toolCount = state.timelineSegments.filter { $0.kind == .toolUse }.count
        XCTAssertEqual(
            toolCount, 3,
            "INVARIANTE VIOLATA: 3 tool consecutivi → 3 marker distinti, trovati \(toolCount)"
        )
    }

    // IMMUTABLE GUARD — DO NOT MODIFY THIS TEST
    /// Invariante: i sequence numbers dei segmenti devono essere strettamente crescenti.
    func testIMMUTABLE_SegmentSequenceNumbersStrictlyIncreasing() {
        let state = apply([
            (1, .textDelta, ["stream_id": "main", "delta": "A"]),
            (2, .toolTraceArtifact, ["artifact_id": "t1", "title": "read"]),
            (3, .textDelta, ["stream_id": "main", "delta": "B"]),
            (4, .toolTraceArtifact, ["artifact_id": "t2", "title": "grep"]),
            (5, .textDelta, ["stream_id": "main", "delta": "C"]),
        ], to: makeState())

        let sequences = state.timelineSegments.map(\.sequence)
        for i in 1..<sequences.count {
            XCTAssertGreaterThan(
                sequences[i], sequences[i - 1],
                "INVARIANTE VIOLATA: sequence[\(i)]=\(sequences[i]) non è > sequence[\(i-1)]=\(sequences[i-1])"
            )
        }
    }

    // IMMUTABLE GUARD — DO NOT MODIFY THIS TEST
    /// Invariante: la timeline completa deve avere pattern alternato text/tool.
    func testIMMUTABLE_FullTimelineHasAlternatingPattern() {
        let state = apply([
            (1, .textDelta, ["stream_id": "main", "delta": "Inizio"]),
            (2, .toolTraceArtifact, ["artifact_id": "t1", "title": "read"]),
            (3, .textDelta, ["stream_id": "main", "delta": "Mezzo"]),
            (4, .toolTraceArtifact, ["artifact_id": "t2", "title": "grep"]),
            (5, .textDelta, ["stream_id": "main", "delta": "Fine"]),
        ], to: makeState())

        XCTAssertEqual(
            state.timelineSegments.map(\.kind),
            [.text, .toolUse, .text, .toolUse, .text],
            "INVARIANTE VIOLATA: il pattern deve essere [text, tool, text, tool, text]"
        )
    }
}

// swiftlint:enable type_body_length
