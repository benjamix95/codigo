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
    private static let liveBatchRunner: LLDBBatchRunner = { commands in
        await LLDBDAPDebugAdapterSupport.defaultBatchRunner(commands: commands)
    }

    nonisolated let name = "lldb-cli"
    private let runBatch: LLDBBatchRunner
    private var state: NativeDebugSessionState = .idle
    private var activeBreakpoints: [DebugBreakpoint] = []
    private var watchExpressions: [String] = []
    private var targetPath: String?
    private var arguments: [String] = []
    private var isSessionActive = false

    init(runBatch: @escaping LLDBBatchRunner = LLDBDAPDebugAdapter.liveBatchRunner) {
        self.runBatch = runBatch
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

        guard FileManager.default.isExecutableFile(atPath: targetPath) else {
            state.status = .error
            state.lastError = "Target non eseguibile: \(targetPath)"
            state.updatedAt = Date()
            return state
        }

        let version = await runBatch(["version"])
        if version.exitCode != 0 {
            state.status = .error
            state.lastError = version.output.isEmpty ? "LLDB non disponibile" : version.output
            state.updatedAt = Date()
            return state
        }

        isSessionActive = true
        return await executeDebugCycle(
            actionCommand: nil,
            lastCommand: "process launch --stop-at-entry",
            fallbackStatus: .paused
        )
    }

    func syncBreakpoints(_ breakpoints: [DebugBreakpoint]) async -> NativeDebugSessionState {
        activeBreakpoints = breakpoints.filter(\.isActive)
        state = makeBaseState(status: state.status, command: "sync_breakpoints")
        state.breakpointsCount = activeBreakpoints.count
        state.updatedAt = Date()
        return state
    }

    func syncWatches(_ expressions: [String]) async -> NativeDebugSessionState {
        watchExpressions = expressions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        state = makeBaseState(status: state.status, command: "sync_watches")
        state.updatedAt = Date()
        guard isSessionActive else { return state }
        return await refresh()
    }

    func step(command: String) async -> NativeDebugSessionState {
        guard isSessionActive else { return state }
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return state }
        let executionCommand = LLDBDAPDebugAdapterSupport.normalizeExecutionCommand(normalized)
        let fallbackStatus: NativeDebugStatus = LLDBDAPDebugAdapterSupport.isContinueLikeCommand(executionCommand) ? .running : .paused
        state = makeBaseState(status: fallbackStatus, command: executionCommand)
        return await executeDebugCycle(
            actionCommand: executionCommand,
            lastCommand: executionCommand,
            fallbackStatus: fallbackStatus
        )
    }

    func refresh() async -> NativeDebugSessionState {
        guard isSessionActive else { return state }
        let actionCommand = state.status == .running ? "process continue" : nil
        let fallbackStatus: NativeDebugStatus = actionCommand == nil ? .paused : .running
        return await executeDebugCycle(
            actionCommand: actionCommand,
            lastCommand: "refresh",
            fallbackStatus: fallbackStatus
        )
    }

    func stopSession() async -> NativeDebugSessionState {
        isSessionActive = false
        state = makeBaseState(status: .stopped, command: "stop")
        state.callStack = []
        state.watchVariables = []
        state.updatedAt = Date()
        return state
    }

    private func makeBaseState(status: NativeDebugStatus, command: String?) -> NativeDebugSessionState {
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

    private func executeDebugCycle(
        actionCommand: String?,
        lastCommand: String,
        fallbackStatus: NativeDebugStatus
    ) async -> NativeDebugSessionState {
        guard let targetPath else {
            isSessionActive = false
            state = .idle
            return state
        }

        let lldbCommands = buildLLDBCommands(targetPath: targetPath, actionCommand: actionCommand)
        let result = await runBatch(lldbCommands)
        let computedStatus = LLDBDAPDebugAdapterSupport.inferSessionStatus(
            from: result.output,
            exitCode: result.exitCode,
            fallback: fallbackStatus
        )

        state = makeBaseState(status: computedStatus, command: lastCommand)
        state.callStack = LLDBDAPDebugAdapterSupport.parseBacktrace(from: result.output)
        state.watchVariables = LLDBDAPDebugAdapterSupport.parseWatchValues(
            from: result.output,
            expressions: watchExpressions
        )
        state.lastError = result.exitCode == 0 ? nil : (result.output.isEmpty ? "Comando LLDB fallito" : result.output)
        state.updatedAt = Date()

        if computedStatus == .stopped || computedStatus == .error {
            isSessionActive = false
        }

        return state
    }

    private func buildLLDBCommands(targetPath: String, actionCommand: String?) -> [String] {
        var commands: [String] = ["target create \"\(targetPath)\""]
        if !arguments.isEmpty {
            let lldbArgs = arguments.map(LLDBDAPDebugAdapterSupport.escapeLLDBString).joined(separator: " ")
            commands.append("settings set -- target.run-args \(lldbArgs)")
        }
        for bp in activeBreakpoints {
            let filePath = bp.filePath.replacingOccurrences(of: "\"", with: "\\\"")
            var cmd = "breakpoint set --file \"\(filePath)\" --line \(bp.line)"
            if let condition = bp.condition, !condition.isEmpty {
                let escapedCondition = condition.replacingOccurrences(of: "\"", with: "\\\"")
                cmd += " --condition \"\(escapedCondition)\""
            }
            commands.append(cmd)
        }
        commands.append("process launch --stop-at-entry")
        if let actionCommand, !actionCommand.isEmpty {
            commands.append(actionCommand)
        }
        commands.append("process status")
        commands.append("thread backtrace")
        for watch in watchExpressions {
            let escaped = watch.replacingOccurrences(of: "\"", with: "\\\"")
            commands.append("expression -- \(escaped)")
        }
        return commands
    }
}
