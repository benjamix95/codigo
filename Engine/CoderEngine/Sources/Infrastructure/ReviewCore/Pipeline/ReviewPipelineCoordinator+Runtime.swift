import Foundation

public actor ReviewPipelineCoordinator {
    public static let shared = ReviewPipelineCoordinator()

    public init() {}

    public func run(
        prompt: String,
        context: WorkspaceContext,
        config: MultiSwarmReviewConfig,
        analysisProvider: any LLMProvider,
        executionProvider: any LLMProvider,
        runtimeResolver: CodeReviewRuntimeResolver?,
        execController: ExecutionController?,
        fileLockCoordinator: FileLockCoordinator,
        sessionState: CodeReviewSessionState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        guard ReviewCoreBridge.isEnabled else {
            throw CodeReviewMultiSwarmProvider.ReviewPipelineError.analysisTransportFailed(
                "Rust review pipeline required but unavailable."
            )
        }
        try await ReviewPipelineRustDriver(
            prompt: prompt,
            context: context,
            config: config,
            analysisProvider: analysisProvider,
            executionProvider: executionProvider,
            runtimeResolver: runtimeResolver,
            execController: execController,
            fileLockCoordinator: fileLockCoordinator,
            sessionState: sessionState,
            continuation: continuation
        ).run()
    }
}

public typealias ReviewPatchPreparationRuntime = (
    CodeReviewSessionSnapshot,
    [String],
    String
) async throws -> CodeReviewSessionSnapshot

public struct CodeReviewRuntimeResources {
    public let config: MultiSwarmReviewConfig
    public let analysisProvider: any LLMProvider
    public let executionProvider: any LLMProvider
    public let prepareVerifiedPatches: ReviewPatchPreparationRuntime?

    public init(
        config: MultiSwarmReviewConfig,
        analysisProvider: any LLMProvider,
        executionProvider: any LLMProvider,
        prepareVerifiedPatches: ReviewPatchPreparationRuntime? = nil
    ) {
        self.config = config
        self.analysisProvider = analysisProvider
        self.executionProvider = executionProvider
        self.prepareVerifiedPatches = prepareVerifiedPatches
    }
}

public typealias CodeReviewRuntimeResolver = (SessionConfig) -> CodeReviewRuntimeResources?

extension ReviewPipelineCoordinator {
    func reviewScopeDescription(
        scope: CodeReviewMultiSwarmProvider.ReviewFileScope,
        againstRef: String?
    ) -> String {
        if let againstRef {
            return "Changes against `\(againstRef)`"
        }
        switch scope {
        case .staged:
            return "Staged changes"
        case .workspace:
            return "Workspace source files"
        case .codebase:
            return "Indexed codebase"
        case .uncommitted:
            return "Uncommitted changes"
        }
    }

    func currentRuntimeResources(
        staticConfig: MultiSwarmReviewConfig,
        staticAnalysisProvider: any LLMProvider,
        staticExecutionProvider: any LLMProvider,
        runtimeResolver: CodeReviewRuntimeResolver?,
        sessionState: CodeReviewSessionState
    ) async -> CodeReviewRuntimeResources {
        let sessionConfig = await sessionState.snapshot().config
        if let runtimeResolver,
           let resolved = runtimeResolver(sessionConfig) {
            return resolved
        }
        return CodeReviewRuntimeResources(
            config: staticConfig,
            analysisProvider: staticAnalysisProvider,
            executionProvider: staticExecutionProvider
        )
    }

    func runAuditStage(
        filesToReview: [String],
        workspacePath: URL,
        sessionState: CodeReviewSessionState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async -> [CodeReviewFinding] {
        guard !filesToReview.isEmpty else { return [] }

        let results = await runAuditStageResults(
            filesToReview: filesToReview,
            workspacePath: workspacePath
        )
        return await reduceAuditStageResults(
            results,
            sessionState: sessionState,
            continuation: continuation
        )
    }

    func runAuditStageResults(
        filesToReview: [String],
        workspacePath: URL
    ) async -> [ReviewAuditToolResult] {
        guard !filesToReview.isEmpty else { return [] }
        let toolNames = ReviewAuditToolName.all

        return await withTaskGroup(
            of: ReviewAuditToolResult.self,
            returning: [ReviewAuditToolResult].self
        ) { group in
            for toolName in toolNames {
                group.addTask {
                    CodeReviewAuditService.runTool(
                        named: toolName,
                        scopeFiles: filesToReview,
                        workspacePath: workspacePath
                    )
                }
            }

            var aggregated: [ReviewAuditToolResult] = []
            for await result in group {
                aggregated.append(result)
            }
            return aggregated
        }
    }

    func reduceAuditStageResults(
        _ results: [ReviewAuditToolResult],
        sessionState: CodeReviewSessionState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async -> [CodeReviewFinding] {
        guard !results.isEmpty else { return [] }
        let toolNames = ReviewAuditToolName.all
        for toolName in toolNames {
            await sessionState.markAuditStarted(toolName: toolName)
        }
        let correlated = CodeReviewAuditService.correlateResults(
            results,
            summaryPrefix: "review_audit_mesh"
        )

        var findings: [CodeReviewFinding] = []
        for result in results.sorted(by: { $0.toolName < $1.toolName }) {
            let sessionId = await sessionState.snapshot().sessionId
            await sessionState.recordAuditResult(result)
            findings.append(contentsOf: result.findings)
            continuation.yield(.raw(type: "review-audit-tool", payload: [
                "tool": result.toolName,
                "session_id": sessionId,
                "findings_count": String(result.findings.count),
                "blocking_findings": String(result.blockingFindingsCount),
                "coverage": result.coverageAvailable ? "true" : "false",
                "duration_ms": String(result.durationMs),
                "detail": result.summary,
            ]))
        }

        let sessionId = await sessionState.snapshot().sessionId
        continuation.yield(.raw(type: "review-audit-tool", payload: [
            "tool": ReviewAuditToolName.correlateFindings,
            "session_id": sessionId,
            "findings_count": String(correlated.findings.count),
            "coverage": correlated.coverageAvailable ? "true" : "false",
            "detail": correlated.summary,
        ]))

        findings.append(contentsOf: correlated.findings)
        return CodeReviewAuditService.deduplicate(findings)
    }

    func resolveFiles(
        context: WorkspaceContext,
        resolvedScope: CodeReviewMultiSwarmProvider.ReviewFileScope,
        againstRef: String?,
        workspacePath: URL,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) -> [String] {
        if let againstRef {
            guard CodeReviewMultiSwarmProvider.isValidAgainstRefFormat(againstRef) else {
                continuation.yield(.textReplace("Invalid AGAINST ref `\(againstRef)`.\n"))
                return []
            }
            let (files, error) = CodeReviewMultiSwarmProvider.gitDiffFiles(
                ref: againstRef,
                workspacePath: workspacePath,
                excludedPaths: context.excludedPaths
            )
            if files.isEmpty {
                let currentHead = currentHEADRevision(workspacePath: workspacePath)
                let message = Self.noFilesAgainstRefMessage(
                    againstRef: againstRef,
                    normalizedInput: CodeReviewMultiSwarmProvider.normalizedAgainstRefInput(againstRef),
                    currentHeadRevision: currentHead,
                    error: error
                )
                continuation.yield(.textReplace(message + "\n"))
            }
            return files
        }

        let files = CodeReviewMultiSwarmProvider.resolveFiles(
            context: context,
            scope: resolvedScope
        )
        if files.isEmpty {
            let message = switch resolvedScope {
            case .staged:
                "No staged source files found.\n"
            case .workspace, .codebase:
                "No workspace source files found.\n"
            case .uncommitted:
                "No uncommitted source files found.\n"
            }
            continuation.yield(.textReplace(message))
        }
        return files
    }

    static func noFilesAgainstRefMessage(
        againstRef: String,
        normalizedInput: String,
        currentHeadRevision: String?,
        error: String?
    ) -> String {
        if let error, !error.isEmpty {
            return "\(error) against `\(againstRef)`."
        }

        let trimmedRef = againstRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSingleCommitRange = normalizedInput != trimmedRef
        let matchesHeadCommit = currentHeadRevision.map {
            $0 == trimmedRef || $0.hasPrefix(trimmedRef) || trimmedRef.hasPrefix($0)
        } ?? false

        if isSingleCommitRange && matchesHeadCommit {
            return "No changed source files for `\(againstRef)`. The ref resolves to the current `HEAD` commit, so the review was reinterpreted as the single-commit range `\(normalizedInput)`."
        }
        if isSingleCommitRange {
            return "No changed source files for `\(againstRef)`. The review was reinterpreted as the single-commit range `\(normalizedInput)`."
        }
        return "No changed source files against `\(againstRef)`."
    }

    private func currentHEADRevision(workspacePath: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "HEAD"]
        process.currentDirectoryURL = workspacePath

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
