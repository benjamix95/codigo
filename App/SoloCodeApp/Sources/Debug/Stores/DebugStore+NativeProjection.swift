import Foundation

extension DebugStore {
    func applyNativePipelineProjection(
        state: NativeDebugSessionState,
        breakpoints: [DebugBreakpoint],
        arguments: [String],
        watchExpressions: [String]
    ) {
        self.breakpoints = breakpoints
        self.nativeSession = state

        if let targetPath = state.targetPath,
           !targetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nativeTargetPathInput = targetPath
        }

        nativeArgumentsInput = arguments.joined(separator: ", ")
        nativeWatchExpressionsInput = watchExpressions.joined(separator: ", ")
    }
}
