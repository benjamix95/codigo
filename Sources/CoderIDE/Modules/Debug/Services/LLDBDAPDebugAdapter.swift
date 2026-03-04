import Foundation

protocol NativeDebugAdapter: Sendable {
    var name: String { get }
    func startSession(
        targetPath: String,
        arguments: [String],
        breakpoints: [DebugBreakpoint],
        watchExpressions: [String]
    ) async -> NativeDebugSessionState
    func syncBreakpoints(_ breakpoints: [DebugBreakpoint]) async -> NativeDebugSessionState
    func syncWatches(_ expressions: [String]) async -> NativeDebugSessionState
    func step(command: String) async -> NativeDebugSessionState
    func refresh() async -> NativeDebugSessionState
    func stopSession() async -> NativeDebugSessionState
}

actor LLDBDAPDebugAdapter: NativeDebugAdapter {
    struct LLDBBatchExecutionResult: Sendable {
        let exitCode: Int32
        let output: String
    }

    typealias LLDBBatchRunner = @Sendable ([String]) async -> LLDBBatchExecutionResult
    typealias LLDBSessionFactory = @Sendable () async throws -> LLDBCommandSession

    enum ExecutionEngine {
        case persistent(LLDBSessionFactory)
        case batch(LLDBBatchRunner)
    }

    private static let liveSessionFactory: LLDBSessionFactory = {
        try LLDBPersistentSession()
    }

    nonisolated let name = "lldb-dap"
    let engine: ExecutionEngine
    var persistentSession: LLDBCommandSession?
    var state: NativeDebugSessionState = .idle
    var activeBreakpoints: [DebugBreakpoint] = []
    var watchExpressions: [String] = []
    var targetPath: String?
    var arguments: [String] = []
    var isSessionActive = false

    init() {
        self.engine = .persistent(Self.liveSessionFactory)
    }

    init(sessionFactory: @escaping LLDBSessionFactory) {
        self.engine = .persistent(sessionFactory)
    }

    init(runBatch: @escaping LLDBBatchRunner) {
        self.engine = .batch(runBatch)
    }

    func startSession(
        targetPath: String,
        arguments: [String],
        breakpoints: [DebugBreakpoint],
        watchExpressions: [String]
    ) async -> NativeDebugSessionState {
        self.targetPath = targetPath
        self.arguments = arguments
        self.activeBreakpoints = breakpoints.filter(\.isActive)
        self.watchExpressions = watchExpressions
        isSessionActive = false
        state = makeBaseState(status: .running, command: "start")

        guard LLDBDAPDebugAdapterSupport.isRunnableTarget(atPath: targetPath) else {
            state.status = .error
            state.lastError = "Target non eseguibile: \(targetPath)"
            state.updatedAt = Date()
            return state
        }

        switch engine {
        case .persistent(let factory):
            await closePersistentSession()
            do {
                let session = try await factory()
                persistentSession = session
                isSessionActive = true
                let commands = buildBootstrapCommands(targetPath: targetPath) + runtimeInspectionCommands()
                return await executePersistent(
                    commands: commands,
                    lastCommand: "process launch --stop-at-entry",
                    fallbackStatus: .paused
                )
            } catch {
                state.status = .error
                state.lastError = "LLDB non disponibile: \(error.localizedDescription)"
                state.updatedAt = Date()
                return state
            }
        case .batch(let runBatch):
            let version = await runBatch(["version"])
            if version.exitCode != 0 {
                state.status = .error
                state.lastError = version.output.isEmpty ? "LLDB non disponibile" : version.output
                state.updatedAt = Date()
                return state
            }
            isSessionActive = true
            return await executeBatchCycle(
                actionCommand: nil,
                lastCommand: "process launch --stop-at-entry",
                fallbackStatus: .paused
            )
        }
    }

    func syncBreakpoints(_ breakpoints: [DebugBreakpoint]) async -> NativeDebugSessionState {
        activeBreakpoints = breakpoints.filter(\.isActive)
        state = makeBaseState(status: state.status, command: "sync_breakpoints")
        state.breakpointsCount = activeBreakpoints.count
        state.updatedAt = Date()
        guard isSessionActive else { return state }

        let commands = ["breakpoint delete --all"] + breakpointCommands() + runtimeInspectionCommands()
        return await execute(commands: commands, lastCommand: "sync_breakpoints", fallbackStatus: state.status)
    }

    func syncWatches(_ expressions: [String]) async -> NativeDebugSessionState {
        watchExpressions = expressions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        state = makeBaseState(status: state.status, command: "sync_watches")
        state.updatedAt = Date()
        guard isSessionActive else { return state }
        return await execute(
            commands: runtimeInspectionCommands(),
            lastCommand: "sync_watches",
            fallbackStatus: state.status
        )
    }

    func step(command: String) async -> NativeDebugSessionState {
        guard isSessionActive else { return state }
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return state }
        let executionCommand = LLDBDAPDebugAdapterSupport.normalizeExecutionCommand(normalized)
        let fallbackStatus: NativeDebugStatus = LLDBDAPDebugAdapterSupport.isContinueLikeCommand(executionCommand) ? .running : .paused
        state = makeBaseState(status: fallbackStatus, command: executionCommand)
        return await execute(
            commands: [executionCommand] + runtimeInspectionCommands(),
            lastCommand: executionCommand,
            fallbackStatus: fallbackStatus
        )
    }

    func refresh() async -> NativeDebugSessionState {
        guard isSessionActive else { return state }
        let shouldContinue = state.status == .running
        let fallbackStatus: NativeDebugStatus = shouldContinue ? .running : .paused
        let commands = (shouldContinue ? ["process continue"] : []) + runtimeInspectionCommands()
        return await execute(
            commands: commands,
            lastCommand: "refresh",
            fallbackStatus: fallbackStatus
        )
    }

    func stopSession() async -> NativeDebugSessionState {
        await closePersistentSession()
        state = makeBaseState(status: .stopped, command: "stop")
        state.callStack = []
        state.watchVariables = []
        state.updatedAt = Date()
        return state
    }

    func makeBaseState(status: NativeDebugStatus, command: String?) -> NativeDebugSessionState {
        NativeDebugSessionState(
            status: status,
            adapter: name,
            targetPath: targetPath,
            breakpointsCount: activeBreakpoints.count,
            callStack: state.callStack,
            watchVariables: state.watchVariables,
            lastCommand: command,
            lastError: nil,
            updatedAt: Date()
        )
    }
}
