import Foundation
import CoderEngine

extension GitService {
    func commit(gitRoot: String, message: String, includeUnstaged: Bool) async throws -> GitCommitResult {
        if includeUnstaged {
            throw GitServiceError.unstagedCommitNotAllowed
        }
        let staged = try changedFiles(gitRoot: gitRoot).filter(\.isStaged)
        if staged.isEmpty {
            throw GitServiceError.noChangesToCommit
        }
        let validation: ValidationRunResult
        do {
            validation = try await validateForCommit(gitRoot: gitRoot, stagedFiles: staged.map(\.path))
        } catch {
            throw GitServiceError.validationFailed(error.localizedDescription)
        }
        guard validation.status == .passed else {
            throw GitServiceError.validationFailed(validation.summaryLine)
        }
        _ = try runGit(["commit", "-m", message], gitRoot: gitRoot)
        let sha = try runGit(["rev-parse", "HEAD"], gitRoot: gitRoot).trimmingCharacters(in: .whitespacesAndNewlines)
        let short = try runGit(["rev-parse", "--short", "HEAD"], gitRoot: gitRoot)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = try runGit(["log", "-1", "--pretty=%s"], gitRoot: gitRoot)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return GitCommitResult(sha: sha, shortSha: short, subject: subject)
    }

    func push(gitRoot: String, branch: String) throws {
        let hasRemote = !(try runGit(["remote"], gitRoot: gitRoot)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        guard hasRemote else { throw GitServiceError.missingRemote }
        _ = try runGit(["push", "-u", "origin", branch], gitRoot: gitRoot)
    }

    func createPullRequest(
        gitRoot: String,
        base: String?,
        title: String,
        body: String?
    ) throws -> GitPRResult {
        guard isGhInstalled() else { throw GitServiceError.ghNotInstalled }
        guard isGhAuthenticated(gitRoot: gitRoot) else { throw GitServiceError.ghNotAuthenticated }

        var args = ["pr", "create", "--title", title]
        if let body, !body.isEmpty {
            args += ["--body", body]
        } else {
            args += ["--body", ""]
        }
        if let base, !base.isEmpty {
            args += ["--base", base]
        }
        args += ["--fill-first", "--json", "url", "--jq", ".url"]
        let url = try runCommand(
            executable: "/usr/bin/env",
            args: ["gh"] + args,
            cwd: gitRoot
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            throw GitServiceError.commandFailed("PR created but URL not available.")
        }
        return GitPRResult(url: url)
    }

    func commitHistory(gitRoot: String, limit: Int = 20) throws -> [GitLogEntry] {
        let format = "%H|%h|%an|%ar|%s"
        let out = try runGit(["log", "--format=\(format)", "-\(limit)"], gitRoot: gitRoot)
        return out
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
            .compactMap { line -> GitLogEntry? in
                let parts = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 5 else { return nil }
                return GitLogEntry(
                    sha: parts[0],
                    shortSha: parts[1],
                    subject: parts[4],
                    authorName: parts[2],
                    relativeDate: parts[3]
        )
    }
    }
}
