import Foundation

extension CodeReviewMultiSwarmProvider {
    // MARK: - Helpers

    /// Resolve files to review from context.
    static func resolveFiles(context: WorkspaceContext, scope: ReviewFileScope = .uncommitted) -> [String] {
        switch scope {
        case .uncommitted:
            return WorkspaceScanner.listUncommittedSourceFiles(
                workspacePath: context.workspacePath,
                excludedPaths: context.excludedPaths
            )
        case .staged:
            return WorkspaceScanner.listStagedSourceFiles(
                workspacePath: context.workspacePath,
                excludedPaths: context.excludedPaths
            )
        case .workspace:
            return WorkspaceScanner.listSourceFiles(
                workspacePath: context.workspacePath,
                excludedPaths: context.excludedPaths
            )
        }
    }

    /// Parse optional [REVIEW_SCOPE:...] marker from prompt.
    static func parseReviewScope(from prompt: String) -> (cleanPrompt: String, scope: ReviewFileScope?) {
        guard let response = ReviewProviderRustBridge.plan(
            operation: "parse_prompt",
            prompt: prompt
        ) else {
            return (prompt, nil)
        }
        return (
            response.cleanPrompt ?? prompt,
            response.explicitScope.flatMap(ReviewFileScope.init(rawValue:))
        )
    }

    static func inferReviewScope(from prompt: String) -> ReviewFileScope? {
        ReviewProviderRustBridge.plan(
            operation: "parse_prompt",
            prompt: prompt
        )?.inferredScope.flatMap(ReviewFileScope.init(rawValue:))
    }

    /// Parse [AGAINST:ref] marker from prompt.
    static func parseAgainstRef(from prompt: String) -> (cleanPrompt: String, ref: String?) {
        guard let response = ReviewProviderRustBridge.plan(
            operation: "parse_prompt",
            prompt: prompt
        ) else {
            return (prompt, nil)
        }
        return (response.cleanPrompt ?? prompt, response.againstRef)
    }

    /// Validation for AGAINST revision expressions.
    /// Supports common syntaxes like `HEAD~1` and `main..feature`.
    public static func isValidAgainstRefFormat(_ ref: String) -> Bool {
        ReviewProviderRustBridge.plan(
            operation: "validate_against_ref",
            againstRef: ref
        )?.isValidAgainstRef ?? false
    }

    public static func normalizedAgainstRefInput(_ ref: String) -> String {
        ReviewProviderRustBridge.plan(
            operation: "normalize_against_ref",
            againstRef: ref
        )?.normalizedAgainstRefInput
            ?? ref.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedAgainstRefRevision(_ ref: String) -> String {
        ReviewProviderRustBridge.plan(
            operation: "normalize_against_ref",
            againstRef: ref
        )?.normalizedAgainstRefRevision
            ?? normalizedAgainstRefInput(ref)
    }

    /// Get files changed since a commit ref using git diff.
    /// Returns `(files, error)` — error is non-nil if git failed.
    static func gitDiffFiles(ref: String, workspacePath: URL, excludedPaths: [String] = []) -> (files: [String], error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "diff", "--name-only", "--diff-filter=ACMR",
            normalizedAgainstRefRevision(ref),
            "--"
        ]
        process.currentDirectoryURL = workspacePath
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        // Read both stdout and stderr asynchronously to avoid pipe deadlock.
        // Synchronous readDataToEndOfFile on one pipe while the other fills can deadlock.
        var outData = Data()
        let outLock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outLock.lock()
            outData.append(chunk)
            outLock.unlock()
        }

        var errData = Data()
        let errLock = NSLock()
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            errLock.lock()
            errData.append(chunk)
            errLock.unlock()
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return ([], "Failed to run git diff: \(error.localizedDescription)")
        }

        let gitTimeoutSeconds: TimeInterval = 30
        let didTimeoutLock = NSLock()
        var didTimeout = false
        let timeoutItem = DispatchWorkItem {
            guard process.isRunning else { return }
            didTimeoutLock.lock()
            didTimeout = true
            didTimeoutLock.unlock()
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + gitTimeoutSeconds, execute: timeoutItem)

        process.waitUntilExit()
        timeoutItem.cancel()

        // Detach handlers first, then drain remaining buffered data synchronously
        // to avoid race between in-flight handler callbacks and final data read.
        pipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        let remainingOut = pipe.fileHandleForReading.readDataToEndOfFile()
        let remainingErr = errPipe.fileHandleForReading.readDataToEndOfFile()

        outLock.lock()
        if !remainingOut.isEmpty { outData.append(remainingOut) }
        let data = outData
        outLock.unlock()
        errLock.lock()
        if !remainingErr.isEmpty { errData.append(remainingErr) }
        errLock.unlock()

        guard process.terminationStatus == 0 else {
            didTimeoutLock.lock()
            let wasTimedOut = didTimeout
            didTimeoutLock.unlock()
            errLock.lock()
            let capturedErrData = errData
            errLock.unlock()
            if wasTimedOut {
                let errMsg = String(data: capturedErrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let detail = errMsg.isEmpty ? "" : " (\(errMsg))"
                return ([], "git diff terminated by signal for ref '\(ref)'\(detail) (timeout was \(Int(gitTimeoutSeconds))s)")
            }
            let errMsg = String(data: capturedErrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
            return ([], "git diff failed for ref '\(ref)': \(errMsg)")
        }
        guard let output = String(data: data, encoding: .utf8) else {
            return ([], "Failed to decode git diff output as UTF-8.")
        }

        // Normalize excluded paths to always end with "/" for directory-aware matching.
        // This prevents "src/test" from matching "src/testing/MyFile.swift".
        let excludedPrefixes = excludedPaths.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        let files = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { path in
                let ext = (path as NSString).pathExtension.lowercased()
                guard WorkspaceScanner.sourceExtensions.contains(ext) else { return false }
                // Exclude paths matching excludedPaths directory prefixes
                return !excludedPrefixes.contains(where: { path.hasPrefix($0) || path == String($0.dropLast()) })
        }
        return (files, nil)
    }
}

enum ReviewProviderRustBridge {
    static func plan(
        operation: String,
        prompt: String? = nil,
        text: String? = nil,
        allowedFiles: [String]? = nil,
        maxWorkers: Int? = nil,
        againstRef: String? = nil
    ) -> ReviewProviderRustPlanResponse? {
        let response: ReviewProviderRustPlanResponse? = ReviewCoreBridge.call(
            functionName: "review_core_provider_plan_step",
            request: ReviewProviderRustPlanRequest(
                schemaVersion: 1,
                operation: operation,
                prompt: prompt,
                text: text,
                allowedFiles: allowedFiles,
                maxWorkers: maxWorkers,
                againstRef: againstRef
            )
        )
        guard response?.error == nil else { return nil }
        return response
    }

    static func reduce(
        operation: String,
        text: String
    ) -> ReviewProviderRustReduceResponse? {
        let response: ReviewProviderRustReduceResponse? = ReviewCoreBridge.call(
            functionName: "review_core_provider_reduce_event",
            request: ReviewProviderRustReduceRequest(
                schemaVersion: 1,
                operation: operation,
                text: text
            )
        )
        guard response?.error == nil else { return nil }
        return response
    }
}

private struct ReviewProviderRustPlanRequest: Encodable {
    let schemaVersion: Int
    let operation: String
    let prompt: String?
    let text: String?
    let allowedFiles: [String]?
    let maxWorkers: Int?
    let againstRef: String?
}

struct ReviewProviderRustPlanResponse: Decodable {
    let error: ReviewProviderRustError?
    let cleanPrompt: String?
    let explicitScope: String?
    let inferredScope: String?
    let againstRef: String?
    let isValidAgainstRef: Bool?
    let normalizedAgainstRefInput: String?
    let normalizedAgainstRefRevision: String?
    let extractionKind: String?
    let tasks: [CodeReviewMultiSwarmProvider.ReviewTask]?
    let reason: String?
}

private struct ReviewProviderRustReduceRequest: Encodable {
    let schemaVersion: Int
    let operation: String
    let text: String
}

struct ReviewProviderRustReduceResponse: Decodable {
    let error: ReviewProviderRustError?
    let findingsState: String?
    let reason: String?
}

struct ReviewProviderRustError: Decodable {
    let code: String
    let message: String
}
