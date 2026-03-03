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
    static func isValidAgainstRefFormat(_ ref: String) -> Bool {
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

    /// Get files changed since a commit ref using git diff.
    /// Returns `(files, error)` — error is non-nil if git failed.
    static func gitDiffFiles(ref: String, workspacePath: URL) -> (files: [String], error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "--name-only", "--diff-filter=ACMR", ref, "--"]
        process.currentDirectoryURL = workspacePath
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

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
            errPipe.fileHandleForReading.readabilityHandler = nil
            return ([], "Failed to run git diff: \(error.localizedDescription)")
        }

        let gitTimeoutSeconds: TimeInterval = 30
        let timeoutItem = DispatchWorkItem {
            guard process.isRunning else { return }
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + gitTimeoutSeconds, execute: timeoutItem)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutItem.cancel()
        errPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            if process.terminationReason == .uncaughtSignal {
                return ([], "git diff timed out after \(Int(gitTimeoutSeconds))s for ref '\(ref)'")
            }
            errLock.lock()
            let capturedErrData = errData
            errLock.unlock()
            let errMsg = String(data: capturedErrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
            return ([], "git diff failed for ref '\(ref)': \(errMsg)")
        }
        guard let output = String(data: data, encoding: .utf8) else {
            return ([], "Failed to decode git diff output as UTF-8.")
        }

        let files = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { path in
                let ext = (path as NSString).pathExtension.lowercased()
                return WorkspaceScanner.sourceExtensions.contains(ext)
            }
        return (files, nil)
    }
}
