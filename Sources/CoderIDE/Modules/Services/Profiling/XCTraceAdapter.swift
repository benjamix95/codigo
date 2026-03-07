import Foundation

// MARK: - XCTrace Adapter

/// Adapter per l'integrazione con xcrun xctrace per il profiling.
actor XCTraceAdapter {
    /// Risultato di una registrazione xctrace.
    struct TraceResult: Sendable {
        let sessionId: String
        let startedAt: Date
        let duration: TimeInterval
        let outputPath: String?
        let cpuUsage: Double
        let peakMemoryMB: Double
        let allocations: Int
        let error: String?
    }

    private let templateName: String
    private let outputDirectory: String
    private var activeProcess: Process?
    private var sessionStartTime: Date?
    private var currentSessionId: String?

    init(templateName: String, outputDirectory: String) {
        self.templateName = templateName
        self.outputDirectory = outputDirectory
    }

    // MARK: - Recording

    /// Avvia una registrazione xctrace per un PID.
    func startRecording(pid: Int32, sessionId: String) async throws {
        guard await isAvailable() else {
            throw ProfileError.xctraceNotAvailable
        }

        // Crea la directory output se necessario
        try? FileManager.default.createDirectory(
            atPath: outputDirectory,
            withIntermediateDirectories: true
        )

        let outputPath = (outputDirectory as NSString)
            .appendingPathComponent("\(sessionId).trace")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "xctrace", "record",
            "--template", templateName,
            "--attach", String(pid),
            "--output", outputPath
        ]

        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe() // Discard stdout

        do {
            try process.run()
        } catch {
            throw ProfileError.recordingFailed(error.localizedDescription)
        }

        activeProcess = process
        sessionStartTime = Date()
        currentSessionId = sessionId
    }

    /// Ferma la registrazione attiva.
    func stopRecording(sessionId: String) async -> TraceResult {
        let startTime = sessionStartTime ?? Date()
        let duration = Date().timeIntervalSince(startTime)

        if let process = activeProcess, process.isRunning {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let lock = NSLock()
                var didResume = false

                @Sendable func resumeOnce() {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume()
                }

                process.terminationHandler = { _ in
                    resumeOnce()
                }

                process.interrupt()

                if !process.isRunning {
                    resumeOnce()
                }
            }
        }

        let outputPath = (outputDirectory as NSString)
            .appendingPathComponent("\(sessionId).trace")

        activeProcess = nil
        sessionStartTime = nil
        currentSessionId = nil

        // Parsa il risultato dal trace file
        let stats = await parseTraceStats(at: outputPath)

        return TraceResult(
            sessionId: sessionId,
            startedAt: startTime,
            duration: duration,
            outputPath: FileManager.default.fileExists(atPath: outputPath) ? outputPath : nil,
            cpuUsage: stats.cpuUsage,
            peakMemoryMB: stats.peakMemoryMB,
            allocations: stats.allocations,
            error: stats.error
        )
    }

    /// Verifica che xctrace sia disponibile.
    func isAvailable() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xctrace", "version"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false

            @Sendable func resumeOnce(_ value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: value)
            }

            process.terminationHandler = { p in
                resumeOnce(p.terminationStatus == 0)
            }

            do {
                try process.run()
            } catch {
                resumeOnce(false)
                return
            }

            if !process.isRunning {
                resumeOnce(process.terminationStatus == 0)
            }
        }
    }

    // MARK: - Privato

    private struct TraceStats {
        var cpuUsage: Double = 0
        var peakMemoryMB: Double = 0
        var allocations: Int = 0
        var error: String?
    }

    private func parseTraceStats(at path: String) async -> TraceStats {
        // Usa xctrace export per estrarre statistiche
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xctrace", "export", "--input", path, "--toc"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let exitStatus: Int32 = await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false

            @Sendable func resumeOnce(_ value: Int32) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: value)
            }

            process.terminationHandler = { p in
                resumeOnce(p.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                resumeOnce(-1)
                return
            }

            if !process.isRunning {
                resumeOnce(process.terminationStatus)
            }
        }

        guard exitStatus >= 0 else {
            return TraceStats(error: "Failed to run xctrace export")
        }

        guard exitStatus == 0 else {
            let errOutput = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            return TraceStats(error: errOutput)
        }

        // Parsing basilare — per un'analisi dettagliata serve xctrace export XML
        let output = String(
            data: outPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        var stats = TraceStats()

        // Estrae metriche dai metadati del trace
        if output.contains("Time Profiler") || output.contains("CPU") {
            stats.cpuUsage = parseMetric(from: output, pattern: "cpu[:\\s]+([\\d.]+)")
        }
        if output.contains("Allocations") || output.contains("Memory") {
            stats.peakMemoryMB = parseMetric(from: output, pattern: "memory[:\\s]+([\\d.]+)")
            stats.allocations = Int(parseMetric(from: output, pattern: "alloc[:\\s]+([\\d]+)"))
        }

        return stats
    }

    private func parseMetric(from output: String, pattern: String) -> Double {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                in: output,
                range: NSRange(output.startIndex..., in: output)
              ),
              let range = Range(match.range(at: 1), in: output) else {
            return 0
        }
        return Double(output[range]) ?? 0
    }
}
