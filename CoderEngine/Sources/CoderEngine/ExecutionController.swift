import Foundation

public enum ExecutionScope: String, Sendable {
    case agent
    case swarm
    case review
    case plan
    case system
}

/// Controller per terminare il processo in esecuzione (Codex CLI, Claude CLI, ecc.)
/// Usato dal pulsante "Ferma" per interrompere l'agente.
public final class ExecutionController: ObservableObject, @unchecked Sendable {
    private var currentProcess: Process?
    private var currentScope: ExecutionScope?
    private var _swarmStopRequested = false
    private let lock = NSLock()

    public init() {}

    /// Registra il processo corrente (chiamato da ProcessRunner)
    public func setCurrentProcess(_ process: Process) {
        lock.withLock { currentProcess = process }
    }

    public func beginScope(_ scope: ExecutionScope) {
        lock.withLock { currentScope = scope }
    }

    /// Rimuove il riferimento al processo (chiamato quando il processo termina)
    public func clearCurrentProcess() {
        lock.withLock {
            currentProcess = nil
            currentScope = nil
        }
    }

    /// Termina il processo corrente. Chiamato dal pulsante Ferma.
    public func terminateCurrent() {
        lock.withLock {
            currentProcess?.terminate()
            currentProcess = nil
            currentScope = nil
        }
    }

    public func terminate(scope: ExecutionScope) {
        lock.withLock {
            if currentScope == scope || scope == .system {
                currentProcess?.terminate()
                currentProcess = nil
                currentScope = nil
            }
            if scope == .swarm || scope == .system {
                _swarmStopRequested = true
            }
        }
    }

    /// Richiesta di stop per lo Swarm: non avviare nuovi agenti. Chiamato da Ferma quando in Swarm.
    public func requestSwarmStop() {
        lock.withLock { _swarmStopRequested = true }
    }

    /// Resetta la richiesta di stop (chiamato all'inizio di ogni esecuzione Swarm)
    public func clearSwarmStopRequested() {
        lock.withLock { _swarmStopRequested = false }
    }

    /// Indica se è stata richiesta l'interruzione dello Swarm
    public var swarmStopRequested: Bool { lock.withLock { _swarmStopRequested } }
    public var activeScope: ExecutionScope? { lock.withLock { currentScope } }
}
