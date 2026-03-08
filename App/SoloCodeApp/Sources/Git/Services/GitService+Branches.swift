import Foundation

extension GitService {
    func resolveGitRoot(from workingDirectory: String?) throws -> String {
        guard let workingDirectory, !workingDirectory.isEmpty else {
            throw GitServiceError.missingWorkingDirectory
        }
        do {
            return try runCommand(
                executable: "/usr/bin/git",
                args: ["rev-parse", "--show-toplevel"],
                cwd: workingDirectory
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw GitServiceError.notGitRepository
        }
    }

    func currentBranch(gitRoot: String) throws -> String {
        let out = try runGit(["branch", "--show-current"], gitRoot: gitRoot)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty { return out }
        let detached = try runGit(["rev-parse", "--short", "HEAD"], gitRoot: gitRoot)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return detached.isEmpty ? "(detached)" : "detached@\(detached)"
    }

    func listLocalBranches(gitRoot: String) throws -> [GitBranch] {
        let current = try currentBranch(gitRoot: gitRoot)
        let out = try runGit(
            ["for-each-ref", "--format=%(refname:short)|%(upstream:short)", "refs/heads"],
            gitRoot: gitRoot
        )
        let branches = out
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }
            .map { row -> GitBranch in
                let parts = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                let name = parts.first ?? ""
                let upstream = parts.count > 1 ? parts[1] : ""
                return GitBranch(name: name, isCurrent: name == current, isRemoteTracking: !upstream.isEmpty)
            }
            .sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
                return lhs.name < rhs.name
            }
        return branches
    }

    func checkoutBranch(name: String, gitRoot: String) throws {
        let existing = try listLocalBranches(gitRoot: gitRoot).map(\.name)
        guard existing.contains(name) else {
            throw GitServiceError.branchNotFound(name)
        }
        _ = try runGit(["checkout", name], gitRoot: gitRoot)
    }

    func createAndCheckoutBranch(name: String, gitRoot: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitServiceError.commandFailed("Nome branch non valido.")
        }
        _ = try runGit(["checkout", "-b", trimmed], gitRoot: gitRoot)
    }

    func deleteBranch(name: String, gitRoot: String, force: Bool) throws {
        let flag = force ? "-D" : "-d"
        _ = try runGit(["branch", flag, name], gitRoot: gitRoot)
    }

    func renameBranch(oldName: String, newName: String, gitRoot: String) throws {
        _ = try runGit(["branch", "-m", oldName, newName], gitRoot: gitRoot)
    }

    func listRemoteBranches(gitRoot: String) throws -> [GitBranch] {
        let out = try runGit(["branch", "-r", "--format=%(refname:short)"], gitRoot: gitRoot)
        return out.split(separator: "\n")
            .map(String.init)
            .filter { !$0.contains("HEAD") }
            .map { name in
                GitBranch(name: name, isCurrent: false, isRemoteTracking: true)
            }
    }

    func checkoutRemoteBranch(name: String, gitRoot: String) throws {
        let localName = name.contains("/")
            ? String(name.split(separator: "/", maxSplits: 1).last ?? Substring(name))
            : name
        _ = try runGit(["checkout", "-b", localName, name], gitRoot: gitRoot)
    }
}
