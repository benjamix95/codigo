import XCTest
@testable import CoderEngine

/// Test di regressione per output Codex con tool nativi (non MCP).
/// Quando Codex usa tool come `functions.read` (senza prefix `coderide_`),
/// il parser deve comunque produrre raw events che abilitano l'interleaving.
///
/// SCENARIO DI REGRESSIONE: Codex smette di usare tool MCP (coderide_*)
/// e torna ai tool nativi. Se il parsing non genera raw events per i tool nativi,
/// la timeline collassa in un blocco monolitico.
final class CodexCLINativeToolInterleavingRegressionTests: XCTestCase {

    // MARK: - Helpers

    private func parseJSON(_ events: [[String: Any]]) -> [StreamEvent] {
        var state = CodexCLIProvider.CodexStreamParserState()
        var out: [StreamEvent] = []
        for json in events {
            out.append(contentsOf: CodexCLIProvider.parseStreamJSONEvent(json, state: &state))
        }
        out.append(contentsOf: CodexCLIProvider.finalizeStreamJSONState(state: &state))
        return out
    }

    private func rawEvents(_ events: [StreamEvent]) -> [(String, [String: String])] {
        events.compactMap { e in
            if case .raw(let type, let payload) = e { return (type, payload) }
            return nil
        }
    }

    private func textDeltas(_ events: [StreamEvent]) -> [String] {
        events.compactMap { e in
            if case .textDelta(let text) = e { return text }
            return nil
        }
    }

    // MARK: - Native Tool Regression Tests

    /// Tool nativo functions.read DEVE produrre un raw event con metadata tool.
    func testNativeFunctionRead_ProducesRawEventWithToolMetadata() {
        let events = parseJSON([
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-1",
                    "type": "function_call",
                    "name": "functions.read",
                    "arguments": #"{"path":"Sources/App.swift"}"#,
                ],
            ],
            ["type": "turn.completed"],
        ])

        let raws = rawEvents(events)
        XCTAssertFalse(
            raws.isEmpty,
            "REGRESSIONE: functions.read DEVE produrre almeno un raw event"
        )
        let hasToolInfo = raws.contains { raw in
            raw.1["tool"] != nil || raw.1["tool_call_id"] != nil || raw.0 == "read"
        }
        XCTAssertTrue(
            hasToolInfo,
            "REGRESSIONE: il raw event per functions.read deve contenere metadata tool"
        )
    }

    /// Tool nativo functions.grep DEVE produrre un raw event.
    func testNativeFunctionGrep_ProducesRawEvent() {
        let events = parseJSON([
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-grep",
                    "type": "function_call",
                    "name": "functions.grep",
                    "arguments": #"{"query":"PolicyAck"}"#,
                ],
            ],
            ["type": "turn.completed"],
        ])

        let raws = rawEvents(events)
        XCTAssertFalse(
            raws.isEmpty,
            "REGRESSIONE: functions.grep DEVE produrre almeno un raw event"
        )
    }

    /// Tool nativo functions.bash DEVE produrre un raw event.
    func testNativeFunctionBash_ProducesRawEvent() {
        let events = parseJSON([
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-bash",
                    "type": "function_call",
                    "name": "functions.bash",
                    "arguments": #"{"command":"swift build"}"#,
                ],
            ],
            ["type": "turn.completed"],
        ])

        let raws = rawEvents(events)
        XCTAssertFalse(
            raws.isEmpty,
            "REGRESSIONE: functions.bash DEVE produrre almeno un raw event"
        )
    }

    /// Sequenza con solo tool nativi (no coderide_*) deve avere raw events per tutti.
    func testAllNativeTools_ProduceRawEvents() {
        let events = parseJSON([
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-read",
                    "type": "function_call",
                    "name": "functions.read",
                    "arguments": #"{"path":"A.swift"}"#,
                ],
            ],
            [
                "type": "item.completed",
                "item": ["type": "agent_message", "text": "Letto."],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-write",
                    "type": "function_call",
                    "name": "functions.write",
                    "arguments": #"{"path":"B.swift","content":"test"}"#,
                ],
            ],
            [
                "type": "item.completed",
                "item": ["type": "agent_message", "text": "Scritto."],
            ],
            ["type": "turn.completed"],
        ])

        let raws = rawEvents(events)
        let toolRaws = raws.filter { raw in
            raw.1["tool"] != nil || raw.1["tool_call_id"] != nil
        }
        XCTAssertGreaterThanOrEqual(
            toolRaws.count, 2,
            "REGRESSIONE: 2 function_call nativi → almeno 2 raw events tool, trovati \(toolRaws.count)"
        )
    }

    /// Confronto MCP vs Nativo: entrambi DEVONO produrre raw events con tool_call_id.
    func testMCPvsNative_BothProduceToolCallIds() {
        let mcpEvents = parseJSON([
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-mcp",
                    "type": "function_call",
                    "name": "functions.coderide_read",
                    "arguments": #"{"path":"A.swift"}"#,
                ],
            ],
            ["type": "turn.completed"],
        ])

        let nativeEvents = parseJSON([
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-native",
                    "type": "function_call",
                    "name": "functions.read",
                    "arguments": #"{"path":"A.swift"}"#,
                ],
            ],
            ["type": "turn.completed"],
        ])

        let mcpRaws = rawEvents(mcpEvents)
        let nativeRaws = rawEvents(nativeEvents)

        let mcpHasToolCallId = mcpRaws.contains { $0.1["tool_call_id"] != nil }
        let nativeHasToolCallId = nativeRaws.contains { $0.1["tool_call_id"] != nil }

        XCTAssertTrue(
            mcpHasToolCallId,
            "MCP function_call DEVE produrre tool_call_id nel raw event"
        )
        XCTAssertTrue(
            nativeHasToolCallId,
            "Native function_call DEVE produrre tool_call_id nel raw event"
        )
    }

    /// GUARDIA CRITICA: tool nativi devono generare raw events che permettono interleaving.
    func testRegressionGuard_NativeToolsStillEnableInterleaving() {
        let events = parseJSON([
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-1",
                    "type": "function_call",
                    "name": "functions.read",
                    "arguments": #"{"path":"Config.swift"}"#,
                ],
            ],
            [
                "type": "item.completed",
                "item": ["type": "agent_message", "text": "Ecco il config."],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-2",
                    "type": "function_call",
                    "name": "functions.grep",
                    "arguments": #"{"query":"timeout"}"#,
                ],
            ],
            [
                "type": "item.completed",
                "item": ["type": "agent_message", "text": "Trovati i timeout."],
            ],
            ["type": "turn.completed"],
        ])

        let raws = rawEvents(events)
        let toolRaws = raws.filter { raw in
            raw.1["tool"] != nil || raw.1["tool_call_id"] != nil
        }
        let texts = textDeltas(events)

        XCTAssertGreaterThanOrEqual(
            toolRaws.count, 2,
            "GUARDIA: 2 tool nativi → 2+ raw events, trovati \(toolRaws.count)"
        )
        XCTAssertGreaterThanOrEqual(
            texts.count, 1,
            "GUARDIA: devono esserci text deltas dagli agent_message"
        )
    }

    /// Verifica che un function_call nativo produce raw event con tipo corretto.
    func testNativeFunctionCall_RawEventType() {
        let events = parseJSON([
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "fc-sem",
                    "type": "function_call",
                    "name": "functions.semantic_search",
                    "arguments": #"{"query":"auth"}"#,
                ],
            ],
            ["type": "turn.completed"],
        ])

        let raws = rawEvents(events)
        let semRaw = raws.first { $0.1["tool_call_id"] == "fc-sem" }
        XCTAssertNotNil(semRaw, "Deve esistere un raw event per semantic_search")

        if let raw = semRaw {
            XCTAssertEqual(
                raw.1["tool"], "semantic_search",
                "Il tool deve essere 'semantic_search'"
            )
        }
    }
}
