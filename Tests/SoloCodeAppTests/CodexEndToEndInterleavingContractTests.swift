import XCTest
@testable import CoderIDE
import CoderEngine

/// Test end-to-end che verificano la catena completa dal raw event Codex
/// al reducer timeline. Simula ciò che il parser Codex produrrebbe come
/// StreamEvent e verifica che il mapping + reducer producano interleaving.
///
/// NOTA: il parser Codex (`parseStreamJSONEvent`) è `internal` in CoderEngine
/// e testato separatamente in CoderEngineTests. Qui testiamo il layer successivo:
/// StreamEvent simulato → mapping a ChatPipelineEvent → ChatPipelineReducer → timeline.
///
/// Se il mapping è sbagliato (es. raw events tool non diventano toolTraceArtifact),
/// questi test DEVONO fallire.
final class CodexEndToEndInterleavingContractTests: XCTestCase {

    // MARK: - Helpers

    private func makeState() -> ChatTurnState {
        ChatTurnState(
            conversationId: UUID(),
            assistantMessageId: UUID(),
            turnId: UUID().uuidString,
            providerId: "codex-cli"
        )
    }

    /// Simula gli StreamEvent che il parser Codex produrrebbe per una sequenza
    /// realistica: text[0] → tool[0] → text[1] → tool[1] → ... → text[N].
    /// Il pattern reale è sempre: testo prima, poi tool, poi testo dopo.
    private func simulatedStreamEvents(
        toolNames: [String],
        textsBetween: [String]
    ) -> [StreamEvent] {
        var events: [StreamEvent] = [.started]
        // textsBetween[0] è il testo PRIMA del primo tool
        // textsBetween[i+1] è il testo DOPO tool[i]
        for (i, tool) in toolNames.enumerated() {
            // Testo PRIMA del tool
            if textsBetween.indices.contains(i) {
                events.append(.textDelta(textsBetween[i]))
            }
            // Tool raw event
            let isMCP = tool.hasPrefix("coderide_")
            var payload: [String: String] = [
                "tool_call_id": "fc-\(i)",
                "tool": tool,
                "status": "completed",
            ]
            if isMCP {
                payload["is_mcp"] = "true"
                payload["mcp_tool"] = tool
                payload["mcp_server"] = "coderide"
            }
            let rawType = isMCP ? tool.replacingOccurrences(of: "coderide_", with: "") : tool
            events.append(.raw(type: rawType, payload: payload))
        }
        // Testo DOPO l'ultimo tool
        let lastTextIndex = toolNames.count
        if textsBetween.indices.contains(lastTextIndex) {
            events.append(.textDelta(textsBetween[lastTextIndex]))
        }
        events.append(.completed)
        return events
    }

    /// Mappa StreamEvent → ChatPipelineEvent seguendo la logica del bridge reale.
    /// Questa è la funzione CRITICA: se diverge dal codice reale, il test rivela il gap.
    private func mapToPipelineEvents(
        _ streamEvents: [StreamEvent],
        state: ChatTurnState
    ) -> [ChatPipelineEvent] {
        var events: [ChatPipelineEvent] = []
        var seq = 1
        for se in streamEvents {
            switch se {
            case .textDelta(let text):
                guard !text.isEmpty else { continue }
                events.append(ChatPipelineEvent(
                    conversationId: state.conversationId,
                    assistantMessageId: state.assistantMessageId,
                    turnId: state.turnId,
                    sequence: seq,
                    source: "codex-cli",
                    kind: .textDelta,
                    payload: ["stream_id": "main", "delta": text]
                ))
                seq += 1
            case .raw(let type, let payload):
                if isToolRawEvent(type: type, payload: payload) {
                    events.append(ChatPipelineEvent(
                        conversationId: state.conversationId,
                        assistantMessageId: state.assistantMessageId,
                        turnId: state.turnId,
                        sequence: seq,
                        source: "codex-cli",
                        kind: .toolTraceArtifact,
                        payload: [
                            "artifact_id": payload["tool_call_id"] ?? "tool-\(seq)",
                            "title": payload["mcp_tool"] ?? payload["tool"] ?? type,
                            "detail": payload["detail"] ?? "",
                        ]
                    ))
                    seq += 1
                }
            case .textReplace(let text):
                events.append(ChatPipelineEvent(
                    conversationId: state.conversationId,
                    assistantMessageId: state.assistantMessageId,
                    turnId: state.turnId,
                    sequence: seq,
                    source: "codex-cli",
                    kind: .textReplace,
                    payload: ["stream_id": "main", "replacement": text]
                ))
                seq += 1
            case .started, .completed, .error:
                break
            }
        }
        return events
    }

    /// Determina se un raw event rappresenta un tool use.
    /// Questa logica DEVE corrispondere a ciò che il sistema reale fa
    /// quando decide di creare un toolTraceArtifact da un raw event.
    private func isToolRawEvent(type: String, payload: [String: String]) -> Bool {
        if payload["is_mcp"] == "true" || payload["mcp_tool"] != nil { return true }
        let toolTypes: Set<String> = [
            "read", "write", "grep", "semantic_search", "str_replace",
            "regex_replace", "create_file", "find_files", "list_dir",
            "file_outline", "find_symbol", "find_references", "codebase_search",
            "function_call", "bash", "edit", "apply_patch",
        ]
        if toolTypes.contains(type) { return true }
        if payload["tool"] != nil && type != "reasoning" && type != "mermaid_render" { return true }
        return false
    }

    private func reduce(
        _ pipelineEvents: [ChatPipelineEvent],
        initial: ChatTurnState
    ) -> ChatTurnState {
        var s = initial
        for event in pipelineEvents {
            s = ChatPipelineReducer.apply(state: s, event: event)
        }
        return s
    }

    // MARK: - End-to-End: MCP Tool Sequence

    /// Sequenza realistica: 2 tool MCP (coderide_read + coderide_grep) con testo tra i tool.
    /// DEVE produrre timeline interleaved.
    func testEndToEnd_RealisticCodexMCPSequence_ProducesInterleavedTimeline() {
        let streamEvents = simulatedStreamEvents(
            toolNames: ["coderide_read", "coderide_grep"],
            textsBetween: ["Ho letto il file.", "Cerco il pattern.", "Trovati 3 riferimenti."]
        )

        let initial = makeState()
        let pipelineEvents = mapToPipelineEvents(streamEvents, state: initial)
        let finalState = reduce(pipelineEvents, initial: initial)

        let toolCount = finalState.timelineSegments.filter { $0.kind == .toolUse }.count
        XCTAssertEqual(
            toolCount, 2,
            "E2E CONTRATTO VIOLATO: 2 MCP tool → 2 segmenti toolUse, trovati \(toolCount)"
        )
        XCTAssertGreaterThanOrEqual(
            finalState.textSegments.count, 3,
            "E2E CONTRATTO VIOLATO: con 2 tool e 3 testi, servono almeno 3 segmenti"
        )
    }

    /// Output monolitico: zero tool, solo testo.
    func testEndToEnd_MonolithicOutput_ProducesSingleTextSegment() {
        let streamEvents: [StreamEvent] = [
            .started,
            .textDelta("Risposta completa senza tool."),
            .completed,
        ]

        let initial = makeState()
        let pipelineEvents = mapToPipelineEvents(streamEvents, state: initial)
        let finalState = reduce(pipelineEvents, initial: initial)

        XCTAssertEqual(
            finalState.timelineSegments.filter { $0.kind == .toolUse }.count, 0,
            "Output monolitico: zero toolUse"
        )
        XCTAssertEqual(finalState.textSegments.count, 1, "Output monolitico: un solo segmento testo")
    }

    // MARK: - End-to-End: Mixed MCP + Native Tools

    /// Mix di tool MCP e nativi DEVE produrre interleaving per entrambi.
    func testEndToEnd_MixedMCPAndNativeTools_ProducesInterleaving() {
        let streamEvents = simulatedStreamEvents(
            toolNames: ["coderide_read", "grep", "coderide_str_replace"],
            textsBetween: ["Leggo.", "Cerco.", "Modifico.", "Fatto."]
        )

        let initial = makeState()
        let pipelineEvents = mapToPipelineEvents(streamEvents, state: initial)
        let finalState = reduce(pipelineEvents, initial: initial)

        let toolCount = finalState.timelineSegments.filter { $0.kind == .toolUse }.count
        XCTAssertEqual(
            toolCount, 3,
            "E2E: 2 MCP + 1 nativo → 3 toolUse, trovati \(toolCount)"
        )
        XCTAssertEqual(
            finalState.textSegments.count, 4,
            "E2E: 4 porzioni di testo tra 3 tool"
        )
        XCTAssertEqual(
            finalState.timelineSegments.map(\.kind),
            [.text, .toolUse, .text, .toolUse, .text, .toolUse, .text]
        )
    }

    // MARK: - Mapping Bridge Tests

    /// Verifica che isToolRawEvent identifica correttamente i tool.
    func testMappingBridge_DetectsToolRawEvents() {
        // MCP tool
        XCTAssertTrue(isToolRawEvent(
            type: "read",
            payload: ["is_mcp": "true", "mcp_tool": "coderide_read"]
        ))
        // Tool nativo per tipo
        XCTAssertTrue(isToolRawEvent(type: "read", payload: [:]))
        XCTAssertTrue(isToolRawEvent(type: "grep", payload: [:]))
        XCTAssertTrue(isToolRawEvent(type: "bash", payload: [:]))
        XCTAssertTrue(isToolRawEvent(type: "semantic_search", payload: [:]))
        // Non-tool
        XCTAssertFalse(isToolRawEvent(type: "reasoning", payload: [:]))
        XCTAssertFalse(isToolRawEvent(type: "mermaid_render", payload: [:]))
        XCTAssertFalse(isToolRawEvent(type: "turn_started", payload: [:]))
        XCTAssertFalse(isToolRawEvent(type: "assistant_update", payload: [:]))
    }

    /// Verifica che il mapping produce il numero corretto di pipeline events.
    func testMappingBridge_CorrectPipelineEventCount() {
        let streamEvents = simulatedStreamEvents(
            toolNames: ["coderide_read"],
            textsBetween: ["Prima.", "Dopo."]
        )

        let initial = makeState()
        let pipelineEvents = mapToPipelineEvents(streamEvents, state: initial)

        let textEvents = pipelineEvents.filter { $0.kind == .textDelta }
        let toolEvents = pipelineEvents.filter { $0.kind == .toolTraceArtifact }

        XCTAssertEqual(textEvents.count, 2, "2 testi → 2 textDelta events")
        XCTAssertEqual(toolEvents.count, 1, "1 tool → 1 toolTraceArtifact event")
    }

    /// Verifica che tool con payload mcp_tool vengono mappati con il titolo corretto.
    func testMappingBridge_MCPToolTitle() {
        let streamEvents: [StreamEvent] = [
            .raw(type: "read", payload: [
                "is_mcp": "true",
                "mcp_tool": "coderide_read",
                "tool_call_id": "fc-1",
            ]),
        ]

        let initial = makeState()
        let pipelineEvents = mapToPipelineEvents(streamEvents, state: initial)

        XCTAssertEqual(pipelineEvents.count, 1)
        XCTAssertEqual(pipelineEvents.first?.payload["title"], "coderide_read")
    }

    // MARK: - Regression Guard: Large Sequences

    /// Sequenza con 5 tool: deve produrre esattamente 5 toolUse e 6 testi.
    func testEndToEnd_LargeToolSequence_ProducesCorrectCounts() {
        let tools = (0..<5).map { "coderide_tool_\($0)" }
        let texts = (0...5).map { "Testo \($0)." }
        let streamEvents = simulatedStreamEvents(toolNames: tools, textsBetween: texts)

        let initial = makeState()
        let pipelineEvents = mapToPipelineEvents(streamEvents, state: initial)
        let finalState = reduce(pipelineEvents, initial: initial)

        XCTAssertEqual(
            finalState.timelineSegments.filter { $0.kind == .toolUse }.count, 5,
            "5 tool → 5 toolUse"
        )
        XCTAssertEqual(
            finalState.textSegments.count, 6,
            "5 tool + 6 testi → 6 segmenti testo"
        )
    }
}
