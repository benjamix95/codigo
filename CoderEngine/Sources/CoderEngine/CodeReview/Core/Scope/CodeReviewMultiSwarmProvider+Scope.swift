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
        }
    }

    /// Parse optional [REVIEW_SCOPE:...] marker from prompt.
    static func parseReviewScope(from prompt: String) -> (cleanPrompt: String, scope: ReviewFileScope?) {
        let searchableLimit = prompt.range(of: "## Conversation context (recent)")?.lowerBound ?? prompt.endIndex
        let searchable = String(prompt[..<searchableLimit])
        let pattern = #"\[REVIEW_SCOPE:(staged|uncommitted)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: searchable, range: NSRange(searchable.startIndex..., in: searchable)),
              let scopeRange = Range(match.range(at: 1), in: searchable),
              let fullRange = Range(match.range(at: 0), in: searchable)
        else { return (prompt, nil) }

        let marker = String(searchable[scopeRange]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedScope = ReviewFileScope(rawValue: marker)
        var cleanPrefix = searchable
        cleanPrefix.removeSubrange(fullRange)
        let suffix = String(prompt[searchableLimit...])
        let cleanPrompt = (cleanPrefix + suffix).trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleanPrompt.isEmpty ? "Review all changes" : cleanPrompt, resolvedScope)
    }

    static func inferReviewScope(from prompt: String) -> ReviewFileScope? {
        let lower = prompt.lowercased()
        if lower.contains("[review_scope:staged]") || lower.contains("/review-staged")
            || lower.contains("review only staged changes")
            || lower.contains("staged diff only")
        {
            return .staged
        }
        if lower.contains("[review_scope:uncommitted]") || lower.contains("/review-uncommitted") {
            return .uncommitted
        }
        return nil
    }

    /// Parse [AGAINST:ref] marker from prompt.
    static func parseAgainstRef(from prompt: String) -> (cleanPrompt: String, ref: String?) {
        let searchableLimit = prompt.range(of: "## Conversation context (recent)")?.lowerBound ?? prompt.endIndex
        let searchable = String(prompt[..<searchableLimit])
        let pattern = #"\[AGAINST:([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: searchable, range: NSRange(searchable.startIndex..., in: searchable)),
              let refRange = Range(match.range(at: 1), in: searchable),
              let markerRange = Range(match.range(at: 0), in: searchable)
        else { return (prompt, nil) }

        let ref = String(searchable[refRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        var cleanPrefix = searchable
        cleanPrefix.removeSubrange(markerRange)
        let suffix = String(prompt[searchableLimit...])
        let clean = (cleanPrefix + suffix).trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean.isEmpty ? "Review all changes" : clean, ref)
    }

    /// Validation for AGAINST revision expressions.
    /// Supports common syntaxes like `HEAD~1` and `main..feature`.
    public static func isValidAgainstRefFormat(_ ref: String) -> Bool {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.hasPrefix("-") else { return false }
        guard !trimmed.hasSuffix(".lock") else { return false }
        guard !trimmed.hasSuffix(".") else { return false }

        let invalidChars = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard trimmed.unicodeScalars.allSatisfy({ !invalidChars.contains($0) }) else { return false }

        let forbiddenSubstrings = [":", "?", "*", "[", "\\", "@{"]
        for seq in forbiddenSubstrings where trimmed.contains(seq) {
            return false
        }
        return true
    }

    static func normalizedAgainstRefRevision(_ ref: String) -> String {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("..") else { return trimmed }
        return "\(trimmed)...HEAD"
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
