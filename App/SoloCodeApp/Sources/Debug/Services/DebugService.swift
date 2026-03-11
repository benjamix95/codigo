import Foundation

actor DebugService {
    let adapter: NativeDebugAdapter
    let configuration: DebugServiceConfiguration
    private let recovery: DebugAdapterRecovery?
    var state: NativeDebugSessionState = .idle

    init(
        adapter: NativeDebugAdapter? = nil,
        configuration: DebugServiceConfiguration = .load(),
        recovery: DebugAdapterRecovery? = nil
    ) {
        self.configuration = configuration
        if let adapter {
            self.adapter = adapter
            self.recovery = recovery
        } else if configuration.nativeDebuggerEnabled {
            let liveAdapter = LLDBDAPDebugAdapter()
            self.adapter = liveAdapter
            self.recovery = recovery ?? DebugAdapterRecovery(
                adapter: liveAdapter,
                adapterFactory: { LLDBDAPDebugAdapter() }
            )
        } else {
            self.adapter = DisabledNativeDebugAdapter(
                reason: configuration.disabledReason
                    ?? "Native debug disabilitato da configurazione."
            )
            self.recovery = nil
        }
    }

    func startSession(
        targetPath: String,
        arguments: [String],
        breakpoints: [DebugBreakpoint],
        watchExpressions: [String]
    ) async -> NativeDebugSessionState {
        state = await performSessionOperation { adapter in
            await adapter.startSession(
                targetPath: targetPath,
                arguments: arguments,
                breakpoints: breakpoints,
                watchExpressions: watchExpressions
            )
        }
        return state
    }

    func stopSession() async -> NativeDebugSessionState {
        state = await performSessionOperation { adapter in
            await adapter.stopSession()
        }
        return state
    }

    func syncBreakpoints(_ breakpoints: [DebugBreakpoint]) async -> NativeDebugSessionState {
        state = await performSessionOperation { adapter in
            await adapter.syncBreakpoints(breakpoints)
        }
        return state
    }

    func syncWatches(_ expressions: [String]) async -> NativeDebugSessionState {
        state = await performSessionOperation { adapter in
            await adapter.syncWatches(expressions)
        }
        return state
    }

    func stepIn() async -> NativeDebugSessionState {
        state = await performSessionOperation { adapter in
            await adapter.step(command: "thread step-in")
        }
        return state
    }

    func stepOut() async -> NativeDebugSessionState {
        state = await performSessionOperation { adapter in
            await adapter.step(command: "thread step-out")
        }
        return state
    }

    func stepOver() async -> NativeDebugSessionState {
        state = await performSessionOperation { adapter in
            await adapter.step(command: "thread step-over")
        }
        return state
    }

    func refresh() async -> NativeDebugSessionState {
        state = await performSessionOperation { adapter in
            await adapter.refresh()
        }
        return state
    }

    func snapshot() -> NativeDebugSessionState {
        state
    }

    func serviceConfiguration() -> DebugServiceConfiguration {
        configuration
    }

    func recoveryStatus() async -> RecoveryStatus? {
        guard let recovery else { return nil }
        return await recovery.recoveryStatus()
    }

    private func performSessionOperation(
        _ operation: @escaping (NativeDebugAdapter) async -> NativeDebugSessionState
    ) async -> NativeDebugSessionState {
        if let recovery {
            return await recovery.executeSessionOp(operation)
        }
        return await operation(adapter)
    }
}
