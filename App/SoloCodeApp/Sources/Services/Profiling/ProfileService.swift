import Foundation

// MARK: - Profile Service

/// Servizio per il profiling delle performance dell'applicazione.
/// Coordina XCTrace e memory leak detection.
actor ProfileService {
    /// Risultato di una sessione di profiling.
    struct ProfileResult: Sendable {
        let sessionId: String
        let startedAt: Date
        let duration: TimeInterval
        let traceFilePath: String?
        let summary: ProfileSummary
        let error: String?

        var isSuccess: Bool { error == nil }
    }

    /// Sommario delle metriche raccolte.
    struct ProfileSummary: Sendable {
        let cpuUsagePercent: Double
        let peakMemoryMB: Double
        let allocations: Int
        let leaksDetected: Int
        let thermalState: String
    }

    /// Configurazione del servizio di profiling.
    struct Configuration: Sendable {
        let profilingEnabled: Bool
        let xctraceTemplatePath: String
        let outputDirectory: String
        let samplingIntervalMs: Int

        static func load() -> Configuration {
            let ud = UserDefaults.standard
            return Configuration(
                profilingEnabled: ud.bool(forKey: "profiling_enabled"),
                xctraceTemplatePath: ud.string(forKey: "xctrace_template") ?? "Time Profiler",
                outputDirectory: ud.string(forKey: "profiling_output_dir")
                    ?? NSTemporaryDirectory() + "SoloCodeProfiles",
                samplingIntervalMs: ud.integer(forKey: "profiling_sample_interval_ms").nonZero ?? 10
            )
        }
    }

    private let configuration: Configuration
    private let xctraceAdapter: XCTraceAdapter
    private let leakDetector: MemoryLeakDetector
    private var activeSession: String?

    init(configuration: Configuration = .load()) {
        self.configuration = configuration
        self.xctraceAdapter = XCTraceAdapter(
            templateName: configuration.xctraceTemplatePath,
            outputDirectory: configuration.outputDirectory
        )
        self.leakDetector = MemoryLeakDetector()
    }

    // MARK: - Sessioni

    /// Avvia una sessione di profiling per un processo.
    func startProfiling(pid: Int32) async throws -> String {
        guard activeSession == nil else {
            throw ProfileError.sessionAlreadyActive
        }

        let sessionId = UUID().uuidString
        activeSession = sessionId

        try await xctraceAdapter.startRecording(pid: pid, sessionId: sessionId)
        return sessionId
    }

    /// Ferma la sessione attiva e restituisce il risultato.
    func stopProfiling() async -> ProfileResult {
        guard let sessionId = activeSession else {
            return ProfileResult(
                sessionId: "none",
                startedAt: Date(),
                duration: 0,
                traceFilePath: nil,
                summary: ProfileSummary(
                    cpuUsagePercent: 0, peakMemoryMB: 0,
                    allocations: 0, leaksDetected: 0, thermalState: "unknown"
                ),
                error: "Nessuna sessione attiva"
            )
        }

        let traceResult = await xctraceAdapter.stopRecording(sessionId: sessionId)
        let leakCount = await leakDetector.currentLeakCount()
        activeSession = nil

        return ProfileResult(
            sessionId: sessionId,
            startedAt: traceResult.startedAt,
            duration: traceResult.duration,
            traceFilePath: traceResult.outputPath,
            summary: ProfileSummary(
                cpuUsagePercent: traceResult.cpuUsage,
                peakMemoryMB: traceResult.peakMemoryMB,
                allocations: traceResult.allocations,
                leaksDetected: leakCount,
                thermalState: currentThermalState()
            ),
            error: traceResult.error
        )
    }

    /// Verifica se xctrace è disponibile.
    func isAvailable() async -> Bool {
        await xctraceAdapter.isAvailable()
    }

    var isSessionActive: Bool { activeSession != nil }

    // MARK: - Privato

    private func currentThermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

enum ProfileError: Error, LocalizedError, Sendable {
    case sessionAlreadyActive
    case xctraceNotAvailable
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .sessionAlreadyActive:
            return "Sessione di profiling già attiva"
        case .xctraceNotAvailable:
            return "xctrace non disponibile nel sistema"
        case .recordingFailed(let reason):
            return "Registrazione fallita: \(reason)"
        }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
