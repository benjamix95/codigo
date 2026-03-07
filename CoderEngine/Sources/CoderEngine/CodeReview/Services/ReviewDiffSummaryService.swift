import Foundation

public enum ReviewDiffSummaryService {
    public struct FileSummary: Sendable {
        public let filePath: String
        public let additions: Int
        public let deletions: Int
    }

    public static func renderSummary(
        snapshot: CodeReviewSessionSnapshot,
        workspacePath: URL,
        fileFilter: String? = nil
    ) -> String {
        let targetFiles = filteredScopeFiles(snapshot: snapshot, fileFilter: fileFilter)
        guard !targetFiles.isEmpty else {
            return "No files available for diff summary."
        }

        let summaries = diffSummaries(
            snapshot: snapshot,
            workspacePath: workspacePath,
            targetFiles: targetFiles
        )
        guard !summaries.isEmpty else {
            return "No diff data available for the selected review scope."
        }

        let totalAdditions = summaries.reduce(0) { $0 + $1.additions }
        let totalDeletions = summaries.reduce(0) { $0 + $1.deletions }
        let header = "Diff summary for session \(snapshot.sessionId): \(summaries.count) files, +\(totalAdditions) / -\(totalDeletions)"
        let lines = summaries.map {
            "\($0.filePath) | +\($0.additions) / -\($0.deletions)"
        }
        return ([header] + lines).joined(separator: "\n")
    }

    private static func filteredScopeFiles(
        snapshot: CodeReviewSessionSnapshot,
        fileFilter: String?
    ) -> [String] {
        let trimmedFilter = (fileFilter ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let files = snapshot.scope?.files ?? []
        guard !trimmedFilter.isEmpty else { return files }
        return files.filter { $0.contains(trimmedFilter) }
    }

    private static func diffSummaries(
        snapshot: CodeReviewSessionSnapshot,
        workspacePath: URL,
        targetFiles: [String]
    ) -> [FileSummary] {
        let args = diffArguments(snapshot: snapshot, targetFiles: targetFiles)
        guard !args.isEmpty else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = workspacePath

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return []
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return []
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return text
            .split(separator: "\n")
            .compactMap(parseNumstatLine(_:))
    }

    private static func diffArguments(
        snapshot: CodeReviewSessionSnapshot,
        targetFiles: [String]
    ) -> [String] {
        guard let scope = snapshot.scope else { return [] }

        var args = ["diff", "--numstat"]
        switch scope.type {
        case .staged:
            args.append("--cached")
        case .againstRef:
            if let ref = scope.ref, !ref.isEmpty {
                args.append(CodeReviewMultiSwarmProvider.normalizedAgainstRefRevision(ref))
            }
        case .uncommitted:
            break
        }
        args.append("--")
        args.append(contentsOf: targetFiles)
        return args
    }

    private static func parseNumstatLine(_ rawLine: Substring) -> FileSummary? {
        let parts = rawLine.split(separator: "\t")
        guard parts.count >= 3 else { return nil }
        let additions = Int(parts[0]) ?? 0
        let deletions = Int(parts[1]) ?? 0
        let filePath = String(parts[2])
        return FileSummary(
            filePath: filePath,
            additions: additions,
            deletions: deletions
        )
    }
}
