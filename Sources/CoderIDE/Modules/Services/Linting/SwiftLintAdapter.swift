import Foundation

// MARK: - SwiftLint CLI Adapter

/// Adapter per SwiftLint. Esegue il linter come processo CLI e parsa i diagnostici.
actor SwiftLintAdapter: LintingAdapter {
    nonisolated let linterType: LinterType = .swiftLint
    private let executablePath: String

    init(executablePath: String = "swiftlint") {
        self.executablePath = executablePath
    }

    func lint(filePath: String) async -> LintResult {
        guard await isAvailable() else {
            return .failure(filePath: filePath, error: "swiftlint non trovato: \(executablePath)")
        }

        let result = await runLint(arguments: ["lint", "--path", filePath, "--reporter", "json", "--quiet"])

        guard result.exitCode == 0 || result.exitCode == 2 else {
            let errorMsg = result.stderr.isEmpty
                ? "Linting fallito (exit code \(result.exitCode))"
                : result.stderr
            return .failure(filePath: filePath, error: errorMsg)
        }

        let diagnostics = parseDiagnostics(from: result.stdout, fallbackPath: filePath)
        return .success(filePath: filePath, diagnostics: diagnostics)
    }

    func lintDirectory(at path: String) async -> [LintResult] {
        guard await isAvailable() else {
            return [.failure(filePath: path, error: "swiftlint non trovato: \(executablePath)")]
        }

        let result = await runLint(arguments: ["lint", "--path", path, "--reporter", "json", "--quiet"])
        let diagnostics = parseDiagnostics(from: result.stdout, fallbackPath: path)

        // Raggruppa diagnostici per file
        let grouped = Dictionary(grouping: diagnostics) { $0.filePath }
        return grouped.map { filePath, diags in
            .success(filePath: filePath, diagnostics: diags)
        }
    }

    nonisolated func isAvailable() async -> Bool {
        let result = await Self.executeProcess(
            executablePath: "/usr/bin/which",
            arguments: [executablePath]
        )
        return result.exitCode == 0
    }

    /// Esegue auto-fix con SwiftLint.
    func autoFix(filePath: String) async -> LintResult {
        guard await isAvailable() else {
            return .failure(filePath: filePath, error: "swiftlint non trovato: \(executablePath)")
        }

        let result = await runLint(arguments: ["fix", "--path", filePath, "--quiet"])
        guard result.exitCode == 0 else {
            return .failure(filePath: filePath, error: result.stderr)
        }

        // Ri-esegui lint per ottenere diagnostici residui
        return await lint(filePath: filePath)
    }

    // MARK: - Private

    private func runLint(arguments: [String]) async -> SwiftLintProcessResult {
        await Self.executeProcess(executablePath: executablePath, arguments: arguments)
    }

    private func parseDiagnostics(from json: String, fallbackPath: String) -> [LintDiagnostic] {
        guard let data = json.data(using: .utf8),
              let violations = try? JSONDecoder().decode([SwiftLintViolation].self, from: data) else {
            return parseLineDiagnostics(from: json, fallbackPath: fallbackPath)
        }

        return violations.map { violation in
            LintDiagnostic(
                filePath: violation.file ?? fallbackPath,
                line: violation.line,
                column: violation.character,
                severity: violation.severity == "error" ? .error : .warning,
                message: violation.reason,
                ruleId: violation.ruleID,
                source: "swiftlint"
            )
        }
    }

    /// Fallback parser per output non-JSON.
    private func parseLineDiagnostics(from text: String, fallbackPath: String) -> [LintDiagnostic] {
        let pattern = #"(.+):(\d+):(\d+): (warning|error): (.+) \((\w+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        return matches.compactMap { match -> LintDiagnostic? in
            guard match.numberOfRanges == 7 else { return nil }
            let file = nsText.substring(with: match.range(at: 1))
            let line = Int(nsText.substring(with: match.range(at: 2))) ?? 0
            let col = Int(nsText.substring(with: match.range(at: 3)))
            let severityStr = nsText.substring(with: match.range(at: 4))
            let message = nsText.substring(with: match.range(at: 5))
            let rule = nsText.substring(with: match.range(at: 6))

            return LintDiagnostic(
                filePath: file,
                line: line,
                column: col,
                severity: severityStr == "error" ? .error : .warning,
                message: message,
                ruleId: rule,
                source: "swiftlint"
            )
        }
    }

    private static func executeProcess(
        executablePath: String,
        arguments: [String]
    ) async -> SwiftLintProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executablePath] + arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: SwiftLintProcessResult(
                    exitCode: 1, stdout: "", stderr: error.localizedDescription
                ))
                return
            }

            process.terminationHandler = { proc in
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: SwiftLintProcessResult(
                    exitCode: proc.terminationStatus, stdout: out, stderr: err
                ))
            }
        }
    }
}

// MARK: - Internal Models

private struct SwiftLintProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private struct SwiftLintViolation: Codable {
    let file: String?
    let line: Int
    let character: Int?
    let severity: String
    let reason: String
    let ruleID: String

    enum CodingKeys: String, CodingKey {
        case file, line, character, severity, reason
        case ruleID = "rule_id"
    }
}
