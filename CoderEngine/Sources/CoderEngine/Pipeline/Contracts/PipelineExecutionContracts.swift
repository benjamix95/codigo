import Foundation

// MARK: - PipelineJobKind

/// Tipo semantico del job orchestrato dalla pipeline.
public enum PipelineJobKind: String, Codable, Sendable, Equatable, CaseIterable {
    case standard
    case debug
}

// MARK: - TaskExecutionStyle

/// Strategia di esecuzione del task.
///
/// - `multiAgentFlow`: comportamento corrente explorer/coder/reviewer/test/doc.
/// - `singleAgent`: un solo agente completa il task.
/// - `mcpTool`: stage esplicito basato su tool MCP.
/// - `nativeCommand`: stage eseguito da un executor nativo/non-LLM.
public enum TaskExecutionStyle: String, Codable, Sendable, Equatable, CaseIterable {
    case multiAgentFlow = "multi_agent_flow"
    case singleAgent = "single_agent"
    case mcpTool = "mcp_tool"
    case nativeCommand = "native_command"

    public var isDirectExecution: Bool {
        switch self {
        case .multiAgentFlow:
            return false
        case .singleAgent, .mcpTool, .nativeCommand:
            return true
        }
    }
}
