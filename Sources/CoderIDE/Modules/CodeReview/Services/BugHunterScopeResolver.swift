import CoderEngine
import Foundation

struct BugHunterScopeResolver {
    private let gitService = GitService()

    func uncommittedFiles(gitRoot: String, excludedPaths: [String]) -> [String] {
        WorkspaceScanner.listUncommittedSourceFiles(
            workspacePath: URL(fileURLWithPath: gitRoot),
            excludedPaths: excludedPaths
        )
    }

    func commitFiles(gitRoot: String, commitSHA: String) throws -> [String] {
        let output = try gitService.runGit(
            ["diff-tree", "--no-commit-id", "--name-only", "-r", commitSHA],
            gitRoot: gitRoot
        )
        return output
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
            .filter { WorkspaceScanner.sourceExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
    }

    func correlatedCommitWindow(
        gitRoot: String,
        primaryCommit: String,
        maxCount: Int
    ) throws -> BugHunterCommitWindow {
        let files = try commitFiles(gitRoot: gitRoot, commitSHA: primaryCommit)
        guard !files.isEmpty else {
            return BugHunterCommitWindow(primaryCommit: primaryCommit, relatedCommits: [], files: [])
        }

        var relatedCommits: [String] = []
        for file in files {
            let output = try gitService.runGit(
                ["log", "--format=%H", "--max-count", String(maxCount + 1), "--", file],
                gitRoot: gitRoot
            )
            for sha in output.split(separator: "\n").map(String.init) where !sha.isEmpty && sha != primaryCommit {
                if !relatedCommits.contains(sha) {
                    relatedCommits.append(sha)
                }
                if relatedCommits.count >= maxCount {
                    break
                }
            }
            if relatedCommits.count >= maxCount {
                break
            }
        }

        return BugHunterCommitWindow(
            primaryCommit: primaryCommit,
            relatedCommits: relatedCommits,
            files: files
        )
    }

    func againstRefExpression(for window: BugHunterCommitWindow) -> String {
        if window.relatedCommits.isEmpty {
            return "\(window.primaryCommit)^..\(window.primaryCommit)"
        }
        let oldest = window.relatedCommits.last ?? window.primaryCommit
        return "\(oldest)^..\(window.primaryCommit)"
    }
}
