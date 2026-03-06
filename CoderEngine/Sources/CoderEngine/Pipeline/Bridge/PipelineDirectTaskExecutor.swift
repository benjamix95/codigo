import Foundation

/// Executor opzionale per stage pipeline che devono bypassare il provider LLM.
public protocol PipelineDirectTaskExecutor: AnyObject, Sendable {
    func canExecute(task: TaskNode) async -> Bool

    func execute(
        task: TaskNode,
        agentName: String,
        role: AgentRole,
        provider: any LLMProvider,
        context: WorkspaceContext,
        jobId: String,
        delegate: AgentWorkerDelegate?
    ) async -> WorkerTaskResult
}
