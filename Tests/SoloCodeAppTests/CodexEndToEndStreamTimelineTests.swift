import XCTest
@testable import CoderIDE
@testable import CoderEngine

/// Test end-to-end che verificano il flusso completo:
/// Codex JSON → parseStreamJSONEvent → RawArtifactEventAdapter → ChatPipelineReducer → ChatTurnState
///
/// Questi test catturano la classe di regressione dove:
/// - I test del parser Codex passano (emette raw events corretti)
/// - I test del reducer passano (gestisce toolTraceArtifact correttamente)
/// - Ma la conversione raw → toolTraceArtifact è rotta nell'adapter
/// - E quindi la timeline resta monolitica nell'app reale
///
/// REGOLA: NON modificare questi test per farli passare. Se falliscono, il bug
/// è nel path di conversione, non nei test.
@MainActor
final class CodexEndToEndStreamTimelineTests: XCTestCase {

    // MARK: - Helpers

    private let conversationId = UUID()
    private let assistantMessageId = UUID()
    private let turnId = "e2e-test-turn"
    private let providerId = "codex-cli"

    /// Parsa una sequenza di JSON Codex e produce ChatPipelineEvents tramite gli adapter.
    private func parseAndAdapt(
        jsonEvents: [[String: Any]]
    ) -> (streamEvents: [StreamEvent], pipelineEvents: [ChatPipelineEvent]) {
        var parserState = CodexCLIProvider.CodexStreamParserState()
        var allStreamEvents: [StreamEvent] = []

        for json in jsonEvents {
            allStreamEvents.append(
                contentsOf: CodexCLIProvider.parseStreamJSONEvent(json, state: &parserState)
            )
        }
        allStreamEvents.append(
            contentsOf: CodexCLIProvider.finalizeStreamJSONState(state: &parserState)
        )

        var pipelineEvents: [ChatPipelineEvent] = []
        var seq = 0

        for streamEvent in allStreamEvents {
            switch streamEvent {
            case .textDelta(let delta):
                pipelineEvents.append(ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: turnId,
                    sequence: seq,
                    source: providerId,
                    kind: .textDelta,
                    payload: ["delta": delta, "stream_id": "main"]
                ))
                seq += 1
            case .textReplace(let replacement):
                pipelineEvents.append(ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: turnId,
                    sequence: seq,
                    source: providerId,
                    kind: .textReplace,
                    payload: ["replacement": replacement, "stream_id": "main"]
                ))
                seq += 1
            case .raw(let type, let payload):
                let adapted = RawArtifactEventAdapter.events(
                    rawType: type,
                    payload: payload,
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: turnId,
                    providerId: providerId
                )
                for adaptedEvent in adapted {
                    pipelineEvents.append(ChatPipelineEvent(
                        conversationId: adaptedEvent.conversationId,
                        assistantMessageId: adaptedEvent.assistantMessageId,
                        turnId: adaptedEvent.turnId,
                        sequence: seq,
                        source: adaptedEvent.source,
                        kind: adaptedEvent.kind,
                        payload: adaptedEvent.payload
                    ))
                    seq += 1
                }
            case .started, .completed, .error:
                // Lifecycle events don't produce pipeline events
                break
            }
        }

        return (allStreamEvents, pipelineEvents)
    }

    /// Riduce una lista di ChatPipelineEvent in ChatTurnState.
    private func reduce(_ events: [ChatPipelineEvent]) -> ChatTurnState {
        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId,
            providerId: providerId
        )
        for event in events {
            state = ChatPipelineReducer.apply(state: state, event: event)
        }
        return state
    }

    // MARK: - End-to-End: Codex with MCP tools → interleaved timeline

    /// CONTRATTO CRITICO: Codex con 2 tool MCP coderide_* deve produrre timeline interleaved.
    func testCodexWithMCPToolsProducesInterleavedTimeline() {
        let (streamEvents, pipelineEvents) = parseAndAdapt(jsonEvents: [
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-1",
                    "type": "function_call",
                    "name": "functions.coderide_read",
                    "arguments": #"{"path":"Sources/App.swift"}"#,
                ] as [String: Any],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "msg-1",
                    "type": "agent_message",
                    "text": "Ho letto il file. Ora cerco il pattern.",
                ] as [String: Any],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-2",
                    "type": "function_call",
                    "name": "functions.coderide_grep",
                    "arguments": #"{"query":"PolicyAck","pathScope":"Sources"}"#,
                ] as [String: Any],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "msg-2",
                    "type": "agent_message",
                    "text": "Trovati 3 match. Ecco il riepilogo.",
                ] as [String: Any],
            ],
            ["type": "turn.completed"],
        ])

        // Verifica che il parser abbia emesso raw events per i tool
        let rawEvents = streamEvents.compactMap { e -> (String, [String: String])? in
            if case .raw(let type, let payload) = e { return (type, payload) }
            return nil
        }
        let toolRaws = rawEvents.filter {
            $0.0 == "mcp_tool_call" || $0.0 == "function_call" || $0.1["mcp_tool"] != nil
        }
        XCTAssertGreaterThanOrEqual(
            toolRaws.count, 2,
            "Parser deve emettere almeno 2 raw events per i tool MCP"
        )

        // INVARIANTE CRITICA: i pipelineEvents devono contenere toolTraceArtifact
        let toolTraceEvents = pipelineEvents.filter { $0.kind == .toolTraceArtifact }
        XCTAssertGreaterThanOrEqual(
            toolTraceEvents.count, 2,
            "REGRESSIONE E2E: 2 tool MCP devono produrre almeno 2 toolTraceArtifact, trovati \(toolTraceEvents.count)"
        )

        // Riduce e verifica la timeline
        let state = reduce(pipelineEvents)
        let timelineKinds = state.timelineSegments.map(\.kind)
        XCTAssertTrue(
            timelineKinds.contains(.toolUse),
            "REGRESSIONE E2E: la timeline DEVE contenere segmenti toolUse, trovato solo \(timelineKinds)"
        )
        XCTAssertGreaterThanOrEqual(
            state.textSegments.count, 2,
            "REGRESSIONE E2E: con tool intercalati devono esserci almeno 2 segmenti testo"
        )
    }

    /// Codex senza tool → timeline monolitica con un singolo segmento text.
    func testCodexWithoutToolsProducesMonolithicTimeline() {
        let (_, pipelineEvents) = parseAndAdapt(jsonEvents: [
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "msg-only",
                    "type": "agent_message",
                    "text": "Risposta diretta senza usare tool.",
                ] as [String: Any],
            ],
            ["type": "turn.completed"],
        ])

        let state = reduce(pipelineEvents)
        let toolUseCount = state.timelineSegments.filter { $0.kind == .toolUse }.count
        XCTAssertEqual(toolUseCount, 0, "Senza tool, zero segmenti toolUse")
        XCTAssertEqual(state.textSegments.count, 1, "Senza tool, un solo segmento text")
    }

    /// Codex con mix di tool MCP e tool nativi → tutti devono avere toolTrace.
    func testCodexMixedMCPAndNativeToolsAllProduceToolTrace() {
        let (_, pipelineEvents) = parseAndAdapt(jsonEvents: [
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-mcp",
                    "type": "function_call",
                    "name": "functions.coderide_read",
                    "arguments": #"{"path":"A.swift"}"#,
                ] as [String: Any],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "msg-1",
                    "type": "agent_message",
                    "text": "Letto il file MCP.",
                ] as [String: Any],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-native",
                    "type": "function_call",
                    "name": "functions.read",
                    "arguments": #"{"path":"B.swift"}"#,
                ] as [String: Any],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "msg-2",
                    "type": "agent_message",
                    "text": "Letto anche il secondo file.",
                ] as [String: Any],
            ],
            ["type": "turn.completed"],
        ])

        let toolTraceEvents = pipelineEvents.filter { $0.kind == .toolTraceArtifact }
        XCTAssertGreaterThanOrEqual(
            toolTraceEvents.count, 2,
            "REGRESSIONE E2E: sia tool MCP che nativi devono produrre toolTraceArtifact, trovati \(toolTraceEvents.count)"
        )

        let state = reduce(pipelineEvents)
        let toolUseCount = state.timelineSegments.filter { $0.kind == .toolUse }.count
        XCTAssertGreaterThanOrEqual(
            toolUseCount, 2,
            "REGRESSIONE E2E: 2 tool devono produrre almeno 2 segmenti toolUse"
        )
    }

    /// Sequenza lunga con 4 tool e 5 porzioni di testo.
    func testLongInterleavedSequencePreservesAllSegments() {
        let tools = [
            "coderide_read", "coderide_grep",
            "coderide_str_replace", "coderide_semantic_search",
        ]
        var jsonEvents: [[String: Any]] = [["type": "turn.started"]]

        for (i, tool) in tools.enumerated() {
            jsonEvents.append([
                "type": "item.completed",
                "item": [
                    "id": "fc-\(i)",
                    "type": "function_call",
                    "name": "functions.\(tool)",
                    "arguments": #"{"path":"File\#(i).swift"}"#,
                ] as [String: Any],
            ])
            jsonEvents.append([
                "type": "item.completed",
                "item": [
                    "id": "msg-\(i)",
                    "type": "agent_message",
                    "text": "Risultato passo \(i + 1). ",
                ] as [String: Any],
            ])
        }
        jsonEvents.append(["type": "turn.completed"])

        let (_, pipelineEvents) = parseAndAdapt(jsonEvents: jsonEvents)
        let state = reduce(pipelineEvents)

        let toolUseCount = state.timelineSegments.filter { $0.kind == .toolUse }.count
        XCTAssertGreaterThanOrEqual(
            toolUseCount, 4,
            "4 tool devono produrre almeno 4 segmenti toolUse, trovati \(toolUseCount)"
        )
    }

    /// Pipeline events count: numero di toolTraceArtifact vs numero di raw tool events.
    func testToolTraceCountMatchesRawToolEventCount() {
        let (streamEvents, pipelineEvents) = parseAndAdapt(jsonEvents: [
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-1",
                    "type": "function_call",
                    "name": "functions.coderide_read",
                    "arguments": #"{"path":"A.swift"}"#,
                ] as [String: Any],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "msg-1",
                    "type": "agent_message",
                    "text": "Fatto.",
                ] as [String: Any],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-2",
                    "type": "function_call",
                    "name": "functions.coderide_grep",
                    "arguments": #"{"query":"foo"}"#,
                ] as [String: Any],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-3",
                    "type": "function_call",
                    "name": "functions.coderide_write",
                    "arguments": #"{"path":"C.swift","content":"ok"}"#,
                ] as [String: Any],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "msg-2",
                    "type": "agent_message",
                    "text": "Completato.",
                ] as [String: Any],
            ],
            ["type": "turn.completed"],
        ])

        // Conta raw events che sono tool calls
        let rawToolCount = streamEvents.compactMap { e -> String? in
            if case .raw(let type, let payload) = e,
               type == "mcp_tool_call" || type == "function_call"
                || payload["mcp_tool"] != nil {
                return type
            }
            return nil
        }.count

        // Conta eventi pipeline che producono segmenti toolUse nel reducer:
        // toolTraceArtifact, filesArtifact e commandsArtifact tutti creano toolUse.
        let toolPipelineCount = pipelineEvents.filter {
            $0.kind == .toolTraceArtifact
                || $0.kind == .filesArtifact
                || $0.kind == .commandsArtifact
        }.count

        XCTAssertGreaterThanOrEqual(
            rawToolCount, 3,
            "Parser deve emettere almeno 3 raw tool events"
        )
        XCTAssertGreaterThanOrEqual(
            toolPipelineCount, rawToolCount,
            "Ogni raw tool event deve produrre un evento pipeline tool: \(toolPipelineCount) pipeline vs \(rawToolCount) raw"
        )
    }
}
