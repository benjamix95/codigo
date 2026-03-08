import Foundation

extension GitService {
    func stash(gitRoot: String, message: String?) throws {
        var args = ["stash", "push"]
        if let message, !message.isEmpty {
            args += ["-m", message]
        }
        _ = try runGit(args, gitRoot: gitRoot)
    }

    func stashPop(gitRoot: String) throws {
        _ = try runGit(["stash", "pop"], gitRoot: gitRoot)
    }

    func stashDrop(gitRoot: String, index: Int) throws {
        _ = try runGit(["stash", "drop", "stash@{\(index)}"], gitRoot: gitRoot)
    }

    func stashList(gitRoot: String) throws -> [GitStashEntry] {
        let out = try runGit(["stash", "list", "--format=%gd|%s"], gitRoot: gitRoot)
        return out.split(separator: "\n").compactMap { line -> GitStashEntry? in
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { return nil }
            // stash@{0} → extract index
            let refPart = parts[0]
            guard let open = refPart.firstIndex(of: "{"),
                  let close = refPart.firstIndex(of: "}"),
                  let idx = Int(refPart[refPart.index(after: open)..<close]) else { return nil }
            return GitStashEntry(index: idx, message: parts[1])
        }
    }

    func aheadBehindCount(gitRoot: String) throws -> (ahead: Int, behind: Int) {
        let branch = try currentBranch(gitRoot: gitRoot)
        guard !branch.hasPrefix("detached") else { return (0, 0) }
        // Check if tracking branch exists
        guard let _ = try? runGit(["rev-parse", "--abbrev-ref", "\(branch)@{upstream}"], gitRoot: gitRoot)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !branch.isEmpty else {
            return (0, 0)
        }
        let out = try runGit(["rev-list", "--left-right", "--count", "\(branch)...@{upstream}"], gitRoot: gitRoot)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = out.split(separator: "\t").map(String.init)
        guard parts.count == 2 else { return (0, 0) }
        return (ahead: Int(parts[0]) ?? 0, behind: Int(parts[1]) ?? 0)
    }
}
