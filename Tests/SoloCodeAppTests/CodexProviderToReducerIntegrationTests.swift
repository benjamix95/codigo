import XCTest
@testable import CoderIDE
import CoderEngine

/// Test di integrazione che verificano la catena COMPLETA:
/// StreamEvent[] (output provider Codex) → RawArtifactEventAdapter → ChatPipelineReducer → ChatTurnState.
///
/// QUESTI test colmano il gap critico: i test esistenti a livello reducer usano eventi
/// ChatPipelineEvent pre-costruiti. Qui partiamo dai raw type come arrivano dal provider
/// e verifichiamo che la timeline finale sia corretta.
///
/// Se Codex regredisce a output monolitico, QUESTI test DEVONO fallire.
/// REGOLA: NON modificare questi test per farli passare. Se falliscono, il bug è nel codice.
@MainActor
final class CodexProviderToReducerIntegrationTests: XCTestCase {

    // MARK: - Helpers

    private func makeState() -> ChatTurnState {
        ChatTurnState(
            conversationId: UUID(),
            assistantMessageId: UUID(),
            turnId: UUID().uuidString,
            providerId: "codex-cli"
        )
    }

    /// Simula la catena reale: raw type + payload → RawArtifactEventAdapter → ChatPipelineReducer.
    /// Questo è esattamente ciò che fa PipelineIntegrationService.consumeRawPipelineArtifacts.
    private func applyRawSequence(
        _ rawEvents: [(rawType: String, payload: [String: String])],
        textDeltas: [(afterIndex: Int, text: String)] = [],
        to initial: ChatTurnState
    ) -> ChatTurnState {
        var state = initial
        var seq = 1

        // Interleave: per ogni raw event, prima applica i textDelta schedulati prima di esso
        for (i, raw) in rawEvents.enumerated() {
            // Applica textDelta programmati prima di questo raw event
            for td in textDeltas where td.afterIndex == i {
                let textEvent = ChatPipelineEvent(
                    conversationId: state.conversationId,
                    assistantMessageId: state.assistantMessageId,
                    turnId: state.turnId,
                    sequence: seq,
                    source: "codex-cli",
                    kind: .textDelta,
                    payload: ["stream_id": "main", "delta": td.text]
                )
                state = ChatPipelineReducer.apply(state: state, event: textEvent)
                seq += 1
            }

            // Converti raw → ChatPipelineEvent via RawArtifactEventAdapter (la catena reale)
            let adapted = RawArtifactEventAdapter.events(
                rawType: raw.rawType,
                payload: raw.payload,
                conversationId: state.conversationId,
                assistantMessageId: state.assistantMessageId,
                turnId: state.turnId,
                providerId: "codex-cli"
            )
            for event in adapted {
                let sequenced = ChatPipelineEvent(
                    conversationId: event.conversationId,
                    assistantMessageId: event.assistantMessageId,
                    turnId: event.turnId,
                    sequence: seq,
                    source: event.source,
                    kind: event.kind,
                    payload: event.payload
                )
                state = ChatPipelineReducer.apply(state: state, event: sequenced)
                seq += 1
            }
        }

        // Applica textDelta finali (afterIndex == rawEvents.count)
        for td in textDeltas where td.afterIndex == rawEvents.count {
            let textEvent = ChatPipelineEvent(
                conversationId: state.conversationId,
                assistantMessageId: state.assistantMessageId,
                turnId: state.turnId,
                sequence: seq,
                source: "codex-cli",
                kind: .textDelta,
                payload: ["stream_id": "main", "delta": td.text]
            )
            state = ChatPipelineReducer.apply(state: state, event: textEvent)
            seq += 1
        }

        return state
    }

    // MARK: - Test 1: Sequenza realistica MCP → timeline interleaved

    func testRealisticCodexMCPSequenceProducesInterleavedTimeline() {
        let state = applyRawSequence(
            [
                (rawType: "mcp_tool_call", payload: [
                    "mcp_tool": "coderide_read",
                    "id": "fc-1",
                    "detail": "Reading Sources/App.swift",
                ]),
                (rawType: "mcp_tool_call", payload: [
                    "mcp_tool": "coderide_grep",
                    "id": "fc-2",
                    "detail": "Searching PolicyAck in Sources/",
                ]),
            ],
            textDeltas: [
                (afterIndex: 0, text: "Analizzo il file. "),
                (afterIndex: 1, text: "Trovato il pattern. Cerco riferimenti. "),
                (afterIndex: 2, text: "Ecco il riepilogo finale."),
            ],
            to: makeState()
        )

        let segmentKinds = state.timelineSegments.map(\.kind)

        XCTAssertEqual(
            segmentKinds,
            [.text, .toolUse, .text, .toolUse, .text],
            "CONTRATTO VIOLATO: sequenza MCP realistica deve produrre [text, tool, text, tool, text], trovato \(segmentKinds)"
        )
        XCTAssertEqual(
            state.textSegments.count, 3,
            "CONTRATTO VIOLATO: 3 porzioni di testo separate dai 2 tool MCP"
        )
    }

    // MARK: - Test 2: Output monolitico → singolo segmento testo

    func testMonolithicCodexOutputHasNoToolSegments() {
        let state = applyRawSequence(
            [],
            textDeltas: [
                (afterIndex: 0, text: "Risposta completa in un solo blocco senza usare tool."),
            ],
            to: makeState()
        )

        XCTAssertEqual(
            state.timelineSegments.map(\.kind), [.text],
            "Output monolitico deve avere solo un segmento .text"
        )
        XCTAssertEqual(state.textSegments.count, 1)
        XCTAssertTrue(
            CodexMonolithicRegressionGuardTests.isMonolithicRegression(
                state: state, expectedToolCount: 2
            ),
            "L'helper di rilevamento DEVE segnalare regressione monolitica quando mancano tool attesi"
        )
    }

    // MARK: - Test 3: Tool nativi (function_call) producono toolTrace

    func testCodexNativeFunctionCallProducesToolTraceArtifact() {
        let state = applyRawSequence(
            [
                (rawType: "function_call", payload: [
                    "name": "read",
                    "id": "fc-native-1",
                    "detail": "cat Config.swift",
                ]),
            ],
            textDeltas: [
                (afterIndex: 0, text: "Leggo il file. "),
                (afterIndex: 1, text: "Ecco il contenuto."),
            ],
            to: makeState()
        )

        let toolSegments = state.timelineSegments.filter { $0.kind == .toolUse }
        XCTAssertEqual(
            toolSegments.count, 1,
            "CONTRATTO VIOLATO: function_call nativo deve produrre 1 segmento toolUse via RawArtifactEventAdapter"
        )
        XCTAssertEqual(state.textSegments.count, 2)
    }

    // MARK: - Test 4: Mapping contract per ogni raw type rilevante

    func testRawArtifactEventAdapterMappingContract() {
        let conversationId = UUID()
        let messageId = UUID()
        let turnId = UUID().uuidString

        // mcp_tool_call → .toolTraceArtifact
        let mcpEvents = RawArtifactEventAdapter.events(
            rawType: "mcp_tool_call",
            payload: ["mcp_tool": "coderide_read", "id": "t1"],
            conversationId: conversationId,
            assistantMessageId: messageId,
            turnId: turnId,
            providerId: "codex-cli"
        )
        XCTAssertEqual(mcpEvents.first?.kind, .toolTraceArtifact,
            "mcp_tool_call DEVE mappare a .toolTraceArtifact")

        // function_call → .toolTraceArtifact
        let fcEvents = RawArtifactEventAdapter.events(
            rawType: "function_call",
            payload: ["name": "grep", "id": "t2"],
            conversationId: conversationId,
            assistantMessageId: messageId,
            turnId: turnId,
            providerId: "codex-cli"
        )
        XCTAssertEqual(fcEvents.first?.kind, .toolTraceArtifact,
            "function_call DEVE mappare a .toolTraceArtifact")

        // file_change → .filesArtifact
        let fileEvents = RawArtifactEventAdapter.events(
            rawType: "file_change",
            payload: ["path": "Sources/A.swift"],
            conversationId: conversationId,
            assistantMessageId: messageId,
            turnId: turnId,
            providerId: "codex-cli"
        )
        XCTAssertEqual(fileEvents.first?.kind, .filesArtifact,
            "file_change DEVE mappare a .filesArtifact")

        // command_execution → .commandsArtifact
        let cmdEvents = RawArtifactEventAdapter.events(
            rawType: "command_execution",
            payload: ["command": "swift build"],
            conversationId: conversationId,
            assistantMessageId: messageId,
            turnId: turnId,
            providerId: "codex-cli"
        )
        XCTAssertEqual(cmdEvents.first?.kind, .commandsArtifact,
            "command_execution DEVE mappare a .commandsArtifact")

        // reasoning → .reasoningDelta (con provider non-Codex, perché Codex ha policy "suppressed")
        let reasoningEvents = RawArtifactEventAdapter.events(
            rawType: "reasoning",
            payload: ["output": "Penso che..."],
            conversationId: conversationId,
            assistantMessageId: messageId,
            turnId: turnId,
            providerId: "claude"
        )
        XCTAssertEqual(reasoningEvents.first?.kind, .reasoningDelta,
            "reasoning DEVE mappare a .reasoningDelta (provider non-codex)")

        // reasoning con provider codex-cli → soppresso dalla ChatReasoningPresentationPolicy
        let codexReasoningEvents = RawArtifactEventAdapter.events(
            rawType: "reasoning",
            payload: ["output": "Penso che..."],
            conversationId: conversationId,
            assistantMessageId: messageId,
            turnId: turnId,
            providerId: "codex-cli"
        )
        XCTAssertTrue(codexReasoningEvents.isEmpty,
            "reasoning con provider codex-cli viene soppresso dalla policy")

        // tipo sconosciuto → nessun evento
        let unknownEvents = RawArtifactEventAdapter.events(
            rawType: "unknown_type",
            payload: ["data": "irrelevant"],
            conversationId: conversationId,
            assistantMessageId: messageId,
            turnId: turnId,
            providerId: "codex-cli"
        )
        XCTAssertTrue(unknownEvents.isEmpty,
            "Tipo raw sconosciuto NON deve produrre eventi pipeline")
    }

    // MARK: - Test 5: Mix MCP + nativi + file_change nella stessa sessione

    func testMixedRawTypesProduceCorrectTimelinePattern() {
        let state = applyRawSequence(
            [
                (rawType: "mcp_tool_call", payload: [
                    "mcp_tool": "coderide_semantic_search",
                    "id": "mcp-1",
                    "detail": "Searching codebase",
                ]),
                (rawType: "function_call", payload: [
                    "name": "grep",
                    "id": "fc-1",
                    "detail": "grep pattern",
                ]),
                (rawType: "file_change", payload: [
                    "path": "Sources/Fix.swift",
                ]),
            ],
            textDeltas: [
                (afterIndex: 0, text: "Cerco nel codebase. "),
                (afterIndex: 1, text: "Trovato. Verifico con grep. "),
                (afterIndex: 2, text: "Applico la fix. "),
                (afterIndex: 3, text: "Fatto."),
            ],
            to: makeState()
        )

        let toolCount = state.timelineSegments.filter { $0.kind == .toolUse }.count
        // mcp_tool_call + function_call → 2 toolTraceArtifact → 2 toolUse
        // file_change → filesArtifact → 1 toolUse (via ensureToolSegment, non appendDistinct)
        XCTAssertGreaterThanOrEqual(
            toolCount, 2,
            "CONTRATTO VIOLATO: almeno 2 tool (MCP + nativo) devono produrre segmenti toolUse, trovati \(toolCount)"
        )
        XCTAssertGreaterThanOrEqual(
            state.textSegments.count, 3,
            "CONTRATTO VIOLATO: almeno 3 segmenti testo tra i tool"
        )
    }

    // MARK: - Test 6: textReplace non distrugge toolUse esistenti

    func testTextReplaceAfterToolsPreservesToolUseSegments() {
        var state = applyRawSequence(
            [
                (rawType: "mcp_tool_call", payload: [
                    "mcp_tool": "coderide_read",
                    "id": "t1",
                    "detail": "read",
                ]),
            ],
            textDeltas: [
                (afterIndex: 0, text: "Prima. "),
                (afterIndex: 1, text: "Dopo."),
            ],
            to: makeState()
        )

        let toolsBefore = state.timelineSegments.filter { $0.kind == .toolUse }.count
        XCTAssertEqual(toolsBefore, 1, "Precondizione: 1 toolUse prima di textReplace")

        // Applica textReplace (come fa Codex per multi-turn)
        let replaceEvent = ChatPipelineEvent(
            conversationId: state.conversationId,
            assistantMessageId: state.assistantMessageId,
            turnId: state.turnId,
            sequence: 100,
            source: "codex-cli",
            kind: .textReplace,
            payload: ["stream_id": "main", "replacement": "Nuovo contenuto"]
        )
        state = ChatPipelineReducer.apply(state: state, event: replaceEvent)

        let toolsAfter = state.timelineSegments.filter { $0.kind == .toolUse }.count
        XCTAssertEqual(
            toolsAfter, toolsBefore,
            "CONTRATTO VIOLATO: textReplace NON deve rimuovere segmenti toolUse esistenti"
        )
    }
}
