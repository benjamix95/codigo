import Foundation

// MARK: - Git Blame Service

/// Servizio per git blame con parsing porcelain e annotations inline.
actor GitBlameService {
    /// Annotazione blame per una singola riga.
    struct BlameAnnotation: Identifiable, Sendable {
        let id: String
        let line: Int
        let commitHash: String
        let author: String
        let authorDate: Date?
        let summary: String

        init(line: Int, commitHash: String, author: String, authorDate: Date? = nil, summary: String) {
            self.id = "\(commitHash):\(line)"
            self.line = line
            self.commitHash = commitHash
            self.author = author
            self.authorDate = authorDate
            self.summary = summary
        }
    }

    /// Risultato di git blame per un file.
    struct BlameResult: Sendable {
        let filePath: String
        let annotations: [BlameAnnotation]
        let error: String?

        var isSuccess: Bool { error == nil }
    }

    /// Esegue git blame su un file e restituisce le annotations.
    func blame(filePath: String, workspacePath: String) async -> BlameResult {
        let result = await runGit(
            arguments: ["blame", "--porcelain", filePath],
            workingDirectory: workspacePath
        )

        guard result.exitCode == 0 else {
            return BlameResult(
                filePath: filePath,
                annotations: [],
                error: result.stderr.isEmpty ? "Git blame fallito." : result.stderr
            )
        }

        let annotations = parsePorcelainBlame(output: result.stdout)
        return BlameResult(filePath: filePath, annotations: annotations, error: nil)
    }

    /// Esegue git blame per un range di righe.
    func blameRange(
        filePath: String,
        startLine: Int,
        endLine: Int,
        workspacePath: String
    ) async -> BlameResult {
        let result = await runGit(
            arguments: ["blame", "--porcelain", "-L", "\(startLine),\(endLine)", filePath],
            workingDirectory: workspacePath
        )

        guard result.exitCode == 0 else {
            return BlameResult(filePath: filePath, annotations: [], error: result.stderr)
        }

        let annotations = parsePorcelainBlame(output: result.stdout)
        return BlameResult(filePath: filePath, annotations: annotations, error: nil)
    }

    // MARK: - Porcelain Parser

    private func parsePorcelainBlame(output: String) -> [BlameAnnotation] {
        let lines = output.components(separatedBy: .newlines)
        var annotations: [BlameAnnotation] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            // Header: <hash> <orig_line> <final_line> [<num_lines>]
            let headerParts = line.split(separator: " ")
            guard headerParts.count >= 3,
                  headerParts[0].count == 40,
                  let finalLine = Int(headerParts[2]) else {
                i += 1
                continue
            }

            let commitHash = String(headerParts[0])
            var author = ""
            var authorDate: Date?
            var summary = ""

            // Leggi le righe di metadati fino alla riga di contenuto (prefisso tab)
            i += 1
            while i < lines.count && !lines[i].hasPrefix("\t") {
                let metaLine = lines[i]
                if metaLine.hasPrefix("author ") {
                    author = String(metaLine.dropFirst("author ".count))
                } else if metaLine.hasPrefix("author-time ") {
                    if let timestamp = TimeInterval(metaLine.dropFirst("author-time ".count)) {
                        authorDate = Date(timeIntervalSince1970: timestamp)
                    }
                } else if metaLine.hasPrefix("summary ") {
                    summary = String(metaLine.dropFirst("summary ".count))
                }
                i += 1
            }

            // Salta la riga di contenuto (prefisso tab)
            if i < lines.count && lines[i].hasPrefix("\t") {
                i += 1
            }

            annotations.append(BlameAnnotation(
                line: finalLine,
                commitHash: commitHash,
                author: author,
                authorDate: authorDate,
                summary: summary
            ))
        }

        return annotations.sorted { $0.line < $1.line }
    }

    // MARK: - Private

    private func runGit(arguments: [String], workingDirectory: String) async -> BlameProcessResult {
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
                continuation.resume(returning: BlameProcessResult(exitCode: 1, stdout: "", stderr: error.localizedDescription))
                return
            }

            process.terminationHandler = { proc in
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: BlameProcessResult(exitCode: proc.terminationStatus, stdout: out, stderr: err))
            }
        }
    }
}

private struct BlameProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
