import Foundation
import os

// MARK: - AgentWorkerAdapter

/// Adapter che esegue task della pipeline chiamando `LLMProvider.send()`.
///
/// Responsabilita':
/// - Costruire il prompt appropriato per ruolo agente e task
/// - Invocare il provider LLM e consumare lo stream
/// - Raccogliere il testo completo e restituire `WorkerTaskResult`
/// - Emettere eventi di streaming via delegate
/// - Gestire timeout e cancellation
public actor AgentWorkerAdapter {

    private static let logger = Logger(
        subsystem: "com.solocode.engine", category: "AgentWorkerAdapter"
    )

    private let provider: any LLMProvider
    private let context: WorkspaceContext
    private let jobId: String
    private let config: AgentWorkerAdapterConfig
    private let directTaskExecutor: (any PipelineDirectTaskExecutor)?
    public weak var delegate: AgentWorkerDelegate?

    public init(
        provider: any LLMProvider,
        context: WorkspaceContext,
        jobId: String,
        config: AgentWorkerAdapterConfig = AgentWorkerAdapterConfig(),
        directTaskExecutor: (any PipelineDirectTaskExecutor)? = nil
    ) {
        self.provider = provider
        self.context = context
        self.jobId = jobId
        self.config = config
        self.directTaskExecutor = directTaskExecutor
    }

    public func setDelegate(_ newDelegate: AgentWorkerDelegate?) {
        self.delegate = newDelegate
    }

    // MARK: - Execute Task

    /// Crea la closure di lavoro per il `WorkerPool.dispatch`.
    /// Restituisce un `@Sendable` closure che esegue la call LLM.
    public func makeWorkClosure(
        task: TaskNode,
        agentName: String,
        role: AgentRole
    ) -> @Sendable () async -> WorkerTaskResult {
        let provider = self.provider
        let context = self.context
        let jobId = self.jobId
        let config = self.config
        let delegate = self.delegate
        let directTaskExecutor = self.directTaskExecutor
        let taskId = task.taskId

        return {
            let startedAt = Date()
            do {
                if let directTaskExecutor,
                   let directResult = await Self.executeDirectTaskIfNeeded(
                    executor: directTaskExecutor,
                    task: task,
                    agentName: agentName,
                    role: role,
                    provider: provider,
                    context: context,
                    jobId: jobId,
                    delegate: delegate
                   )
                {
                    return directResult
                }

                let prompt = Self.buildPrompt(
                    task: task, role: role,
                    agentName: agentName, jobId: jobId
                )

                let stream = try await provider.send(
                    prompt: prompt,
                    context: context,
                    attachments: nil
                )

                let fullText = try await Self.consumeStream(
                    stream: stream,
                    jobId: jobId,
                    taskId: taskId,
                    delegate: delegate,
                    config: config
                )

                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

                let envelope = AgentActionEnvelope(
                    agentId: "\(agentName)_\(UUID().uuidString.prefix(6))",
                    agentName: agentName,
                    agentRole: role,
                    jobId: jobId,
                    taskId: taskId,
                    actions: [AgentAction(
                        type: Self.actionType(for: role),
                        summary: String(fullText.prefix(500))
                    )],
                    confidence: fullText.isEmpty ? 0.0 : 0.8
                )

                return WorkerTaskResult(
                    taskId: taskId,
                    agentName: agentName,
                    agentRole: role,
                    success: true,
                    envelope: envelope,
                    durationMs: durationMs,
                    providerId: provider.id
                )
            } catch {
                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                let readable = Self.readableErrorMessage(error)
                Self.logger.error(
                    "Pipeline task \(taskId) failed after \(durationMs)ms — \(String(describing: error))"
                )
                return WorkerTaskResult(
                    taskId: taskId,
                    agentName: agentName,
                    agentRole: role,
                    success: false,
                    error: readable,
                    durationMs: durationMs,
                    providerId: provider.id
                )
            }
        }
    }

    // MARK: - Stream Consumption

    static func consumeStream(
        stream: AsyncThrowingStream<StreamEvent, Error>,
        jobId: String,
        taskId: String,
        delegate: AgentWorkerDelegate?,
        config: AgentWorkerAdapterConfig
    ) async throws -> String {
        var parts: [String] = []
        var totalLength = 0

        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                if totalLength + delta.count <= config.maxTextLength {
                    parts.append(delta)
                    totalLength += delta.count
                }
                await delegate?.worker(
                    jobId: jobId, taskId: taskId,
                    didEmitTextDelta: delta
                )

            case .textReplace(let replacement):
                parts = replacement.isEmpty ? [] : [replacement]
                totalLength = replacement.count
                await delegate?.worker(
                    jobId: jobId, taskId: taskId,
                    didReplace: replacement
                )

            case .error(let message):
                throw AgentWorkerError.streamError(message)

            case .raw(let type, let payload):
                await delegate?.worker(
                    jobId: jobId, taskId: taskId,
                    didEmitRaw: type, payload: payload
                )

            case .started, .completed:
                break
            }
        }

        return parts.joined()
    }

    // MARK: - Helpers

    static func actionType(for role: AgentRole) -> ActionType {
        switch role {
        case .coder, .debugger: return .patchProposal
        case .testWriter: return .testUpdate
        case .docWriter: return .docUpdate
        default: return .analysisNote
        }
    }

    static func readableErrorMessage(_ error: Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty,
           !description.hasPrefix("The operation couldn't be completed. (CoderEngine.AgentWorkerError") {
            return description
        }

        if let workerError = error as? AgentWorkerError,
           let workerDescription = workerError.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workerDescription.isEmpty {
            return workerDescription
        }

        return String(describing: error)
    }
}
