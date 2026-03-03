import Foundation

extension GitService {
    func stageFile(path: String, gitRoot: String) throws {
        _ = try runGit(["add", "--", path], gitRoot: gitRoot)
    }

    func unstageFile(path: String, gitRoot: String) throws {
        _ = try runGit(["restore", "--staged", "--", path], gitRoot: gitRoot)
    }

    func stageAll(gitRoot: String) throws {
        _ = try runGit(["add", "-A"], gitRoot: gitRoot)
    }

    func unstageAll(gitRoot: String) throws {
        _ = try runGit(["reset", "HEAD"], gitRoot: gitRoot)
    }
}
