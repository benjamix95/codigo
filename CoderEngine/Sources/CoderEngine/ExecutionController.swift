import Foundation

public enum ExecutionScope: String, Sendable {
    case agent
    case swarm
    case review
    case plan
    case system
}

public enum ExecutionRunState: String, Sendable {
    case idle
    case running
    case paused
    case stopping
}

/// Controller per terminare il processo in esecuzione (Codex CLI, Claude CLI, ecc.)
/// Usato dal pulsante "Ferma" per interrompere l'agente.
public final class ExecutionController: ObservableObject, @unchecked Sendable {
    private var currentProcess: Process?
    private var currentScope: ExecutionScope?
    private var _swarmStopRequested = false
    private var _swarmPauseRequested = false
    private var _runState: ExecutionRunState = .idle
    private let lock = NSLock()

    public init() {}

    /// Registra il processo corrente (chiamato da ProcessRunner)
    public func setCurrentProcess(_ process: Process) {
        lock.withLock {
            currentProcess = process
            _runState = .running
        }
    }

    public func beginScope(_ scope: ExecutionScope) {
        lock.withLock {
            currentScope = scope
            _runState = .running
        }
    }

    /// Rimuove il riferimento al processo (chiamato quando il processo termina)
    public func clearCurrentProcess() {
        lock.withLock {
            currentProcess = nil
            currentScope = nil
            _runState = .idle
        }
    }

    /// Termina il processo corrente. Chiamato dal pulsante Ferma.
    public func terminateCurrent() {
        lock.withLock {
            _runState = .stopping
            currentProcess?.terminate()
            currentProcess = nil
            currentScope = nil
            _runState = .idle
        }
    }

    public func terminate(scope: ExecutionScope) {
        lock.withLock {
            if currentScope == scope || scope == .system {
                _runState = .stopping
                currentProcess?.terminate()
                currentProcess = nil
                currentScope = nil
                _runState = .idle
            }
            if scope == .swarm || scope == .system {
                _swarmStopRequested = true
            }
        }
    }

    public func pause(scope: ExecutionScope) {
        lock.withLock {
            guard currentScope == scope || scope == .system else { return }
            if let process = currentProcess {
                _ = process.suspend()
            }
            _runState = .paused
            if scope == .swarm || currentScope == .swarm || scope == .system {
                _swarmPauseRequested = true
            }
        }
    }

    public func resume(scope: ExecutionScope) {
        lock.withLock {
            guard currentScope == scope || scope == .system else { return }
            if let process = currentProcess {
                _ = process.resume()
            }
            _runState = .running
            if scope == .swarm || currentScope == .swarm || scope == .system {
                _swarmPauseRequested = false
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

    public func clearSwarmPauseRequested() {
        lock.withLock { _swarmPauseRequested = false }
    }

    /// Indica se è stata richiesta l'interruzione dello Swarm
    public var swarmStopRequested: Bool { lock.withLock { _swarmStopRequested } }
    public var swarmPauseRequested: Bool { lock.withLock { _swarmPauseRequested } }
    public var activeScope: ExecutionScope? { lock.withLock { currentScope } }
    public var runState: ExecutionRunState { lock.withLock { _runState } }
}
