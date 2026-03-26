import Foundation

public extension WorkspaceContext {
    /// Standard agent system block when `systemPromptOverride` is nil (tool-enabled providers merge tool protocol separately).
    var resolvedStandardAgentSystemPrompt: String {
        preferDebuggerPromptProfile
            ? SystemPrompts.debugSessionAgentBase
            : SystemPrompts.taskCompletionStrict
    }
}
