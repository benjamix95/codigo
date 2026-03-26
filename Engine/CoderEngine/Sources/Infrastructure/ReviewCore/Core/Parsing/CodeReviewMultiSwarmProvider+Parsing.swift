import Foundation

extension CodeReviewMultiSwarmProvider {
    // MARK: - Phase 1: Streaming Analysis

    /// Streams ALL events from analysis to the continuation (identical to agent mode).
    /// Returns the collected full analysis text.
    static func runAnalysisPhase(
        cleanPrompt: String,
        scopeDescription: String,
        _ filesToReview: [String],
        _ maxWorkers: Int,
        context: WorkspaceContext,
        analysisProvider: any LLMProvider,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        isCancelled: @Sendable @escaping () -> Bool,
        waitWhilePaused: @Sendable @escaping () async -> Void
    ) async throws -> String {
        let fileList = filesToReview.joined(separator: "\n")

        let analysisPrompt = """
        You are a senior code reviewer performing a thorough analysis.

        ## Scope
        \(scopeDescription) — \(filesToReview.count) files:
        \(fileList)

        ## User Instructions
        \(cleanPrompt.isEmpty ? "Review the code thoroughly." : cleanPrompt)

        ## Review Criteria
        1. **Bugs** — logic errors, null/nil dereferences, race conditions, off-by-one
        2. **Security** — injection, hardcoded secrets, insecure patterns
        3. **Performance** — unnecessary allocations, N+1 queries, blocking calls
        4. **Style** — naming, dead code, overly complex logic
        5. **Architecture** — SOLID violations, tight coupling, missing error handling
        6. **Skills & Native Audits** — prefer audit_* tools and relevant skills (security-scan, debugging, testing) when they materially improve confidence

        ## Output Format
        First, provide your detailed analysis with findings.

        Then, at the very end of your response, output a JSON block wrapped in ```json fences.
        This JSON is an array of candidate findings for parallel workers. Each task groups related files:

        ```json
        [
          {
            "id": "review-0",
            "description": "Brief description of what is wrong",
            "files": ["path/to/file1.swift", "path/to/file2.swift"],
            "severity": "critical",
            "line": 42,
            "end_line": 44,
            "category": "correctness",
            "evidence": "Exact code excerpt or concrete proof from the file",
            "expected_invariant": "What invariant is violated",
            "repro_or_reasoning": "How the issue manifests or why it is real"
          }
        ]
        ```

        Rules for tasks:
        - Group related fixes into the same task (same area/module)
        - Each file should appear in at most ONE task
        - severity: "critical", "warning", or "suggestion"
        - `line`, `evidence`, `expected_invariant`, and `repro_or_reasoning` are strongly recommended and should be included whenever possible
        - If no fixes are needed, output an empty array: ```json\n[]\n```
        - Maximum \(maxWorkers) tasks — group smaller fixes together
        """

        var accumulator = CodeReviewStreamTextAccumulator()
        var streamErrorMessage: String?
        do {
            let stream = try await analysisProvider.send(
                prompt: analysisPrompt,
                context: context,
                imageURLs: nil
            )
            for try await event in stream {
                await waitWhilePaused()
                if isCancelled() { break }
                if case .error(let message) = event {
                    streamErrorMessage = message
                }
                continuation.yield(event)
                accumulator.consume(event)
            }
        } catch {
            continuation.yield(.textDelta("\n**Analysis error:** \(error.localizedDescription)\n"))
            throw ReviewPipelineError.analysisTransportFailed(error.localizedDescription)
        }
        if let streamErrorMessage {
            continuation.yield(.textDelta("\n**Analysis error:** \(streamErrorMessage)\n"))
            throw ReviewPipelineError.analysisTransportFailed(streamErrorMessage)
        }

        let fullText = accumulator.text
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ReviewPipelineError.analysisReturnedNoData
        }

        return trimmed
    }

    // MARK: - Phase 2: Parse Review Tasks

    /// Extracts structured tasks from analysis output.
    static func parseReviewTasks(
        from analysisText: String,
        filesToReview: [String],
        maxWorkers: Int
    ) -> ReviewTaskExtractionResult {
        guard let response = ReviewProviderRustBridge.plan(
            operation: "parse_review_tasks",
            text: analysisText,
            allowedFiles: filesToReview,
            maxWorkers: maxWorkers
        ) else {
            return .invalidJSON(reason: "Rust review provider parser unavailable.")
        }
        switch response.extractionKind {
        case "tasks":
            return .tasks(response.tasks ?? [])
        case "no_fixes":
            return .noFixes
        case "no_payload":
            return .noPayload(reason: response.reason ?? "No JSON review task block found in analysis output.")
        case "invalid_json":
            return .invalidJSON(reason: response.reason ?? "Unable to parse task JSON block as an array.")
        default:
            return .invalidJSON(reason: response.reason ?? "Rust review provider parser returned an unsupported result.")
        }
    }

    /// Try to extract JSON review tasks from analysis text.
    /// Supports both fenced code blocks (```json ... ```) and bare JSON arrays.
    static func extractReviewTasksJSON(
        from text: String,
        allowedFiles: [String]? = nil
    ) -> ExtractedReviewTasks? {
        guard let response = ReviewProviderRustBridge.plan(
            operation: "extract_review_tasks_json",
            text: text,
            allowedFiles: allowedFiles
        ) else {
            return .invalidJSON(reason: "Rust review provider parser unavailable.")
        }
        switch response.extractionKind {
        case "json_tasks":
            return .jsonTasks(response.tasks ?? [])
        case "invalid_json":
            return .invalidJSON(reason: response.reason ?? "Unable to parse task JSON block as an array.")
        default:
            return nil
        }
    }

    static func parseTasksJSON(
        _ jsonStr: String,
        allowedFiles: Set<String>?
    ) -> ParsedTasksResult {
        guard let response = ReviewProviderRustBridge.plan(
            operation: "parse_tasks_json",
            text: jsonStr,
            allowedFiles: allowedFiles.map(Array.init)
        ) else {
            return .invalidJSON(reason: "Rust review provider parser unavailable.")
        }
        switch response.extractionKind {
        case "tasks":
            return .tasks(response.tasks ?? [])
        default:
            return .invalidJSON(reason: response.reason ?? "Unable to parse task JSON block as an array.")
        }
    }
}
