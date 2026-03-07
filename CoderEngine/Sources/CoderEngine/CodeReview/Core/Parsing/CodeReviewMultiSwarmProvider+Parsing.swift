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

        ## Output Format
        First, provide your detailed analysis with findings.

        Then, at the very end of your response, output a JSON block wrapped in ```json fences.
        This JSON is an array of fix tasks for parallel workers. Each task groups related files:

        ```json
        [
          {
            "id": "review-0",
            "description": "Brief description of what to fix",
            "files": ["path/to/file1.swift", "path/to/file2.swift"],
            "severity": "critical"
          }
        ]
        ```

        Rules for tasks:
        - Group related fixes into the same task (same area/module)
        - Each file should appear in at most ONE task
        - severity: "critical", "warning", or "suggestion"
        - If no fixes are needed, output an empty array: ```json\n[]\n```
        - Maximum \(maxWorkers) tasks — group smaller fixes together
        """

        var accumulator = CodeReviewStreamTextAccumulator()
        do {
            let stream = try await analysisProvider.send(
                prompt: analysisPrompt,
                context: context,
                imageURLs: nil
            )
            for try await event in stream {
                await waitWhilePaused()
                if isCancelled() { break }
                continuation.yield(event)
                accumulator.consume(event)
            }
        } catch {
            continuation.yield(.textDelta("\n**Analysis error:** \(error.localizedDescription)\n"))
            throw ReviewPipelineError.analysisTransportFailed(error.localizedDescription)
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
        guard let extraction = extractReviewTasksJSON(from: analysisText, allowedFiles: filesToReview) else {
            return .noPayload(reason: "No JSON review task block found in analysis output.")
        }

        switch extraction {
        case .jsonTasks(let tasks) where tasks.isEmpty:
            return .noFixes
        case .jsonTasks(let tasks):
            return .tasks(Array(tasks.prefix(maxWorkers)))
        case .invalidJSON(let reason):
            return .invalidJSON(reason: reason)
        }
    }

    /// Try to extract JSON review tasks from analysis text.
    /// Supports both fenced code blocks (```json ... ```) and bare JSON arrays.
    static func extractReviewTasksJSON(
        from text: String,
        allowedFiles: [String]? = nil
    ) -> ExtractedReviewTasks? {
        let allowedSet = allowedFiles.map(Set.init)

        // Non-greedy JSON capture so multiple fenced blocks are handled correctly.
        let codeBlockPattern = #"```json\s*(?:\r?\n)(\[[\s\S]*?\])\s*(?:\r?\n)```"#
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            var lastInvalidReason: String?
            for match in matches.reversed() {
                guard let jsonRange = Range(match.range(at: 1), in: text) else { continue }
                let jsonStr = String(text[jsonRange])
                switch parseTasksJSON(jsonStr, allowedFiles: allowedSet) {
                case .tasks(let tasks):
                    return .jsonTasks(tasks)
                case .invalidJSON(let reason):
                    lastInvalidReason = lastInvalidReason ?? reason
                }
            }
            if let reason = lastInvalidReason {
                return .invalidJSON(reason: reason)
            }
        }

        // Use lazy matching ([\s\S]*?) so the regex stops at the first valid }\s*]
        // rather than greedily spanning across multiple JSON blocks in the text.
        let bareArrayPattern = #"\[\s*\{[\s\S]*?\}\s*\]"#
        if let regex = try? NSRegularExpression(pattern: bareArrayPattern, options: []) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: text) else { continue }
                let jsonStr = String(text[range])
                switch parseTasksJSON(jsonStr, allowedFiles: allowedSet) {
                case .tasks(let tasks):
                    return .jsonTasks(tasks)
                case .invalidJSON:
                    continue
                }
            }
        }

        return .none
    }

    static func parseTasksJSON(
        _ jsonStr: String,
        allowedFiles: Set<String>?
    ) -> ParsedTasksResult {
        guard let data = jsonStr.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return .invalidJSON(reason: "Unable to parse task JSON block as an array.")
        }

        var tasks: [ReviewTask] = []
        var invalidEntries = 0
        var claimedFiles = Set<String>()
        var usedTaskIDs = Set<String>()
        for (index, dict) in arr.enumerated() {
            let preferredID = ((dict["id"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let id = normalizedUniqueReviewTaskID(preferred: preferredID, fallbackIndex: index, usedIDs: &usedTaskIDs)
            let description = ((dict["description"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rawFiles = (dict["files"] as? [String]) ?? []
            let filteredFiles = uniquedNonEmptyFiles(rawFiles)
            guard !filteredFiles.isEmpty else { continue }

            let scopedFiles: [String]
            if let allowedFiles {
                // Normalize paths: strip leading "./" for consistent matching
                let normalizedAllowed = Set(allowedFiles.map { $0.hasPrefix("./") ? String($0.dropFirst(2)) : $0 })
                scopedFiles = filteredFiles.map { $0.hasPrefix("./") ? String($0.dropFirst(2)) : $0 }
                    .filter { normalizedAllowed.contains($0) && !claimedFiles.contains($0) }
            } else {
                scopedFiles = filteredFiles.filter { !claimedFiles.contains($0) }
            }

            guard !scopedFiles.isEmpty else {
                invalidEntries += 1
                continue
            }

            let normalizedDescription = description.isEmpty ? "Fix issues in assigned files" : description
            let severityRaw = (dict["severity"] as? String)?.lowercased() ?? "warning"
            let allowedSeverities: Set<String> = ["critical", "warning", "suggestion"]
            let severity = allowedSeverities.contains(severityRaw) ? severityRaw : "warning"
            tasks.append(
                ReviewTask(
                    id: id,
                    description: normalizedDescription,
                    files: scopedFiles,
                    severity: severity
                )
            )
            claimedFiles.formUnion(scopedFiles)
        }

        if tasks.isEmpty && !arr.isEmpty {
            return .invalidJSON(
                reason: invalidEntries > 0
                    ? "All task entries were invalid or outside review scope."
                    : "Unable to parse task array entries."
            )
        }
        return .tasks(tasks)
    }

    static func uniquedNonEmptyFiles(_ rawFiles: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in rawFiles {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                out.append(trimmed)
            }
        }
        return out
    }

    static func normalizedUniqueReviewTaskID(
        preferred: String,
        fallbackIndex: Int,
        usedIDs: inout Set<String>
    ) -> String {
        func claim(_ candidate: String) -> String? {
            guard !candidate.isEmpty else { return nil }
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            guard usedIDs.insert(normalized).inserted else { return nil }
            return normalized
        }

        if let preferredClaimed = claim(preferred) {
            return preferredClaimed
        }
        if let fallbackClaimed = claim("review-\(fallbackIndex)") {
            return fallbackClaimed
        }

        var suffix = 1
        while suffix <= 1000 {
            let candidate = "review-\(fallbackIndex)-\(suffix)"
            if let claimed = claim(candidate) { return claimed }
            suffix += 1
        }
        // Safety fallback: use UUID to guarantee uniqueness
        let uuid = UUID().uuidString.prefix(8)
        let fallback = "review-\(fallbackIndex)-\(uuid)"
        usedIDs.insert(fallback)
        return fallback
    }
}
