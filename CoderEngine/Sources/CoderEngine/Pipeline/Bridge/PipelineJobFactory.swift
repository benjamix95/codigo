import Foundation

// MARK: - PipelineJobFactory

/// Factory per creare `PipelineJob` e `TaskNode` DAG da input applicativi.
/// Converte plan todos, chat messages e review scope in strutture pipeline.
public enum PipelineJobFactory {

    // MARK: - Plan Build

    /// Crea un job + task DAG da una lista di plan todos.
    /// Ogni todo diventa un TaskNode con dipendenza sequenziale sul precedente.
    public static func fromPlanBuild(
        todos: [PlanTodoItem],
        workspace: String,
        providerId: String,
        mode: PipelineMode = .strict,
        maxConcurrentWorkers: Int = 4,
        jobTimeoutMs: Int = 1_800_000
    ) -> (job: PipelineJob, tasks: [TaskNode]) {
        let jobId = "plan_\(UUID().uuidString.prefix(8))"

        let job = PipelineJob(
            jobId: jobId,
            workspace: workspace,
            request: "Plan Build (\(todos.count) steps)",
            mode: mode,
            selectedProviderProfile: providerId,
            jobTimeoutMs: jobTimeoutMs,
            maxConcurrentWorkers: maxConcurrentWorkers
        )

        var tasks: [TaskNode] = []
        var previousId: String?

        for (index, todo) in todos.enumerated() {
            let taskId = "task_\(index)_\(sanitizeForId(todo.title))"
            var node = TaskNode(
                taskId: taskId,
                title: todo.title,
                dependsOn: previousId.map { [$0] } ?? [],
                priority: max(0, 100 - index * 5),
                risk: estimateRisk(from: todo.title),
                taskType: inferTaskType(from: todo.title),
                fileScope: todo.linkedFiles ?? [],
                status: .pending,
                timeoutMs: 120_000
            )
            node.deriveTaskLabel()
            tasks.append(node)
            previousId = taskId
        }

        return (job, tasks)
    }

    // MARK: - Chat Message (single task)

    /// Crea un job con un singolo task per un messaggio chat in modalita' agent.
    public static func fromChatMessage(
        prompt: String,
        workspace: String,
        providerId: String,
        mode: PipelineMode = .fast,
        jobTimeoutMs: Int = 600_000
    ) -> (job: PipelineJob, tasks: [TaskNode]) {
        let jobId = "chat_\(UUID().uuidString.prefix(8))"

        let job = PipelineJob(
            jobId: jobId,
            workspace: workspace,
            request: String(prompt.prefix(200)),
            mode: mode,
            selectedProviderProfile: providerId,
            jobTimeoutMs: jobTimeoutMs,
            maxConcurrentWorkers: 1
        )

        let truncatedTitle = String(prompt.prefix(80))
        var node = TaskNode(
            taskId: "task_chat_0",
            title: truncatedTitle.isEmpty ? "Chat task" : truncatedTitle,
            priority: 50,
            risk: .low,
            taskType: .feature,
            metadata: [
                "pipeline_full_prompt": prompt
            ],
            status: .pending,
            timeoutMs: min(jobTimeoutMs, 300_000)
        )
        node.deriveTaskLabel()

        return (job, [node])
    }

    // MARK: - Code Review

    /// Crea un job + task DAG per una code review multi-file.
    /// Genera un task per l'analisi e uno per ogni file da fixare.
    public static func fromCodeReview(
        scope: ReviewScope,
        filesToReview: [String],
        workspace: String,
        analysisProviderId: String,
        executionProviderId: String,
        maxWorkers: Int = 4,
        maxRounds: Int = 3
    ) -> (job: PipelineJob, tasks: [TaskNode]) {
        let jobId = "review_\(UUID().uuidString.prefix(8))"

        let job = PipelineJob(
            jobId: jobId,
            workspace: workspace,
            request: "Code Review (\(filesToReview.count) files, scope: \(scope.rawValue))",
            mode: .strict,
            selectedProviderProfile: analysisProviderId,
            jobTimeoutMs: 1_200_000,
            maxConcurrentWorkers: maxWorkers
        )

        var tasks: [TaskNode] = []

        var analysisNode = TaskNode(
            taskId: "task_analysis",
            title: "Review Analysis",
            priority: 100,
            risk: .low,
            taskType: .refactor,
            fileScope: filesToReview,
            status: .pending,
            timeoutMs: 180_000
        )
        analysisNode.deriveTaskLabel()
        tasks.append(analysisNode)

        for (index, file) in filesToReview.enumerated() {
            let fileName = (file as NSString).lastPathComponent
            var fixNode = TaskNode(
                taskId: "task_fix_\(index)_\(sanitizeForId(fileName))",
                title: "Fix: \(fileName)",
                dependsOn: ["task_analysis"],
                priority: 80 - index,
                risk: .medium,
                taskType: .bugfix,
                fileScope: [file],
                status: .pending,
                timeoutMs: 120_000
            )
            fixNode.deriveTaskLabel()
            tasks.append(fixNode)
        }

        return (job, tasks)
    }

    // MARK: - Private Helpers

    private static func sanitizeForId(_ text: String) -> String {
        let cleaned = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return String(cleaned.prefix(30))
    }

    private static func estimateRisk(from title: String) -> RiskLevel {
        let lower = title.lowercased()
        if lower.contains("delete") || lower.contains("remove") || lower.contains("migrate") {
            return .high
        }
        if lower.contains("refactor") || lower.contains("rename") {
            return .medium
        }
        if lower.contains("test") || lower.contains("doc") || lower.contains("comment") {
            return .low
        }
        return .medium
    }

    private static func inferTaskType(from title: String) -> TaskType {
        let lower = title.lowercased()
        if lower.contains("test") { return .test }
        if lower.contains("doc") || lower.contains("readme") { return .docs }
        if lower.contains("fix") || lower.contains("bug") { return .bugfix }
        if lower.contains("refactor") || lower.contains("clean") { return .refactor }
        return .feature
    }
}

// MARK: - PlanTodoItem

/// Rappresentazione minimale di un todo dal plan, usata dalla factory.
public struct PlanTodoItem: Sendable {
    public let title: String
    public let linkedFiles: [String]?

    public init(title: String, linkedFiles: [String]? = nil) {
        self.title = title
        self.linkedFiles = linkedFiles
    }
}
