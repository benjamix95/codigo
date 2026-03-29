import XCTest
@testable import CoderIDE
import CoderEngine

/// Test che proteggono il contratto del bridge tra raw events Codex
/// e la generazione di pipeline events via RawArtifactEventAdapter.
///
/// Questi test verificano che tool types producano toolTraceArtifact,
/// impedendo regressioni monolitiche quando il mapping viene modificato.
final class CodexToolTraceBridgeContractTests: XCTestCase {

    // MARK: - Helpers

    private let testConversationId = UUID()
    private let testAssistantMessageId = UUID()
    private let testTurnId = "test-turn"
    private let testProviderId = "codex-cli"

    private func adapt(
        rawType: String,
        payload: [String: String] = [:]
    ) -> [ChatPipelineEvent] {
        RawArtifactEventAdapter.events(
            rawType: rawType,
            payload: payload,
            conversationId: testConversationId,
            assistantMessageId: testAssistantMessageId,
            turnId: testTurnId,
            providerId: testProviderId
        )
    }

    // MARK: - Artifact Types: Commands

    func testRawArtifactAdapter_CommandExecution_ProducesCommandsArtifact() {
        let events = adapt(rawType: "command_execution", payload: ["command": "swift build"])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .commandsArtifact)
    }

    func testRawArtifactAdapter_Bash_ProducesCommandsArtifact() {
        let events = adapt(rawType: "bash", payload: ["command": "git status"])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .commandsArtifact)
    }

    // MARK: - Artifact Types: Files

    func testRawArtifactAdapter_FileChange_ProducesFilesArtifact() {
        let events = adapt(rawType: "file_change", payload: ["path": "Sources/App.swift"])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .filesArtifact)
    }

    func testRawArtifactAdapter_Edit_ProducesFilesArtifact() {
        let events = adapt(rawType: "edit", payload: ["path": "Sources/Config.swift"])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .filesArtifact)
    }

    func testRawArtifactAdapter_Write_ProducesFilesArtifact() {
        let events = adapt(rawType: "write", payload: ["path": "Sources/New.swift"])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .filesArtifact)
    }

    func testRawArtifactAdapter_ApplyPatch_ProducesFilesArtifact() {
        let events = adapt(rawType: "apply_patch", payload: ["path": "Sources/Fix.swift"])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .filesArtifact)
    }

    // MARK: - Artifact Types: Mermaid

    func testRawArtifactAdapter_MermaidRender_ProducesMermaidArtifact() {
        let events = adapt(rawType: "mermaid_render", payload: ["code": "graph TD; A-->B", "title": "Flow"])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .mermaidArtifact)
    }

    // MARK: - Lifecycle

    func testRawArtifactAdapter_TurnStarted_ProducesTurnStarted() {
        let events = adapt(rawType: "turn_started", payload: ["status": "streaming"])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .turnStarted)
    }

    // MARK: - CRITICO: Tool Types → toolTraceArtifact

    /// GUARDIA ANTI-REGRESSIONE: i tool MCP e nativi DEVONO produrre toolTraceArtifact.
    /// Se uno di questi test fallisce, l'interleaving è rotto.

    func testRawArtifactAdapter_ToolRead_ProducesToolTraceArtifact() {
        let events = adapt(rawType: "read", payload: ["tool": "read", "path": "A.swift"])
        XCTAssertEqual(events.count, 1, "read DEVE produrre toolTraceArtifact")
        XCTAssertEqual(events.first?.kind, .toolTraceArtifact)
    }

    func testRawArtifactAdapter_ToolGrep_ProducesToolTraceArtifact() {
        let events = adapt(rawType: "grep", payload: ["tool": "grep", "query": "test"])
        XCTAssertEqual(events.count, 1, "grep DEVE produrre toolTraceArtifact")
        XCTAssertEqual(events.first?.kind, .toolTraceArtifact)
    }

    func testRawArtifactAdapter_ToolSemanticSearch_ProducesToolTraceArtifact() {
        let events = adapt(rawType: "semantic_search", payload: ["tool": "semantic_search"])
        XCTAssertEqual(events.count, 1, "semantic_search DEVE produrre toolTraceArtifact")
        XCTAssertEqual(events.first?.kind, .toolTraceArtifact)
    }

    func testRawArtifactAdapter_FunctionCall_ProducesToolTraceArtifact() {
        let events = adapt(rawType: "function_call", payload: ["tool": "coderide_read", "tool_call_id": "fc-1"])
        XCTAssertEqual(events.count, 1, "function_call DEVE produrre toolTraceArtifact")
        XCTAssertEqual(events.first?.kind, .toolTraceArtifact)
    }

    func testRawArtifactAdapter_MCPToolCall_ProducesToolTraceArtifact() {
        let events = adapt(rawType: "mcp_tool_call", payload: ["mcp_tool": "coderide_todo_write", "is_mcp": "true"])
        XCTAssertEqual(events.count, 1, "mcp_tool_call DEVE produrre toolTraceArtifact")
        XCTAssertEqual(events.first?.kind, .toolTraceArtifact)
    }

    func testRawArtifactAdapter_FindSymbol_ProducesToolTraceArtifact() {
        let events = adapt(rawType: "find_symbol", payload: ["tool": "find_symbol"])
        XCTAssertEqual(events.count, 1, "find_symbol DEVE produrre toolTraceArtifact")
        XCTAssertEqual(events.first?.kind, .toolTraceArtifact)
    }

    func testRawArtifactAdapter_FindReferences_ProducesToolTraceArtifact() {
        let events = adapt(rawType: "find_references", payload: ["tool": "find_references"])
        XCTAssertEqual(events.count, 1, "find_references DEVE produrre toolTraceArtifact")
        XCTAssertEqual(events.first?.kind, .toolTraceArtifact)
    }

    func testRawArtifactAdapter_ListDir_ProducesToolTraceArtifact() {
        let events = adapt(rawType: "list_dir", payload: ["tool": "list_dir"])
        XCTAssertEqual(events.count, 1, "list_dir DEVE produrre toolTraceArtifact")
        XCTAssertEqual(events.first?.kind, .toolTraceArtifact)
    }

    func testRawArtifactAdapter_FindFiles_ProducesToolTraceArtifact() {
        let events = adapt(rawType: "find_files", payload: ["tool": "find_files"])
        XCTAssertEqual(events.count, 1, "find_files DEVE produrre toolTraceArtifact")
        XCTAssertEqual(events.first?.kind, .toolTraceArtifact)
    }

    func testRawArtifactAdapter_CodebaseSearch_ProducesToolTraceArtifact() {
        let events = adapt(rawType: "codebase_search", payload: ["tool": "codebase_search"])
        XCTAssertEqual(events.count, 1, "codebase_search DEVE produrre toolTraceArtifact")
        XCTAssertEqual(events.first?.kind, .toolTraceArtifact)
    }

    func testRawArtifactAdapter_FileOutline_ProducesToolTraceArtifact() {
        let events = adapt(rawType: "file_outline", payload: ["tool": "file_outline"])
        XCTAssertEqual(events.count, 1, "file_outline DEVE produrre toolTraceArtifact")
        XCTAssertEqual(events.first?.kind, .toolTraceArtifact)
    }

    // MARK: - Guardia: tutti i tool types critici producono toolTraceArtifact

    func testAllCriticalToolTypesProduceToolTraceArtifact() {
        let criticalToolTypes = [
            "read", "grep", "semantic_search", "codebase_search",
            "find_symbol", "find_references", "find_files", "list_dir",
            "file_outline", "function_call", "mcp_tool_call",
        ]

        for toolType in criticalToolTypes {
            let events = adapt(rawType: toolType, payload: ["tool": toolType])
            XCTAssertFalse(
                events.isEmpty,
                "GUARDIA: '\(toolType)' DEVE produrre toolTraceArtifact per abilitare interleaving"
            )
            XCTAssertEqual(
                events.first?.kind, .toolTraceArtifact,
                "GUARDIA: '\(toolType)' deve produrre .toolTraceArtifact, non \(String(describing: events.first?.kind))"
            )
        }
    }

    // MARK: - Guardia: artifact types specifici funzionano

    func testHandledArtifactTypesProduceNonEmptyEvents() {
        let handledTypes: [(String, [String: String])] = [
            ("command_execution", ["command": "test"]),
            ("bash", ["command": "test"]),
            ("file_change", ["path": "test.swift"]),
            ("edit", ["path": "test.swift"]),
            ("write", ["path": "test.swift"]),
            ("apply_patch", ["path": "test.swift"]),
            ("create_file", ["path": "test.swift"]),
            ("delete_file", ["path": "test.swift"]),
            ("mermaid_render", ["code": "graph TD"]),
            ("turn_started", ["status": "streaming"]),
        ]

        for (rawType, payload) in handledTypes {
            let events = adapt(rawType: rawType, payload: payload)
            XCTAssertFalse(
                events.isEmpty,
                "Il tipo '\(rawType)' DEVE produrre eventi — contratto violato!"
            )
        }
    }

    // MARK: - Guardia: tipi sconosciuti restituiscono vuoto

    func testUnknownRawTypesReturnEmpty() {
        let unknownTypes = ["unknown", "custom_event", "internal_log", "metric"]
        for rawType in unknownTypes {
            let events = adapt(rawType: rawType, payload: [:])
            XCTAssertTrue(
                events.isEmpty,
                "Tipo sconosciuto '\(rawType)' non deve produrre eventi"
            )
        }
    }

    // MARK: - Tool title resolution

    func testToolTraceTitle_UsesMCPToolName() {
        let events = adapt(rawType: "read", payload: ["mcp_tool": "coderide_read"])
        XCTAssertEqual(events.first?.payload["title"], "coderide_read")
    }

    func testToolTraceTitle_FallsBackToToolName() {
        let events = adapt(rawType: "read", payload: ["tool": "read"])
        XCTAssertEqual(events.first?.payload["title"], "read")
    }

    func testToolTraceTitle_FallsBackToRawType() {
        let events = adapt(rawType: "grep", payload: [:])
        XCTAssertEqual(events.first?.payload["title"], "grep")
    }
}
