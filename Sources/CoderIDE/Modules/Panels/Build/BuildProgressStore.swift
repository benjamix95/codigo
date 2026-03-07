import SwiftUI

// MARK: - Build Progress Store

/// Store per il monitoraggio del progresso di build e profiling.
@MainActor
final class BuildProgressStore: ObservableObject {
    /// Stato della build corrente.
    enum BuildState: Sendable {
        case idle
        case building
        case succeeded
        case failed(String)
        case profiling
    }

    /// Log entry della build.
    struct BuildLogEntry: Identifiable, Sendable {
        let id: String
        let timestamp: Date
        let level: LogLevel
        let message: String

        enum LogLevel: String, Sendable {
            case info
            case warning
            case error
        }
    }

    @Published var buildState: BuildState = .idle
    @Published var progress: Double = 0
    @Published var currentStep: String = ""
    @Published var logEntries: [BuildLogEntry] = []
    @Published var profilingResult: ProfileService.ProfileResult?
    @Published var memorySnapshots: [MemoryLeakDetector.MemorySnapshot] = []

    private let profileService = ProfileService()
    private let leakDetector = MemoryLeakDetector()

    // MARK: - Build

    /// Avvia una build Swift del progetto.
    func startBuild(projectPath: String) {
        guard case .idle = buildState else { return }
        buildState = .building
        progress = 0
        currentStep = "Preparazione build..."
        logEntries = []

        Task {
            await runBuild(projectPath: projectPath)
        }
    }

    // MARK: - Profiling

    /// Avvia una sessione di profiling.
    func startProfiling(pid: Int32) {
        buildState = .profiling
        currentStep = "Profiling in corso..."

        Task {
            do {
                _ = try await profileService.startProfiling(pid: pid)
            } catch {
                buildState = .failed(error.localizedDescription)
            }
        }
    }

    /// Ferma il profiling e mostra i risultati.
    func stopProfiling() {
        Task {
            let result = await profileService.stopProfiling()
            profilingResult = result
            buildState = result.isSuccess ? .succeeded : .failed(result.error ?? "Errore sconosciuto")
        }
    }

    /// Cattura uno snapshot della memoria.
    func captureMemorySnapshot() {
        Task {
            let snapshot = await leakDetector.captureSnapshot()
            memorySnapshots.append(snapshot)
        }
    }

    /// Esegue il leak detector.
    func detectLeaks() {
        Task {
            _ = await leakDetector.detectLeaks()
            let snapshot = await leakDetector.captureSnapshot()
            memorySnapshots.append(snapshot)
        }
    }

    func clearLogs() {
        logEntries = []
    }

    // MARK: - Privato

    private func runBuild(projectPath: String) async {
        let result = await launchBuildProcess(projectPath: projectPath)

        guard let (output, terminationStatus) = result else {
            buildState = .failed("Impossibile avviare il processo di build")
            return
        }

        parseBuildOutput(output)

        if terminationStatus == 0 {
            progress = 1.0
            currentStep = "Build completata"
            buildState = .succeeded
        } else {
            buildState = .failed("Build fallita con codice \(terminationStatus)")
        }
    }

    private func launchBuildProcess(projectPath: String) async -> (output: String, terminationStatus: Int32)? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = ["build"]
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let lock = NSLock()
            var didResume = false

            func readProcessOutput(status: Int32) -> (output: String, terminationStatus: Int32) {
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                return (stdout + "\n" + stderr, status)
            }

            func resumeOnce(_ value: (output: String, terminationStatus: Int32)?) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: value)
            }

            process.terminationHandler = { proc in
                resumeOnce(readProcessOutput(status: proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                resumeOnce(nil)
                return
            }

            if !process.isRunning {
                resumeOnce(readProcessOutput(status: process.terminationStatus))
            }
        }
    }

    private func parseBuildOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let level: BuildLogEntry.LogLevel
            if trimmed.contains("error:") {
                level = .error
            } else if trimmed.contains("warning:") {
                level = .warning
            } else {
                level = .info
            }

            logEntries.append(BuildLogEntry(
                id: UUID().uuidString,
                timestamp: Date(),
                level: level,
                message: trimmed
            ))

            // Aggiorna progresso da output di swift build
            if trimmed.hasPrefix("[") {
                if let progress = parseBuildProgress(trimmed) {
                    self.progress = progress
                    self.currentStep = trimmed
                }
            }
        }
    }

    private func parseBuildProgress(_ line: String) -> Double? {
        // Formato: [N/M] Compiling ...
        guard let slashIdx = line.firstIndex(of: "/"),
              let closeIdx = line.firstIndex(of: "]"),
              let openIdx = line.firstIndex(of: "[") else { return nil }

        let currentStr = line[line.index(after: openIdx)..<slashIdx]
        let totalStr = line[line.index(after: slashIdx)..<closeIdx]

        guard let current = Double(currentStr), let total = Double(totalStr), total > 0 else {
            return nil
        }
        return current / total
    }
}
