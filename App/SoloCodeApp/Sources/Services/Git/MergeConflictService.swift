import Foundation

// MARK: - Merge Conflict Service

/// Servizio per gestione conflitti di merge Git.
/// Supporta parsing, risoluzione per hunk, e salvataggio.
actor MergeConflictService {
    /// Trova tutti i file con conflitti nel workspace.
    func findConflictedFiles(workspacePath: String) async -> [String] {
        let result = await runGit(
            arguments: ["diff", "--name-only", "--diff-filter=U"],
            workingDirectory: workspacePath
        )
        guard result.exitCode == 0 else { return [] }

        return result.stdout.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "\(workspacePath)/\($0)" }
    }

    /// Parsa i conflitti in un singolo file.
    func parseConflicts(filePath: String) -> MergeConflictParser.ParseResult {
        MergeConflictParser.parse(filePath: filePath)
    }

    /// Risolve un singolo hunk di conflitto.
    func resolveHunk(
        filePath: String,
        hunk: MergeConflictParser.ConflictHunk,
        resolution: ConflictResolution
    ) async -> Bool {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return false
        }

        let resolved = MergeConflictParser.resolveHunk(
            content: content,
            hunk: hunk,
            resolution: resolution
        )

        do {
            try resolved.write(toFile: filePath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Risolve tutti i conflitti in un file con la stessa strategia.
    func resolveAllHunks(
        filePath: String,
        resolution: ConflictResolution
    ) async -> Bool {
        let parseResult = parseConflicts(filePath: filePath)
        guard parseResult.hasConflicts else { return true }

        var content = parseResult.fullContent
        // Risolvi dall'ultimo al primo per non invalidare gli indici
        for hunk in parseResult.hunks.reversed() {
            content = MergeConflictParser.resolveHunk(
                content: content,
                hunk: hunk,
                resolution: resolution
            )
        }

        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Segna un file come risolto (`git add`).
    func markAsResolved(filePath: String, workspacePath: String) async -> Bool {
        let result = await runGit(
            arguments: ["add", filePath],
            workingDirectory: workspacePath
        )
        return result.exitCode == 0
    }

    // MARK: - Private

    private func runGit(arguments: [String], workingDirectory: String) async -> GitProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do { try process.run() } catch {
                continuation.resume(returning: GitProcessResult(exitCode: 1, stdout: "", stderr: error.localizedDescription))
                return
            }

            process.terminationHandler = { proc in
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: GitProcessResult(exitCode: proc.terminationStatus, stdout: out, stderr: err))
            }
        }
    }
}

private struct GitProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
