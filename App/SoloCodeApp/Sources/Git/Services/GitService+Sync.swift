import Foundation

extension GitService {
    @discardableResult
    func pull(gitRoot: String) throws -> String {
        try runGit(["pull"], gitRoot: gitRoot)
    }

    @discardableResult
    func fetch(gitRoot: String) throws -> String {
        try runGit(["fetch", "--all", "--prune"], gitRoot: gitRoot)
    }
}
