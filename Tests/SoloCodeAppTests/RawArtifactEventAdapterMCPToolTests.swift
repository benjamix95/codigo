import XCTest
@testable import CoderIDE
import CoderEngine

/// Test che verificano la conversione di raw events MCP/function_call in toolTraceArtifact.
/// REGOLA: questi test NON devono essere modificati per farli passare.
/// Se falliscono, il bug è nel RawArtifactEventAdapter, non nei test.
///
/// GAP COPERTO: senza questi test, il Codex può regredire a output monolitico
/// senza tool trace nella timeline e tutti i test di interleaving al livello
/// reducer passano comunque (perché iniettano toolTraceArtifact sinteticamente).
@MainActor
final class RawArtifactEventAdapterMCPToolTests: XCTestCase {

    private let conversationId = UUID()
    private let assistantMessageId = UUID()
    private let turnId = "test-turn"
    private let providerId = "codex-cli"

    private func adapt(rawType: String, payload: [String: String]) -> [ChatPipelineEvent] {
        RawArtifactEventAdapter.events(
            rawType: rawType,
            payload: payload,
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId,
            providerId: providerId
        )
    }

    // MARK: - MCP Tool Call → toolTraceArtifact

    func testMCPToolCallProducesToolTraceArtifact() {
        let events = adapt(rawType: "mcp_tool_call", payload: [
            "mcp_tool": "coderide_read",
            "status": "completed",
            "title": "coderide_read",
            "detail": "Reading Sources/App.swift",
        ])
        XCTAssertFalse(events.isEmpty, "mcp_tool_call DEVE produrre almeno un ChatPipelineEvent")
        let toolTraces = events.filter { $0.kind == .toolTraceArtifact }
        XCTAssertEqual(toolTraces.count, 1, "mcp_tool_call DEVE produrre esattamente 1 toolTraceArtifact")
    }

    func testMCPToolCallWithCoderidePrefixProducesToolTrace() {
        for tool in ["coderide_read", "coderide_grep", "coderide_str_replace", "coderide_semantic_search", "coderide_write"] {
            let events = adapt(rawType: "mcp_tool_call", payload: [
                "mcp_tool": tool,
                "status": "completed",
                "title": tool,
            ])
            let toolTraces = events.filter { $0.kind == .toolTraceArtifact }
            XCTAssertEqual(toolTraces.count, 1, "\(tool) mcp_tool_call DEVE produrre toolTraceArtifact")
        }
    }

    func testMCPToolCallWithoutCoderidePrefixStillProducesToolTrace() {
        let events = adapt(rawType: "mcp_tool_call", payload: [
            "mcp_tool": "custom_mcp_tool",
            "status": "completed",
            "title": "custom_mcp_tool",
        ])
        let toolTraces = events.filter { $0.kind == .toolTraceArtifact }
        XCTAssertEqual(toolTraces.count, 1, "Qualsiasi mcp_tool_call DEVE produrre toolTraceArtifact")
    }

    func testMCPToolCallPreservesToolNameInPayload() {
        let events = adapt(rawType: "mcp_tool_call", payload: [
            "mcp_tool": "coderide_grep",
            "status": "completed",
            "title": "coderide_grep",
            "detail": "Searching pattern in Sources/",
        ])
        guard let trace = events.first(where: { $0.kind == .toolTraceArtifact }) else {
            XCTFail("Manca toolTraceArtifact"); return
        }
        XCTAssertTrue(
            (trace.payload["title"] ?? "").contains("grep"),
            "Il title del toolTraceArtifact deve contenere il nome del tool"
        )
    }

    // MARK: - Function Call → toolTraceArtifact

    func testFunctionCallProducesToolTraceArtifact() {
        let events = adapt(rawType: "function_call", payload: [
            "name": "functions.coderide_read",
            "status": "completed",
            "title": "coderide_read",
        ])
        let toolTraces = events.filter { $0.kind == .toolTraceArtifact }
        XCTAssertEqual(toolTraces.count, 1, "function_call DEVE produrre toolTraceArtifact")
    }

    func testNativeFunctionCallProducesToolTraceArtifact() {
        let events = adapt(rawType: "function_call", payload: [
            "name": "functions.read",
            "status": "completed",
            "title": "read",
        ])
        let toolTraces = events.filter { $0.kind == .toolTraceArtifact }
        XCTAssertEqual(toolTraces.count, 1, "function_call nativo DEVE produrre toolTraceArtifact")
    }

    func testFunctionCallStripsFunctionsPrefix() {
        let events = adapt(rawType: "function_call", payload: [
            "name": "functions.coderide_read",
        ])
        guard let trace = events.first(where: { $0.kind == .toolTraceArtifact }) else {
            XCTFail("Manca toolTraceArtifact"); return
        }
        XCTAssertEqual(
            trace.payload["title"], "coderide_read",
            "Il prefisso 'functions.' deve essere rimosso dal title"
        )
    }

    // MARK: - Negative: non-tool raw events unchanged

    func testReasoningRawEventDoesNotProduceToolTrace() {
        let events = adapt(rawType: "reasoning", payload: [
            "output": "Thinking about the problem...",
            "group_id": "reasoning",
        ])
        let toolTraces = events.filter { $0.kind == .toolTraceArtifact }
        XCTAssertEqual(toolTraces.count, 0, "reasoning NON deve produrre toolTraceArtifact")
    }

    func testTurnStartedDoesNotProduceToolTrace() {
        let events = adapt(rawType: "turn_started", payload: [
            "status": "started",
        ])
        let toolTraces = events.filter { $0.kind == .toolTraceArtifact }
        XCTAssertEqual(toolTraces.count, 0, "turn_started NON deve produrre toolTraceArtifact")
    }

    func testExistingFileChangeHandlingUnchanged() {
        let events = adapt(rawType: "edit", payload: [
            "path": "Sources/App.swift",
        ])
        let fileEvents = events.filter { $0.kind == .filesArtifact }
        XCTAssertEqual(fileEvents.count, 1, "edit deve produrre filesArtifact come prima")
        let toolTraces = events.filter { $0.kind == .toolTraceArtifact }
        XCTAssertEqual(toolTraces.count, 0, "edit NON deve produrre toolTraceArtifact")
    }

    // MARK: - End-to-end: raw events → adapter → reducer → timeline

    func testMCPToolCallThroughReducerProducesInterleavedTimeline() {
        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId,
            providerId: providerId
        )

        // Step 1: textDelta
        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: turnId,
                sequence: 1,
                source: providerId,
                kind: .textDelta,
                payload: ["delta": "Analizzo il file. ", "stream_id": "main"]
            )
        )

        // Step 2: mcp_tool_call → adapter → reducer
        let toolEvents = adapt(rawType: "mcp_tool_call", payload: [
            "mcp_tool": "coderide_read",
            "status": "completed",
            "title": "coderide_read",
            "detail": "Reading Config.swift",
        ])
        for (i, event) in toolEvents.enumerated() {
            state = ChatPipelineReducer.apply(
                state: state,
                event: ChatPipelineEvent(
                    conversationId: event.conversationId,
                    assistantMessageId: event.assistantMessageId,
                    turnId: event.turnId,
                    sequence: 2 + i,
                    source: event.source,
                    kind: event.kind,
                    payload: event.payload
                )
            )
        }

        // Step 3: textDelta
        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: turnId,
                sequence: 10,
                source: providerId,
                kind: .textDelta,
                payload: ["delta": "Ecco il risultato.", "stream_id": "main"]
            )
        )

        // INVARIANTE: la timeline DEVE essere interleaved
        let kinds = state.timelineSegments.map(\.kind)
        XCTAssertEqual(
            kinds, [.text, .toolUse, .text],
            "CONTRATTO: text → mcp_tool_call → text DEVE produrre [text, toolUse, text], trovato \(kinds)"
        )
    }

    func testMultipleMCPToolCallsProduceMultipleToolUseSegments() {
        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId,
            providerId: providerId
        )
        var seq = 1

        let tools = ["coderide_read", "coderide_grep", "coderide_str_replace"]
        for tool in tools {
            state = ChatPipelineReducer.apply(
                state: state,
                event: ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: turnId,
                    sequence: seq,
                    source: providerId,
                    kind: .textDelta,
                    payload: ["delta": "Passo per \(tool). ", "stream_id": "main"]
                )
            )
            seq += 1

            let toolEvents = adapt(rawType: "mcp_tool_call", payload: [
                "mcp_tool": tool,
                "status": "completed",
                "title": tool,
            ])
            for event in toolEvents {
                state = ChatPipelineReducer.apply(
                    state: state,
                    event: ChatPipelineEvent(
                        conversationId: event.conversationId,
                        assistantMessageId: event.assistantMessageId,
                        turnId: event.turnId,
                        sequence: seq,
                        source: event.source,
                        kind: event.kind,
                        payload: event.payload
                    )
                )
                seq += 1
            }
        }

        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: turnId,
                sequence: seq,
                source: providerId,
                kind: .textDelta,
                payload: ["delta": "Fine.", "stream_id": "main"]
            )
        )

        let toolUseCount = state.timelineSegments.filter { $0.kind == .toolUse }.count
        XCTAssertEqual(
            toolUseCount, 3,
            "3 mcp_tool_call devono produrre 3 segmenti toolUse, trovati \(toolUseCount)"
        )

        let textCount = state.textSegments.count
        XCTAssertEqual(
            textCount, 4,
            "3 tool + testo iniziale e finale → 4 segmenti text, trovati \(textCount)"
        )
    }
}
