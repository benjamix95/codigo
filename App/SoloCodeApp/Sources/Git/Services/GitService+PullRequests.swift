import Foundation

extension GitService {
    func mergePullRequest(gitRoot: String, prURL: String, auto: Bool) throws {
        guard isGhInstalled() else { throw GitServiceError.ghNotInstalled }
        guard isGhAuthenticated(gitRoot: gitRoot) else { throw GitServiceError.ghNotAuthenticated }
        var args = ["pr", "merge", prURL, "--merge", "--delete-branch"]
        if auto {
            args.append("--auto")
        }
        _ = try runCommand(executable: "/usr/bin/env", args: ["gh"] + args, cwd: gitRoot)
    }
}
