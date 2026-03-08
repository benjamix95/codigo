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

/// Controller for terminating the running process (Codex CLI, Claude CLI, etc.)
/// Used by the "Stop" button to interrupt the agent.
public final class ExecutionController: ObservableObject, @unchecked Sendable {
    private var currentProcess: Process?
    private var currentScope: ExecutionScope?
    private var suspendedProcessStack: [(process: Process, scope: ExecutionScope?)] = []
    private var _swarmStopRequested = false
    private var _swarmPauseRequested = false
    private var _runState: ExecutionRunState = .idle
    private let lock = NSLock()

    public init() {}

    /// Registers the current process (called by ProcessRunner)
    public func setCurrentProcess(_ process: Process) {
        lock.withLock {
            if let currentProcess {
                suspendedProcessStack.append((currentProcess, currentScope))
            }
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

    /// Ends a logical execution scope started with `beginScope`.
    ///
    /// This method is intentionally conservative:
    /// - if a matching process is still running, scope teardown is deferred
    /// - if no process is running, the controller transitions back to idle
    public func endScope(_ scope: ExecutionScope) {
        lock.withLock {
            guard currentScope == scope || scope == .system else { return }

            if let process = currentProcess {
                if process.isRunning {
                    return
                }
                currentProcess = nil
            }

            currentScope = nil
            _runState = .idle
        }
    }

    /// Clears the process reference (called when a process terminates).
    /// If a specific process is provided, clears only when it matches the tracked one.
    public func clearCurrentProcess(_ process: Process? = nil) {
        lock.withLock {
            if let process, let currentProcess, currentProcess !== process {
                return
            }
            if let previous = suspendedProcessStack.popLast() {
                currentProcess = previous.process
                currentScope = previous.scope
                _runState = .running
            } else {
                currentProcess = nil
                currentScope = nil
                _runState = .idle
            }
        }
    }

    /// Terminates the current process. Called by the Stop button.
    public func terminateCurrent() {
        lock.withLock {
            guard let process = currentProcess else {
                currentScope = nil
                _runState = .idle
                return
            }
            guard process.isRunning else {
                currentProcess = nil
                currentScope = nil
                _runState = .idle
                return
            }

            // Keep the "stopping" state until ProcessRunner observes the termination
            // and calls clearCurrentProcess(). This prevents a user stop from being
            // classified as a runtime error (e.g. exit code 15).
            _runState = .stopping
            process.terminate()
        }
    }

    public func terminate(scope: ExecutionScope) {
        lock.withLock {
            if currentScope == scope || scope == .system {
                if let process = currentProcess, process.isRunning {
                    _runState = .stopping
                    process.terminate()
                } else {
                    currentProcess = nil
                    currentScope = nil
                    _runState = .idle
                }
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

    /// Stop request for the Swarm: do not start new agents. Called by Stop when in Swarm.
    public func requestSwarmStop() {
        lock.withLock { _swarmStopRequested = true }
    }

    /// Resets the stop request (called at the start of each Swarm execution)
    public func clearSwarmStopRequested() {
        lock.withLock { _swarmStopRequested = false }
    }

    public func clearSwarmPauseRequested() {
        lock.withLock { _swarmPauseRequested = false }
    }

    /// Indicates whether Swarm interruption has been requested
    public var swarmStopRequested: Bool { lock.withLock { _swarmStopRequested } }
    public var swarmPauseRequested: Bool { lock.withLock { _swarmPauseRequested } }
    public var activeScope: ExecutionScope? { lock.withLock { currentScope } }
    public var runState: ExecutionRunState { lock.withLock { _runState } }
}
