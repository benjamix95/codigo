import Foundation

extension GitService {
    func status(gitRoot: String) throws -> GitStatusSummary {
        let porcelain = try runGit(["status", "--porcelain"], gitRoot: gitRoot)
        let lines = porcelain.split(separator: "\n").map(String.init)
        var added = 0
        var removed = 0
        var modified = 0
        var untracked = 0
        for line in lines {
            guard line.count >= 2 else { continue }
            let prefix = String(line.prefix(2))
            if prefix == "??" {
                untracked += 1
                continue
            }
            let chars = Array(prefix)
            if chars.contains("A") { added += 1 }
            if chars.contains("D") { removed += 1 }
            if chars.contains("M") || chars.contains("R") || chars.contains("C") || chars.contains("T") {
                modified += 1
            }
        }
        let hasRemote = !(try runGit(["remote"], gitRoot: gitRoot)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let aheadBehind = try? runGit(["status", "-sb"], gitRoot: gitRoot)
            .split(separator: "\n")
            .first
            .map(String.init)
        return GitStatusSummary(
            changedFiles: lines.count,
            added: added,
            removed: removed,
            modified: modified,
            untracked: untracked,
            aheadBehind: aheadBehind,
            hasRemote: hasRemote
        )
    }

    func diffForCommitMessage(gitRoot: String, includeUnstaged: Bool) throws -> String {
        let args = includeUnstaged ? ["diff", "--cached", "HEAD", "--", ".", ":(exclude).git"]
            : ["diff", "--cached"]
        var diff = try runGit(args, gitRoot: gitRoot)
        if includeUnstaged {
            let unstaged = try runGit(["diff", "--", ".", ":(exclude).git"], gitRoot: gitRoot)
            if !unstaged.isEmpty {
                diff += "\n\n# Unstaged\n" + unstaged
            }
            let untracked = try runGit(["ls-files", "--others", "--exclude-standard"], gitRoot: gitRoot)
            if !untracked.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diff += "\n\n# Untracked files\n" + untracked
            }
        }
        return diff
    }

    func changedFiles(gitRoot: String) throws -> [GitChangedFile] {
        let porcelain = try runGit(["status", "--porcelain"], gitRoot: gitRoot)
        let lines = porcelain.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        var result: [GitChangedFile] = []
        for line in lines {
            guard line.count >= 3 else { continue }
            // Porcelain format: XY path
            // X = index (staged), Y = worktree
            let indexChar = line[line.startIndex]
            let worktreeChar = line[line.index(after: line.startIndex)]
            let rawPath = String(line.dropFirst(3))
            let path = rawPath.components(separatedBy: " -> ").last ?? rawPath

            // Determine staging status
            // If index column has a change letter (not ' ' and not '?'), it's staged
            let isStaged = indexChar != " " && indexChar != "?"
            let statusCode: String
            if indexChar == "?" && worktreeChar == "?" {
                statusCode = "??"
            } else if isStaged {
                statusCode = String(indexChar)
            } else {
                statusCode = String(worktreeChar)
            }

            var added = 0
            var removed = 0
            if statusCode == "??" {
                // Untracked file: count lines as all-added
                let fullPath = (gitRoot as NSString).appendingPathComponent(path)
                if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                    added = content.components(separatedBy: .newlines).count
                    if content.hasSuffix("\n") { added = max(0, added - 1) }
                }
            } else {
                // Use --cached for staged files, plain diff for unstaged
                var diffArgs = ["diff", "--numstat"]
                if isStaged {
                    diffArgs.append("--cached")
                }
                diffArgs.append(contentsOf: ["--", path])
                let stat = try runGit(diffArgs, gitRoot: gitRoot)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stat.isEmpty {
                    // Take only the last non-empty line (in case of multi-line output)
                    let lastLine = stat.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .last(where: { !$0.isEmpty }) ?? stat
                    let comps = lastLine.split(separator: "\t")
                    if comps.count >= 2 {
                        added = Int(comps[0]) ?? 0
                        removed = Int(comps[1]) ?? 0
                    }
                }
            }

            result.append(GitChangedFile(
                path: path,
                added: added,
                removed: removed,
                status: statusCode.isEmpty ? "M" : statusCode,
                isStaged: isStaged
            ))
        }
        return result
    }
}
