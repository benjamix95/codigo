import Foundation

/// Lightweight internal representation of a tool call used by the tool execution loop.
/// Previously part of CoderIDEMarkerParser; kept here for the native tool_call_suggested path.
struct CoderIDEMarker {
    let kind: String
    let payload: [String: String]
}

public final class ToolEnabledLLMProvider: LLMProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public var attachmentCapabilities: ProviderAttachmentCapabilities {
        base.attachmentCapabilities
    }

    let base: any LLMProvider
    let runtime: UnifiedToolRuntime
    let policy: ToolRuntimePolicy
    let executionScope: ExecutionScope
    let maxToolRounds: Int
    let maxAutonomousContinuationRounds = 4

    /// Optional factory for creating base LLM providers for subagent execution.
    /// If nil, subagents reuse the same base provider as the parent agent.
    let subagentProviderFactory: (@Sendable () -> any LLMProvider)?

    public init(
        base: any LLMProvider,
        runtime: UnifiedToolRuntime? = nil,
        policy: ToolRuntimePolicy = ToolRuntimePolicy(),
        executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        maxToolRounds: Int = 160,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) {
        self.base = base
        self.id = base.id
        self.displayName = base.displayName
        self.runtime = runtime ?? UnifiedToolRuntime(executionController: executionController, executionScope: executionScope)
        self.policy = policy
        self.executionScope = executionScope
        self.maxToolRounds = max(1, maxToolRounds)
        self.subagentProviderFactory = subagentProviderFactory
    }

    public func isAuthenticated() -> Bool {
        base.isAuthenticated()
    }

    public func debugToolRuntimeSnapshot() async -> ToolRuntimeDebugSnapshot {
        await runtime.debugSnapshot()
    }

    public func setBrowserBridge(_ bridge: (any BrowserBridge)?) async {
        await runtime.setBrowserBridge(bridge)
    }

    public func setTerminalBridge(_ bridge: (any TerminalBridge)?) async {
        await runtime.setTerminalBridge(bridge)
    }

}
