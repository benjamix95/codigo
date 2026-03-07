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
        let args = diffArguments(snapshot: snapshot)
        guard !args.isEmpty else { return [] }
        guard let text = runGit(arguments: args, workspacePath: workspacePath) else {
            return []
        }

        let targetFileSet = Set(targetFiles)
        var summariesByFile: [String: FileSummary] = [:]
        for rawLine in text.split(separator: "\n") {
            guard let parsed = parseNumstatLine(rawLine) else { continue }
            let matches = parsed.candidatePaths.filter { targetFileSet.contains($0) }
            for filePath in matches {
                let current = summariesByFile[filePath] ?? FileSummary(
                    filePath: filePath,
                    additions: 0,
                    deletions: 0
                )
                summariesByFile[filePath] = FileSummary(
                    filePath: filePath,
                    additions: current.additions + parsed.additions,
                    deletions: current.deletions + parsed.deletions
                )
            }
        }

        let untracked = untrackedFiles(workspacePath: workspacePath, targetFiles: targetFiles)
        for filePath in untracked where summariesByFile[filePath] == nil {
            summariesByFile[filePath] = FileSummary(
                filePath: filePath,
                additions: lineCount(
                    at: workspacePath.appendingPathComponent(filePath)
                ),
                deletions: 0
            )
        }

        return targetFiles.compactMap { summariesByFile[$0] }
    }

    private static func diffArguments(
        snapshot: CodeReviewSessionSnapshot
    ) -> [String] {
        guard let scope = snapshot.scope else { return [] }

        var args = ["diff", "--numstat", "-M", "-C"]
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
        return args
    }

    private static func parseNumstatLine(
        _ rawLine: Substring
    ) -> (additions: Int, deletions: Int, candidatePaths: [String])? {
        let parts = rawLine.split(separator: "\t")
        guard parts.count >= 3 else { return nil }
        let additions = Int(parts[0]) ?? 0
        let deletions = Int(parts[1]) ?? 0
        let rawPath = String(parts[2])
        let candidatePaths = renameAwarePaths(from: rawPath)
        guard !candidatePaths.isEmpty else { return nil }
        return (
            additions: max(0, additions),
            deletions: max(0, deletions),
            candidatePaths: candidatePaths
        )
    }

    private static func renameAwarePaths(from rawPath: String) -> [String] {
        var candidates = Set<String>()
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        candidates.insert(trimmed)
        if let expanded = expandedBraceRenamePaths(from: trimmed) {
            candidates.formUnion(expanded)
        } else if trimmed.contains(" => ") {
            let parts = trimmed.components(separatedBy: " => ")
            if parts.count == 2 {
                candidates.insert(parts[0].trimmingCharacters(in: .whitespacesAndNewlines))
                candidates.insert(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private static func expandedBraceRenamePaths(from rawPath: String) -> [String]? {
        guard let openBrace = rawPath.firstIndex(of: "{"),
              let closeBrace = rawPath[openBrace...].firstIndex(of: "}"),
              openBrace < closeBrace
        else {
            return nil
        }

        let prefix = String(rawPath[..<openBrace])
        let body = String(rawPath[rawPath.index(after: openBrace)..<closeBrace])
        let suffix = String(rawPath[rawPath.index(after: closeBrace)...])
        let bodyParts = body.components(separatedBy: " => ")
        guard bodyParts.count == 2 else { return nil }
        return [
            prefix + bodyParts[0] + suffix,
            prefix + bodyParts[1] + suffix,
        ]
    }

    private static func runGit(
        arguments: [String],
        workspacePath: URL
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = workspacePath

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputState = StreamCaptureState()
        let errorState = StreamCaptureState()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputState.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorState.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputState.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorState.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        guard process.terminationStatus == 0 else {
            return nil
        }
        return String(data: outputState.data, encoding: .utf8)
    }

    private static func untrackedFiles(
        workspacePath: URL,
        targetFiles: [String]
    ) -> Set<String> {
        guard !targetFiles.isEmpty else { return [] }
        let args = ["ls-files", "--others", "--exclude-standard", "--"] + targetFiles
        guard let output = runGit(arguments: args, workspacePath: workspacePath) else {
            return []
        }
        return Set(
            output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private static func lineCount(at fileURL: URL) -> Int {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return 0
        }
        if text.isEmpty {
            return 0
        }

        var lineCount = 0
        text.enumerateLines { _, _ in
            lineCount += 1
        }
        if text.hasSuffix("\n") {
            return lineCount
        }
        return max(1, lineCount)
    }
}

private final class StreamCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }
}
