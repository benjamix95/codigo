import Foundation

extension AgentWorkerAdapter {
    static func executeDirectTaskIfNeeded(
        executor: any PipelineDirectTaskExecutor,
        task: TaskNode,
        agentName: String,
        role: AgentRole,
        provider: any LLMProvider,
        context: WorkspaceContext,
        jobId: String,
        delegate: AgentWorkerDelegate?
    ) async -> WorkerTaskResult? {
        guard await executor.canExecute(task: task) else {
            return nil
        }
        return await executor.execute(
            task: task,
            agentName: agentName,
            role: role,
            provider: provider,
            context: context,
            jobId: jobId,
            delegate: delegate
        )
    }
}
