import Foundation

extension CodeReviewMultiSwarmProvider {

    /// Entry point alternativo che usa la pipeline DAG per la fase di fix.
    /// Mantiene il flusso di analisi e parsing esistente, ma delega
    /// l'esecuzione parallela dei fix al PipelineFacade/WorkerPool.
    static func runReviewPipelineOrchestrated(
        prompt: String,
        context: WorkspaceContext,
        config: MultiSwarmReviewConfig,
        analysisProvider: any LLMProvider,
        executionProvider: any LLMProvider,
        execController: ExecutionController?,
        fileLockCoordinator: FileLockCoordinator,
        sessionState: CodeReviewSessionState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        try await ReviewPipelineCoordinator.shared.run(
            prompt: prompt,
            context: context,
            config: config,
            analysisProvider: analysisProvider,
            executionProvider: executionProvider,
            runtimeResolver: nil,
            execController: execController,
            fileLockCoordinator: fileLockCoordinator,
            sessionState: sessionState,
            continuation: continuation
        )
    }

    /// Mappa PipelineUIEvent in StreamEvent per il continuation della review.
    private static func bridgeEventToStreamContinuation(
        _ event: PipelineUIEvent,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) {
        switch event {
        case .taskStarted(let p):
            continuation.yield(.raw(type: "agent", payload: [
                "title": p.title,
                "detail": "started",
                "swarm_id": p.taskId,
                "group_id": "pipeline-\(p.taskId)"
            ]))
        case .taskCompleted(let p):
            continuation.yield(.raw(type: "agent", payload: [
                "title": p.agentName,
                "detail": "completed",
                "swarm_id": p.taskId,
                "group_id": "pipeline-\(p.taskId)"
            ]))
        case .textDelta(let p):
            continuation.yield(.textDelta(p.delta))
        case .textReplace(let p):
            continuation.yield(.textReplace(p.replacement))
        case .taskFailed(let p):
            continuation.yield(.textDelta(
                "\n[Task \(p.taskId) failed: \(p.error)]\n"
            ))
        case .jobCompleted(let p):
            continuation.yield(.textDelta(
                "\nPipeline review completed: "
                + "\(p.completedTasks)/\(p.totalTasks) tasks.\n"
            ))
            continuation.yield(.completed)
            continuation.finish()
        case .jobFailed(let p):
            continuation.yield(.textDelta(
                "\n[Pipeline review failed: \(p.reason)]\n"
            ))
            continuation.yield(.completed)
            continuation.finish()
        default:
            break
        }
    }
}
