import Foundation

// MARK: - AgentWorkerAdapterConfig

public struct AgentWorkerAdapterConfig: Sendable {
    public let streamTimeoutSec: Int
    public let maxTextLength: Int

    public init(
        streamTimeoutSec: Int = 300,
        maxTextLength: Int = 500_000
    ) {
        self.streamTimeoutSec = streamTimeoutSec
        self.maxTextLength = maxTextLength
    }
}

// MARK: - AgentWorkerDelegate

/// Delegate per ricevere eventi di streaming in tempo reale dal worker.
public protocol AgentWorkerDelegate: AnyObject, Sendable {
    func worker(
        jobId: String, taskId: String,
        didEmitTextDelta delta: String
    ) async
    func worker(
        jobId: String, taskId: String,
        didReplace replacement: String
    ) async
    func worker(
        jobId: String, taskId: String,
        didEmitRaw type: String, payload: [String: String]
    ) async
}

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

    private let provider: any LLMProvider
    private let context: WorkspaceContext
    private let jobId: String
    private let config: AgentWorkerAdapterConfig
    public weak var delegate: AgentWorkerDelegate?

    public init(
        provider: any LLMProvider,
        context: WorkspaceContext,
        jobId: String,
        config: AgentWorkerAdapterConfig = AgentWorkerAdapterConfig()
    ) {
        self.provider = provider
        self.context = context
        self.jobId = jobId
        self.config = config
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
        let taskId = task.taskId
        let title = task.title

        return {
            let startedAt = Date()
            do {
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
                return WorkerTaskResult(
                    taskId: taskId,
                    agentName: agentName,
                    agentRole: role,
                    success: false,
                    error: error.localizedDescription,
                    durationMs: durationMs,
                    providerId: provider.id
                )
            }
        }
    }

    // MARK: - Stream Consumption

    private static func consumeStream(
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

    // MARK: - Prompt Building

    private static func buildPrompt(
        task: TaskNode,
        role: AgentRole,
        agentName: String,
        jobId: String
    ) -> String {
        let roleInstructions = roleSpecificInstructions(for: role)
        let fileContext = task.fileScope.isEmpty
            ? ""
            : "\n\nFile scope: \(task.fileScope.joined(separator: ", "))"

        return """
        You are agent "\(agentName)" with role \(role.displayName).
        Job: \(jobId) | Task: \(task.taskId)

        ## Task
        \(task.title)
        \(fileContext)

        ## Role Instructions
        \(roleInstructions)

        Execute the task precisely. Be concise and focused.
        """
    }

    private static func roleSpecificInstructions(
        for role: AgentRole
    ) -> String {
        switch role {
        case .planner:
            return "Analyze the request and produce a structured execution plan."
        case .explorer:
            return "Explore the codebase to gather context needed for the task."
        case .coder:
            return "Implement the changes as described. Write clean, minimal code."
        case .debugger:
            return "Investigate and fix the issue. Explain root cause briefly."
        case .reviewer:
            return "Review the code changes. Report findings as structured feedback."
        case .testWriter:
            return "Write tests covering the changed functionality."
        case .docWriter:
            return "Update documentation to reflect the changes made."
        case .securityAuditor:
            return "Audit code for security vulnerabilities. Report findings."
        }
    }

    private static func actionType(for role: AgentRole) -> ActionType {
        switch role {
        case .coder, .debugger: return .patchProposal
        case .testWriter: return .testUpdate
        case .docWriter: return .docUpdate
        default: return .analysisNote
        }
    }
}

// MARK: - AgentWorkerError

public enum AgentWorkerError: Error, Sendable {
    case streamError(String)
    case timeout(taskId: String, elapsedMs: Int)
}
