import Foundation

// MARK: - SwiftFormat CLI Adapter

/// Adapter per il formatter swift-format (Apple o Airbnb SwiftFormat).
/// Esegue il formatter come processo CLI e cattura l'output.
actor SwiftFormatAdapter: FormattingAdapter {
    nonisolated let formatterType: FormatterType = .swiftFormat
    private let executablePath: String
    private let timeoutNanoseconds: UInt64 = 10_000_000_000

    init(executablePath: String = "swift-format") {
        self.executablePath = executablePath
    }

    func format(content: String, filePath: String, options: FormattingOptions) async -> FormattingResult {
        guard await isAvailable() else {
            return .failure(filePath: filePath, error: "swift-format non trovato in PATH: \(executablePath)")
        }

        let args = buildFormatArguments(filePath: filePath, options: options)
        let result = await executeProcess(arguments: args, stdin: content)

        guard result.exitCode == 0 else {
            let errorMsg = result.stderr.isEmpty ? "Formattazione fallita (exit code \(result.exitCode))" : result.stderr
            return .failure(filePath: filePath, error: errorMsg)
        }

        return .success(original: content, formatted: result.stdout, filePath: filePath)
    }

    func formatFile(at path: String, options: FormattingOptions) async -> FormattingResult {
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure(filePath: path, error: "File non trovato: \(path)")
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return .failure(filePath: path, error: "Impossibile leggere il file: \(path)")
        }

        return await format(content: content, filePath: path, options: options)
    }

    nonisolated func isAvailable() async -> Bool {
        let result = await Self.runProcess(
            executablePath: "/usr/bin/which",
            arguments: [executablePath],
            stdin: nil
        )
        return result.exitCode == 0
    }

    // MARK: - Private

    private func buildFormatArguments(filePath: String, options: FormattingOptions) -> [String] {
        var args = ["format", "--assume-filename", filePath]
        args.append(contentsOf: ["--indent-width", "\(options.indentWidth)"])
        args.append(contentsOf: ["--tab-width", "\(options.tabWidth)"])
        if options.useTabs {
            args.append("--indent-using-tabs")
        }
        args.append(contentsOf: ["--line-length", "\(options.maxLineLength)"])
        return args
    }

    private func executeProcess(arguments: [String], stdin: String?) async -> ProcessResult {
        await Self.runProcess(executablePath: executablePath, arguments: arguments, stdin: stdin)
    }

    private static func runProcess(
        executablePath: String,
        arguments: [String],
        stdin: String?
    ) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executablePath] + arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            let inPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = inPipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ProcessResult(
                    exitCode: 1,
                    stdout: "",
                    stderr: "Impossibile avviare: \(error.localizedDescription)"
                ))
                return
            }

            if let stdinData = stdin?.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(stdinData)
                inPipe.fileHandleForWriting.closeFile()
            }

            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: ProcessResult(
                    exitCode: proc.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? ""
                ))
            }
        }
    }
}

// MARK: - Process Result

private struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
