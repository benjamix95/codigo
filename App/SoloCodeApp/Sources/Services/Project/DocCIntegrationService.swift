import Foundation

// MARK: - DocC Integration Service

/// Servizio per l'integrazione con Swift-DocC: generazione e preview della documentazione.
actor DocCIntegrationService {
    /// Risultato della generazione DocC.
    struct DocCResult: Sendable {
        let outputPath: String?
        let diagnostics: [DocCDiagnostic]
        let durationSeconds: TimeInterval
        let error: String?

        var isSuccess: Bool { error == nil }
    }

    /// Diagnostica DocC (warning/error dalla compilazione docs).
    struct DocCDiagnostic: Identifiable, Sendable {
        let id: String
        let severity: Severity
        let message: String
        let filePath: String?
        let line: Int?

        enum Severity: String, Sendable {
            case warning
            case error
            case note
        }
    }

    // MARK: - Generazione

    /// Genera la documentazione DocC per un progetto Swift Package.
    func generateDocumentation(
        projectPath: String,
        targetName: String? = nil
    ) async -> DocCResult {
        let startTime = Date()

        var args = ["package", "generate-documentation"]
        if let target = targetName {
            args.append(contentsOf: ["--target", target])
        }

        let result = await runSwift(arguments: args, workingDirectory: projectPath)

        let diagnostics = parseDiagnostics(output: result.stdout + "\n" + result.stderr)
        let outputPath = findOutputPath(in: result.stdout, projectPath: projectPath)
        let duration = Date().timeIntervalSince(startTime)

        if result.exitCode != 0 {
            return DocCResult(
                outputPath: nil,
                diagnostics: diagnostics,
                durationSeconds: duration,
                error: result.stderr.isEmpty ? "Generazione DocC fallita" : result.stderr
            )
        }

        return DocCResult(
            outputPath: outputPath,
            diagnostics: diagnostics,
            durationSeconds: duration,
            error: nil
        )
    }

    /// Avvia il server di preview DocC.
    func startPreview(
        projectPath: String,
        targetName: String? = nil,
        port: Int = 8080
    ) async -> (pid: Int32?, error: String?) {
        var args = ["package", "preview-documentation", "--port", String(port)]
        if let target = targetName {
            args.append(contentsOf: ["--target", target])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            return (process.processIdentifier, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    /// Verifica la copertura della documentazione per un target.
    ///
    /// Returns the count of undocumented symbols and the associated warnings.
    /// A percentage is not returned because the total symbol count cannot be
    /// determined from DocC warning output alone; callers should not fabricate
    /// an estimate.
    func checkDocumentationCoverage(
        projectPath: String,
        targetName: String
    ) async -> (undocumentedCount: Int, warnings: [DocCDiagnostic]) {
        let result = await runSwift(
            arguments: ["package", "generate-documentation", "--target", targetName, "--warnings-as-errors"],
            workingDirectory: projectPath
        )

        let output = result.stdout + "\n" + result.stderr
        let warnings = parseDiagnostics(output: output).filter { $0.severity == .warning }
        let undocumentedWarnings = warnings.filter {
            $0.message.lowercased().contains("undocumented") ||
            $0.message.lowercased().contains("no documentation")
        }

        return (undocumentedWarnings.count, undocumentedWarnings)
    }

    // MARK: - Privato

    private struct ProcessResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func runSwift(arguments: [String], workingDirectory: String) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do { try process.run() } catch {
                continuation.resume(returning: ProcessResult(
                    exitCode: 1, stdout: "", stderr: error.localizedDescription
                ))
                return
            }

            process.terminationHandler = { proc in
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: ProcessResult(
                    exitCode: proc.terminationStatus, stdout: out, stderr: err
                ))
            }
        }
    }

    private func parseDiagnostics(output: String) -> [DocCDiagnostic] {
        let lines = output.components(separatedBy: .newlines)
        var diagnostics: [DocCDiagnostic] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let severity: DocCDiagnostic.Severity
            if trimmed.contains("warning:") {
                severity = .warning
            } else if trimmed.contains("error:") {
                severity = .error
            } else if trimmed.contains("note:") {
                severity = .note
            } else {
                continue
            }

            // Formato: /path/file.swift:line:col: warning: message
            let parts = trimmed.components(separatedBy: ": ")
            let message = parts.dropFirst(2).joined(separator: ": ")
            let location = parts.first ?? ""
            let locationParts = location.components(separatedBy: ":")

            diagnostics.append(DocCDiagnostic(
                id: UUID().uuidString,
                severity: severity,
                message: message.isEmpty ? trimmed : message,
                filePath: locationParts.first,
                line: locationParts.count > 1 ? Int(locationParts[1]) : nil
            ))
        }

        return diagnostics
    }

    private func findOutputPath(in output: String, projectPath: String) -> String? {
        // DocC output tipicamente in .build/plugins/Swift-DocC/outputs
        let buildPath = (projectPath as NSString)
            .appendingPathComponent(".build/plugins/Swift-DocC/outputs")
        if FileManager.default.fileExists(atPath: buildPath) {
            return buildPath
        }
        return nil
    }
}
