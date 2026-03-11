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
        guard ensureNativeDebugEnabledForUI() else { return }

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

        performNativeCoordinatorUpdate(
            .start(
                targetPath: resolvedTarget,
                arguments: resolvedArguments,
                breakpoints: self.breakpoints,
                watchExpressions: self.parsedNativeWatchExpressions
            )
        )
    }

    func stopNativeDebugSession() {
        guard ensureNativeDebugEnabledForUI() else { return }
        performNativeCoordinatorUpdate(.stop)
    }

    func refreshNativeDebugSession() {
        guard ensureNativeDebugEnabledForUI() else { return }
        performNativeCoordinatorUpdate(.refresh)
    }

    func syncNativeBreakpoints(force: Bool = false) {
        syncNativeConfiguration(force: force)
    }

    func syncNativeWatches(force: Bool = false) {
        syncNativeConfiguration(force: force)
    }

    func syncNativeConfiguration(force: Bool = false) {
        guard ensureNativeDebugEnabledForUI() else { return }
        guard force || shouldAutoSyncNativeConfiguration else { return }
        Task { [weak self] in
            guard let self else { return }
            let breakpointState = await self.nativeDebugCoordinator.execute(.syncBreakpoints(self.breakpoints))
            let finalState = await self.nativeDebugCoordinator.execute(
                .syncWatches(self.parsedNativeWatchExpressions)
            )
            await MainActor.run {
                self.nativeSession = finalState.metrics.lastStage?.stage == .syncWatches
                    ? finalState
                    : breakpointState
            }
        }
    }

    func nativeStepIn() {
        guard ensureNativeDebugEnabledForUI() else { return }
        performNativeCoordinatorUpdate(.stepIn)
    }

    func nativeStepOut() {
        guard ensureNativeDebugEnabledForUI() else { return }
        performNativeCoordinatorUpdate(.stepOut)
    }

    func nativeStepOver() {
        guard ensureNativeDebugEnabledForUI() else { return }
        performNativeCoordinatorUpdate(.stepOver)
    }

    @discardableResult
    private func ensureNativeDebugEnabledForUI() -> Bool {
        guard isNativeDebugEnabled else {
            applyNativeFeatureDisabledState()
            return false
        }
        return true
    }

    private func applyNativeFeatureDisabledState() {
        nativeSession = NativeDebugSessionState(
            status: .idle,
            adapter: "native-debug-disabled",
            targetPath: resolvedNativeTargetPathInput,
            breakpointsCount: breakpoints.filter(\.isActive).count,
            callStack: [],
            watchVariables: [],
            lastCommand: nil,
            lastError: nativeDebugDisabledReason ?? "Native debug disabilitato.",
            updatedAt: Date()
        )
    }

    private func performNativeCoordinatorUpdate(_ command: DebugExecutionCommand) {
        Task { [weak self] in
            guard let self else { return }
            let state = await self.nativeDebugCoordinator.execute(command)
            await MainActor.run {
                self.nativeSession = state
            }
        }
    }
}
