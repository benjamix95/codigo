import Foundation

/// Backend dell'orchestratore
public enum OrchestratorBackend: String, CaseIterable, Codable, Sendable {
    case openai
    case codex
    case claude
    case gemini
}

/// Backend dei worker
public enum WorkerBackend: String, CaseIterable, Codable, Sendable {
    case codex
    case claude
    case gemini
}

/// Override per-role del backend worker.
/// Permette di assegnare un backend diverso a ciascun ruolo specializzato.
/// Esempio: Coder → claude, Reviewer → gemini, TestWriter → codex
public struct WorkerBackendOverrides: Sendable, Equatable {
    private let mapping: [AgentRole: WorkerBackend]

    public init(_ mapping: [AgentRole: WorkerBackend] = [:]) {
        self.mapping = mapping
    }

    /// Ritorna il backend specifico per il ruolo, oppure `nil` se si usa il default.
    public func backend(for role: AgentRole) -> WorkerBackend? {
        mapping[role]
    }

    /// Ritorna il backend effettivo: override per-role se presente, altrimenti il default globale.
    public func effectiveBackend(for role: AgentRole, default fallback: WorkerBackend)
        -> WorkerBackend
    {
        mapping[role] ?? fallback
    }

    public var isEmpty: Bool { mapping.isEmpty }

    public var allOverrides: [AgentRole: WorkerBackend] { mapping }

    /// Crea una nuova istanza aggiungendo o sovrascrivendo un mapping.
    public func setting(_ role: AgentRole, to backend: WorkerBackend?) -> WorkerBackendOverrides {
        var copy = mapping
        if let backend {
            copy[role] = backend
        } else {
            copy.removeValue(forKey: role)
        }
        return WorkerBackendOverrides(copy)
    }

    /// Serializza in stringa per persistenza (es. "coder:claude,reviewer:gemini")
    public func serialize() -> String {
        mapping
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue):\($0.value.rawValue)" }
            .joined(separator: ",")
    }

    /// Deserializza dalla stringa serializzata
    public static func deserialize(_ raw: String) -> WorkerBackendOverrides {
        var mapping: [AgentRole: WorkerBackend] = [:]
        for token in raw.components(separatedBy: ",") {
            let parts = token.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: ":")
            guard parts.count == 2,
                let role = AgentRole(rawValue: parts[0].trimmingCharacters(in: .whitespaces)),
                let backend = WorkerBackend(rawValue: parts[1].trimmingCharacters(in: .whitespaces))
            else { continue }
            mapping[role] = backend
        }
        return WorkerBackendOverrides(mapping)
    }
}

/// Configurazione del swarm di agenti
public struct SwarmConfig: Sendable {
    public let orchestratorBackend: OrchestratorBackend
    public let workerBackend: WorkerBackend
    public let workerBackendOverrides: WorkerBackendOverrides
    public let enabledRoles: Set<AgentRole>
    public let maxRounds: Int
    public let autoPostCodePipeline: Bool
    public let maxPostCodeRetries: Int
    public let maxReviewLoops: Int

    public init(
        orchestratorBackend: OrchestratorBackend = .openai,
        workerBackend: WorkerBackend = .codex,
        workerBackendOverrides: WorkerBackendOverrides = WorkerBackendOverrides(),
        enabledRoles: Set<AgentRole>? = nil,
        maxRounds: Int = 1,
        autoPostCodePipeline: Bool = true,
        maxPostCodeRetries: Int = 10,
        maxReviewLoops: Int = 2
    ) {
        self.orchestratorBackend = orchestratorBackend
        self.workerBackend = workerBackend
        self.workerBackendOverrides = workerBackendOverrides
        self.enabledRoles = enabledRoles ?? Set(AgentRole.allCases)
        self.maxRounds = maxRounds
        self.autoPostCodePipeline = autoPostCodePipeline
        self.maxPostCodeRetries = maxPostCodeRetries
        self.maxReviewLoops = min(5, max(0, maxReviewLoops))
    }

    /// Ritorna il backend effettivo per un dato ruolo, risolvendo eventuali override.
    public func effectiveWorkerBackend(for role: AgentRole) -> WorkerBackend {
        workerBackendOverrides.effectiveBackend(for: role, default: workerBackend)
    }
}
