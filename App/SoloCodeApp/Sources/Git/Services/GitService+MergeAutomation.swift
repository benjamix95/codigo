import Foundation

private struct GitAllowFailureResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

extension GitService {
    func startNoCommitMerge(
        sourceBranch: String,
        intoTarget targetBranch: String,
        gitRoot: String
    ) throws -> GitMergeStartResult {
        let source = sourceBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = targetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !target.isEmpty else {
            throw GitServiceError.commandFailed("Branch sorgente/target non validi.")
        }

        try ensureBranchExists(name: source, gitRoot: gitRoot)
        try ensureBranchExists(name: target, gitRoot: gitRoot)
        try checkoutBranch(name: target, gitRoot: gitRoot)

        let result = try runGitAllowFailure(
            ["merge", "--no-ff", "--no-commit", source],
            gitRoot: gitRoot
        )
        let conflicts = try listConflictedFiles(gitRoot: gitRoot)
        let output = [
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            result.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        if result.status != 0 && conflicts.isEmpty {
            throw GitServiceError.commandFailed(
                output.isEmpty ? "Merge non riuscito." : output
            )
        }
        return GitMergeStartResult(
            hadConflicts: !conflicts.isEmpty,
            output: output
        )
    }

    func abortMerge(gitRoot: String) throws {
        let result = try runGitAllowFailure(["merge", "--abort"], gitRoot: gitRoot)
        guard result.status != 0 else { return }
        let errorText = "\(result.stdout)\n\(result.stderr)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if errorText.contains("there is no merge to abort")
            || errorText.contains("merge_head missing")
        {
            return
        }
        throw GitServiceError.commandFailed(
            errorText.isEmpty ? "Impossibile annullare il merge." : errorText
        )
    }

    func finalizeMergeCommit(gitRoot: String, message: String) throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitServiceError.commandFailed("Messaggio commit merge non valido.")
        }
        _ = try runGit(["commit", "-m", trimmed], gitRoot: gitRoot)
    }

    func autoCommitAllChanges(gitRoot: String, message: String) throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitServiceError.commandFailed("Messaggio auto-commit non valido.")
        }
        _ = try runGit(["add", "-A"], gitRoot: gitRoot)
        guard try worktreeStatusIsDirty(gitRoot: gitRoot) else {
            throw GitServiceError.noChangesToCommit
        }
        _ = try runGit(["commit", "-m", trimmed], gitRoot: gitRoot)
    }

    func deleteMergedBranch(name: String, gitRoot: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitServiceError.commandFailed("Nome branch da eliminare non valido.")
        }
        _ = try runGit(["branch", "-d", trimmed], gitRoot: gitRoot)
    }

    private func runGitAllowFailure(
        _ args: [String],
        gitRoot: String
    ) throws -> GitAllowFailureResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: gitRoot)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        let stdout = String(
            data: outPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: errPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return GitAllowFailureResult(
            status: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}
