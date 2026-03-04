import Foundation

// MARK: - Extended Debug Store Integration

extension DebugStore {
    /// Seleziona un frame nello stack trace e aggiorna le variabili locali.
    func selectNativeFrame(index: Int) {
        guard ensureNativeDebugEnabledForUI() else { return }

        Task { [weak self] in
            guard let self else { return }
            let result = await self.nativeDebugService.selectFrame(index: index)
            await MainActor.run {
                self.selectedFrameResult = result
            }
        }
    }

    /// Naviga a un frame specifico del call stack.
    func navigateToNativeFrame(_ frame: NativeCallStackFrame) {
        guard ensureNativeDebugEnabledForUI() else { return }

        Task { [weak self] in
            guard let self else { return }
            let result = await self.nativeDebugService.navigateToFrame(frame)
            await MainActor.run {
                self.selectedFrameResult = result
            }
        }
    }

    /// Ispeziona le variabili locali del frame corrente.
    func inspectNativeLocals() {
        guard ensureNativeDebugEnabledForUI() else { return }

        Task { [weak self] in
            guard let self else { return }
            let locals = await self.nativeDebugService.inspectLocals()
            await MainActor.run {
                self.localVariables = locals
            }
        }
    }

    /// Ispeziona le variabili globali.
    func inspectNativeGlobals() {
        guard ensureNativeDebugEnabledForUI() else { return }

        Task { [weak self] in
            guard let self else { return }
            let globals = await self.nativeDebugService.inspectGlobals()
            await MainActor.run {
                self.globalVariables = globals
            }
        }
    }

    /// Ispezione completa: locali + argomenti + globali.
    func inspectAllNativeVariables() {
        guard ensureNativeDebugEnabledForUI() else { return }

        Task { [weak self] in
            guard let self else { return }
            let all = await self.nativeDebugService.inspectAllVariables()
            await MainActor.run {
                self.localVariables = all.filter { $0.scope == .local }
                self.globalVariables = all.filter { $0.scope == .global }
                self.argumentVariables = all.filter { $0.scope == .argument }
            }
        }
    }

    /// Valuta un'espressione nel contesto corrente.
    func evaluateNativeExpression(_ expression: String) {
        guard ensureNativeDebugEnabledForUI() else { return }

        Task { [weak self] in
            guard let self else { return }
            let result = await self.nativeDebugService.evaluateExpression(expression)
            await MainActor.run {
                self.lastExpressionResult = result
                if result.success {
                    self.expressionHistory.append(result)
                }
            }
        }
    }

    /// Imposta un breakpoint con modificatori avanzati.
    func setEnhancedNativeBreakpoint(
        filePath: String,
        line: Int,
        condition: String? = nil,
        modifier: BreakpointModifier = .none
    ) {
        guard ensureNativeDebugEnabledForUI() else { return }

        performNativeServiceUpdate { service in
            await service.setEnhancedBreakpoint(
                filePath: filePath,
                line: line,
                condition: condition,
                modifier: modifier
            )
        }
    }

    /// Imposta un breakpoint one-shot.
    func setOneShotNativeBreakpoint(filePath: String, line: Int) {
        setEnhancedNativeBreakpoint(
            filePath: filePath,
            line: line,
            modifier: BreakpointModifier(isOneShot: true)
        )
    }

    /// Imposta un log breakpoint.
    func setLogNativeBreakpoint(filePath: String, line: Int, message: String) {
        setEnhancedNativeBreakpoint(
            filePath: filePath,
            line: line,
            modifier: BreakpointModifier(logMessage: message, isAutoResume: true)
        )
    }

    // MARK: - Private helpers ripetuti per accesso

    @discardableResult
    private func ensureNativeDebugEnabledForUI() -> Bool {
        isNativeDebugEnabled
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
