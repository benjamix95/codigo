import Foundation

// MARK: - Coverage Parser

/// Parsa i dati di code coverage dal formato JSON generato da `swift test --enable-code-coverage`.
actor CoverageParser {
    /// Parsa il report di coverage dal file JSON prodotto da llvm-cov.
    func parseCoverageReport(at jsonPath: String) async -> CoverageReport {
        guard FileManager.default.fileExists(atPath: jsonPath) else {
            return .failure(error: "File coverage non trovato: \(jsonPath)")
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)) else {
            return .failure(error: "Impossibile leggere il file coverage.")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(error: "Formato JSON coverage non valido.")
        }

        return parseJSON(json)
    }

    /// Genera il report di coverage eseguendo `swift test --enable-code-coverage`.
    func generateCoverage(projectPath: String) async -> CoverageReport {
        let testResult = await runSwiftTest(projectPath: projectPath)
        guard testResult.exitCode == 0 else {
            return .failure(error: "Test falliti. Coverage non generato.")
        }

        let profDataPath = findProfData(projectPath: projectPath)
        guard let profPath = profDataPath else {
            return .failure(error: "File .profdata non trovato dopo l'esecuzione dei test.")
        }

        let coverageJSON = await exportCoverageJSON(profDataPath: profPath, projectPath: projectPath)
        guard let jsonPath = coverageJSON else {
            return .failure(error: "Impossibile esportare coverage JSON.")
        }

        return await parseCoverageReport(at: jsonPath)
    }

    // MARK: - Private

    private func parseJSON(_ json: [String: Any]) -> CoverageReport {
        guard let dataArray = json["data"] as? [[String: Any]],
              let firstData = dataArray.first,
              let files = firstData["files"] as? [[String: Any]] else {
            return .failure(error: "Struttura JSON coverage non riconosciuta.")
        }

        var coverageFiles: [FileCoverage] = []
        var totalCovered = 0
        var totalExecutable = 0

        for file in files {
            guard let filename = file["filename"] as? String,
                  let summary = file["summary"] as? [String: Any],
                  let lines = summary["lines"] as? [String: Any],
                  let covered = lines["covered"] as? Int,
                  let count = lines["count"] as? Int else { continue }

            let lineHits = parseLineHits(from: file)
            let fileCoverage = FileCoverage(
                filePath: filename,
                coveredLines: covered,
                executableLines: count,
                lineHits: lineHits
            )
            coverageFiles.append(fileCoverage)
            totalCovered += covered
            totalExecutable += count
        }

        return CoverageReport(
            files: coverageFiles.sorted { $0.filePath < $1.filePath },
            totalCoveredLines: totalCovered,
            totalExecutableLines: totalExecutable,
            error: nil
        )
    }

    private func parseLineHits(from file: [String: Any]) -> [Int: Int] {
        guard let segments = file["segments"] as? [[Any]] else { return [:] }
        var hits: [Int: Int] = [:]
        for segment in segments {
            guard segment.count >= 3,
                  let line = segment[0] as? Int,
                  let count = segment[2] as? Int else { continue }
            hits[line] = count
        }
        return hits
    }

    private func runSwiftTest(projectPath: String) async -> TestProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = ["test", "--enable-code-coverage", "--package-path", projectPath]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do { try process.run() } catch {
                continuation.resume(returning: TestProcessResult(exitCode: 1, stdout: "", stderr: error.localizedDescription))
                return
            }

            process.terminationHandler = { proc in
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: TestProcessResult(exitCode: proc.terminationStatus, stdout: out, stderr: err))
            }
        }
    }

    private func findProfData(projectPath: String) -> String? {
        let buildDir = "\(projectPath)/.build/debug/codecov"
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: buildDir) else { return nil }
        return contents.first(where: { $0.hasSuffix(".profdata") }).map { "\(buildDir)/\($0)" }
    }

    private func exportCoverageJSON(profDataPath: String, projectPath: String) async -> String? {
        let outputPath = "\(projectPath)/.build/debug/coverage.json"
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<TestProcessResult, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "llvm-cov", "export",
                "-instr-profile=\(profDataPath)",
                "-format=json",
                "\(projectPath)/.build/debug/PackageTests"
            ]

            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = Pipe()

            do { try process.run() } catch {
                continuation.resume(returning: TestProcessResult(exitCode: 1, stdout: "", stderr: ""))
                return
            }

            process.terminationHandler = { proc in
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: TestProcessResult(exitCode: proc.terminationStatus, stdout: out, stderr: ""))
            }
        }

        guard result.exitCode == 0, !result.stdout.isEmpty else { return nil }
        try? result.stdout.write(toFile: outputPath, atomically: true, encoding: .utf8)
        return outputPath
    }
}
