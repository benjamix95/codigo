import Foundation

actor DebugService {
    private let adapter: NativeDebugAdapter
    private let configuration: DebugServiceConfiguration
    private var state: NativeDebugSessionState = .idle

    init(
        adapter: NativeDebugAdapter? = nil,
        configuration: DebugServiceConfiguration = .load()
    ) {
        self.configuration = configuration
        if let adapter {
            self.adapter = adapter
        } else if configuration.nativeDebuggerEnabled {
            self.adapter = LLDBDAPDebugAdapter()
        } else {
            self.adapter = DisabledNativeDebugAdapter(
                reason: configuration.disabledReason
                    ?? "Native debug disabilitato da configurazione."
            )
        }
    }

    func startSession(
        targetPath: String,
        arguments: [String],
        breakpoints: [DebugBreakpoint],
        watchExpressions: [String]
    ) async -> NativeDebugSessionState {
        state = await adapter.startSession(
            targetPath: targetPath,
            arguments: arguments,
            breakpoints: breakpoints,
            watchExpressions: watchExpressions
        )
        return state
    }

    func stopSession() async -> NativeDebugSessionState {
        state = await adapter.stopSession()
        return state
    }

    func syncBreakpoints(_ breakpoints: [DebugBreakpoint]) async -> NativeDebugSessionState {
        state = await adapter.syncBreakpoints(breakpoints)
        return state
    }

    func syncWatches(_ expressions: [String]) async -> NativeDebugSessionState {
        state = await adapter.syncWatches(expressions)
        return state
    }

    func stepIn() async -> NativeDebugSessionState {
        state = await adapter.step(command: "thread step-in")
        return state
    }

    func stepOut() async -> NativeDebugSessionState {
        state = await adapter.step(command: "thread step-out")
        return state
    }

    func stepOver() async -> NativeDebugSessionState {
        state = await adapter.step(command: "thread step-over")
        return state
    }

    func refresh() async -> NativeDebugSessionState {
        state = await adapter.refresh()
        return state
    }

    func snapshot() -> NativeDebugSessionState {
        state
    }

    func serviceConfiguration() -> DebugServiceConfiguration {
        configuration
    }
}
