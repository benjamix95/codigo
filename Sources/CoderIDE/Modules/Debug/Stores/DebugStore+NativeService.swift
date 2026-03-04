import Foundation

extension DebugStore {
    var defaultNativeDebugTargetPath: String? {
        if let bundleExec = Bundle.main.executablePath, !bundleExec.isEmpty {
            return bundleExec
        }
        let arg0 = ProcessInfo.processInfo.arguments.first ?? ""
        return arg0.isEmpty ? nil : arg0
    }

    private var shouldAutoSyncNativeConfiguration: Bool {
        switch nativeSession.status {
        case .running, .paused:
            return true
        case .idle, .stopped, .error:
            return false
        }
    }

    func startNativeDebugSession(targetPath: String? = nil, arguments: [String]? = nil) {
        let targetOverride = targetPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTarget = (targetOverride?.isEmpty == false)
            ? targetOverride
            : resolvedNativeTargetPathInput

        guard let resolvedTarget else {
            nativeSession.status = .error
            nativeSession.lastError = "Target debug non disponibile."
            nativeSession.updatedAt = Date()
            return
        }

        let resolvedArguments = arguments ?? parsedNativeArguments
        nativeTargetPathInput = resolvedTarget
        nativeArgumentsInput = resolvedArguments.joined(separator: ", ")

        performNativeServiceUpdate { [breakpoints = self.breakpoints, watches = self.parsedNativeWatchExpressions] service in
            await service.startSession(
                targetPath: resolvedTarget,
                arguments: resolvedArguments,
                breakpoints: breakpoints,
                watchExpressions: watches
            )
        }
    }

    func stopNativeDebugSession() {
        performNativeServiceUpdate { service in
            await service.stopSession()
        }
    }

    func refreshNativeDebugSession() {
        performNativeServiceUpdate { service in
            await service.refresh()
        }
    }

    func syncNativeBreakpoints(force: Bool = false) {
        syncNativeConfiguration(force: force)
    }

    func syncNativeWatches(force: Bool = false) {
        syncNativeConfiguration(force: force)
    }

    func syncNativeConfiguration(force: Bool = false) {
        guard force || shouldAutoSyncNativeConfiguration else { return }
        performNativeServiceUpdate { [breakpoints = self.breakpoints, watches = self.parsedNativeWatchExpressions] service in
            _ = await service.syncBreakpoints(breakpoints)
            return await service.syncWatches(watches)
        }
    }

    func nativeStepIn() {
        performNativeServiceUpdate { service in
            await service.stepIn()
        }
    }

    func nativeStepOut() {
        performNativeServiceUpdate { service in
            await service.stepOut()
        }
    }

    func nativeStepOver() {
        performNativeServiceUpdate { service in
            await service.stepOver()
        }
    }

    private func performNativeServiceUpdate(
        _ operation: @escaping (DebugService) async -> NativeDebugSessionState
    ) {
        Task { [weak self] in
            guard let self else { return }
            let state = await operation(self.nativeDebugService)
            await MainActor.run {
                self.nativeSession = state
            }
        }
    }
}
