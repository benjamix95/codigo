import Foundation

extension LLDBDAPDebugAdapter {
    func execute(
        commands: [String],
        lastCommand: String,
        fallbackStatus: NativeDebugStatus
    ) async -> NativeDebugSessionState {
        switch engine {
        case .persistent:
            return await executePersistent(
                commands: commands,
                lastCommand: lastCommand,
                fallbackStatus: fallbackStatus
            )
        case .batch:
            let actionCommand = commands.first(where: {
                LLDBDAPDebugAdapterSupport.isExecutionCommand($0)
            })
            return await executeBatchCycle(
                actionCommand: actionCommand,
                lastCommand: lastCommand,
                fallbackStatus: fallbackStatus
            )
        }
    }

    func executePersistent(
        commands: [String],
        lastCommand: String,
        fallbackStatus: NativeDebugStatus
    ) async -> NativeDebugSessionState {
        guard let session = persistentSession else {
            isSessionActive = false
            state.status = .error
            state.lastError = "Sessione LLDB non inizializzata."
            state.updatedAt = Date()
            return state
        }

        do {
            let output = try await session.send(commands: commands)
            applyExecutionOutput(output, exitCode: 0, lastCommand: lastCommand, fallbackStatus: fallbackStatus)
            if state.status == .stopped || state.status == .error {
                isSessionActive = false
            }
            return state
        } catch {
            isSessionActive = false
            state = makeBaseState(status: .error, command: lastCommand)
            state.lastError = error.localizedDescription
            state.updatedAt = Date()
            await closePersistentSession()
            return state
        }
    }

    func executeBatchCycle(
        actionCommand: String?,
        lastCommand: String,
        fallbackStatus: NativeDebugStatus
    ) async -> NativeDebugSessionState {
        guard let targetPath else {
            isSessionActive = false
            state = .idle
            return state
        }

        guard case .batch(let runBatch) = engine else {
            state = makeBaseState(status: .error, command: lastCommand)
            state.lastError = "Engine batch non disponibile."
            state.updatedAt = Date()
            return state
        }

        let lldbCommands = buildBatchCommands(targetPath: targetPath, actionCommand: actionCommand)
        let result = await runBatch(lldbCommands)
        applyExecutionOutput(
            result.output,
            exitCode: result.exitCode,
            lastCommand: lastCommand,
            fallbackStatus: fallbackStatus
        )
        if state.status == .stopped || state.status == .error {
            isSessionActive = false
        }
        return state
    }

    func buildBatchCommands(targetPath: String, actionCommand: String?) -> [String] {
        var commands: [String] = ["target create \"\(targetPath)\""]
        if !arguments.isEmpty {
            let lldbArgs = arguments.map(LLDBDAPDebugAdapterSupport.escapeLLDBString).joined(separator: " ")
            commands.append("settings set -- target.run-args \(lldbArgs)")
        }
        commands.append(contentsOf: breakpointCommands())
        commands.append("process launch --stop-at-entry")
        if let actionCommand, !actionCommand.isEmpty {
            commands.append(actionCommand)
        }
        commands.append(contentsOf: runtimeInspectionCommands())
        return commands
    }

    func buildBootstrapCommands(targetPath: String) -> [String] {
        var commands: [String] = ["target create \"\(targetPath)\""]
        if !arguments.isEmpty {
            let lldbArgs = arguments.map(LLDBDAPDebugAdapterSupport.escapeLLDBString).joined(separator: " ")
            commands.append("settings set -- target.run-args \(lldbArgs)")
        }
        commands.append(contentsOf: breakpointCommands())
        commands.append("process launch --stop-at-entry")
        return commands
    }

    func breakpointCommands() -> [String] {
        activeBreakpoints.map { breakpoint in
            LLDBDAPDebugAdapterSupport.makeBreakpointCommand(from: breakpoint)
        }
    }

    func runtimeInspectionCommands() -> [String] {
        var commands = ["process status", "thread backtrace"]
        for watch in watchExpressions where !watch.isEmpty {
            let escaped = watch.replacingOccurrences(of: "\"", with: "\\\"")
            commands.append("expression -- \(escaped)")
        }
        return commands
    }

    func applyExecutionOutput(
        _ output: String,
        exitCode: Int32,
        lastCommand: String,
        fallbackStatus: NativeDebugStatus
    ) {
        let computedStatus = LLDBDAPDebugAdapterSupport.inferSessionStatus(
            from: output,
            exitCode: exitCode,
            fallback: fallbackStatus
        )
        state = makeBaseState(status: computedStatus, command: lastCommand)
        state.callStack = LLDBDAPDebugAdapterSupport.parseBacktrace(from: output)
        state.watchVariables = LLDBDAPDebugAdapterSupport.parseWatchValues(
            from: output,
            expressions: watchExpressions
        )
        state.lastError = exitCode == 0 ? nil : (output.isEmpty ? "Comando LLDB fallito" : output)
        state.updatedAt = Date()
    }

    func closePersistentSession() async {
        isSessionActive = false
        guard let session = persistentSession else { return }
        await session.close()
        persistentSession = nil
    }
}
