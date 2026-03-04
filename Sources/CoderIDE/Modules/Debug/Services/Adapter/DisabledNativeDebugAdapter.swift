import Foundation

actor DisabledNativeDebugAdapter: NativeDebugAdapter {
    nonisolated let name = "native-debug-disabled"
    private let reason: String

    init(reason: String) {
        self.reason = reason
    }

    func startSession(
        targetPath: String,
        arguments: [String],
        breakpoints: [DebugBreakpoint],
        watchExpressions: [String]
    ) async -> NativeDebugSessionState {
        makeDisabledState(targetPath: targetPath, breakpointsCount: breakpoints.filter(\.isActive).count)
    }

    func syncBreakpoints(_ breakpoints: [DebugBreakpoint]) async -> NativeDebugSessionState {
        makeDisabledState(targetPath: nil, breakpointsCount: breakpoints.filter(\.isActive).count)
    }

    func syncWatches(_ expressions: [String]) async -> NativeDebugSessionState {
        makeDisabledState(targetPath: nil, breakpointsCount: 0)
    }

    func step(command: String) async -> NativeDebugSessionState {
        makeDisabledState(targetPath: nil, breakpointsCount: 0)
    }

    func refresh() async -> NativeDebugSessionState {
        makeDisabledState(targetPath: nil, breakpointsCount: 0)
    }

    func stopSession() async -> NativeDebugSessionState {
        makeDisabledState(targetPath: nil, breakpointsCount: 0)
    }

    private func makeDisabledState(targetPath: String?, breakpointsCount: Int) -> NativeDebugSessionState {
        NativeDebugSessionState(
            status: .idle,
            adapter: name,
            targetPath: targetPath,
            breakpointsCount: breakpointsCount,
            callStack: [],
            watchVariables: [],
            lastCommand: nil,
            lastError: reason,
            updatedAt: Date()
        )
    }
}
