import Foundation

// MARK: - PipelineJobFactory

/// Factory per creare `PipelineJob` e `TaskNode` DAG da input applicativi.
/// Converte plan todos, chat messages e review scope in strutture pipeline.
public enum PipelineJobFactory {

    // MARK: - Plan Build

    /// Crea un job + task DAG da una lista di plan todos.
    /// - When `sequentialPlanSteps` is `true` (default), ogni todo dipende dal precedente (ordine sicuro).
    /// - When `false`, i task non hanno dipendenze incrociate e possono essere eseguiti in parallelo fino a `maxConcurrentWorkers`.
    ///   Usare solo se il flusso è stato validato: passi paralleli possono modificare gli stessi file e corrompere il workspace.
    public static func fromPlanBuild(
        todos: [PlanTodoItem],
        workspace: String,
        providerId: String,
        mode: PipelineMode = .strict,
        maxConcurrentWorkers: Int = 4,
        jobTimeoutMs: Int = 1_800_000,
        sequentialPlanSteps: Bool = true
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
            let dependsOn: [String] = {
                guard sequentialPlanSteps else { return [] }
                return previousId.map { [$0] } ?? []
            }()
            var node = TaskNode(
                taskId: taskId,
                title: todo.title,
                dependsOn: dependsOn,
                priority: max(0, 100 - index * 5),
                risk: estimateRisk(from: todo.title),
                taskType: inferTaskType(from: todo.title),
                fileScope: todo.linkedFiles ?? [],
                status: .pending,
                timeoutMs: 120_000
            )
            node.deriveTaskLabel()
            tasks.append(node)
            if sequentialPlanSteps {
                previousId = taskId
            }
        }

        return (job, tasks)
    }

    // MARK: - Chat Message (single task)

    /// Crea un job con un singolo task per un messaggio chat in modalita' agent.
    /// Timeout 2 h per task lunghi (code review, analisi pipeline, refactoring, ecc.).
    public static func fromChatMessage(
        prompt: String,
        displayRequest: String? = nil,
        workspace: String,
        providerId: String,
        mode: PipelineMode = .fast,
        jobTimeoutMs: Int = 7_200_000
    ) -> (job: PipelineJob, tasks: [TaskNode]) {
        let jobId = "chat_\(UUID().uuidString.prefix(8))"
        let requestPreview = normalizedChatRequestPreview(
            displayRequest ?? prompt
        )

        let job = PipelineJob(
            jobId: jobId,
            workspace: workspace,
            request: requestPreview,
            mode: mode,
            selectedProviderProfile: providerId,
            jobTimeoutMs: jobTimeoutMs,
            maxConcurrentWorkers: 1
        )

        let truncatedTitle = String(requestPreview.prefix(80))
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

    /// Crea un job + task DAG per una fix stage di code review già analizzata.
    /// Ogni task corrisponde a un finding cluster o review task strutturato.
    static func fromCodeReviewTasks(
        scope: ReviewScope,
        reviewTasks: [CodeReviewMultiSwarmProvider.ReviewTask],
        workspace: String,
        providerId: String,
        sessionId: String,
        round: Int,
        maxWorkers: Int = 4
    ) -> (job: PipelineJob, tasks: [TaskNode]) {
        let jobId = "review_fix_\(UUID().uuidString.prefix(8))"
        let job = PipelineJob(
            jobId: jobId,
            workspace: workspace,
            request: "Code Review Fix Stage (\(reviewTasks.count) tasks, scope: \(scope.rawValue), session: \(sessionId), round: \(round))",
            mode: .strict,
            selectedProviderProfile: providerId,
            jobTimeoutMs: 1_200_000,
            maxConcurrentWorkers: maxWorkers
        )

        let tasks = reviewTasks.enumerated().map { index, reviewTask in
            var node = TaskNode(
                taskId: reviewTask.id,
                title: reviewTask.description,
                priority: max(0, 90 - index),
                risk: reviewTask.severity == "critical" ? .high : .medium,
                taskType: .bugfix,
                executionStyle: .multiAgentFlow,
                fileScope: reviewTask.files,
                metadata: [
                    "review_session_id": sessionId,
                    "review_round": "\(round)",
                    "review_severity": reviewTask.severity,
                    "review_description": reviewTask.description,
                    "review_origin": reviewTask.origin.rawValue,
                    "review_category": reviewTask.category ?? "",
                    "review_confidence": reviewTask.confidence.map { "\($0)" } ?? "",
                    "review_evidence": reviewTask.evidence ?? "",
                    "review_source_tool": reviewTask.sourceTool ?? "",
                    "review_blocking": reviewTask.blocking == true ? "true" : "false",
                ],
                status: .pending,
                timeoutMs: 180_000
            )
            node.deriveTaskLabel()
            return node
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

    private static func normalizedChatRequestPreview(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "Chat task" }
        return String(collapsed.prefix(200))
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
