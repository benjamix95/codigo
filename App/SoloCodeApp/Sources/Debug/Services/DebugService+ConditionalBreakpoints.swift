import Foundation

// MARK: - Enhanced Conditional Breakpoints

extension DebugService {
    /// Imposta un breakpoint con modificatori avanzati (hit count, log, one-shot).
    func setEnhancedBreakpoint(
        filePath: String,
        line: Int,
        condition: String? = nil,
        modifier: BreakpointModifier = .none
    ) async -> NativeDebugSessionState {
        if let lldbAdapter = adapter as? LLDBDAPDebugAdapter {
            state = await lldbAdapter.setEnhancedBreakpoint(
                filePath: filePath,
                line: line,
                condition: condition,
                modifier: modifier
            )
            return state
        }
        return state
    }

    /// Imposta un breakpoint one-shot (si elimina automaticamente dopo il primo hit).
    func setOneShotBreakpoint(
        filePath: String,
        line: Int,
        condition: String? = nil
    ) async -> NativeDebugSessionState {
        await setEnhancedBreakpoint(
            filePath: filePath,
            line: line,
            condition: condition,
            modifier: BreakpointModifier(isOneShot: true)
        )
    }

    /// Imposta un log breakpoint (non ferma l'esecuzione, logga il messaggio).
    func setLogBreakpoint(
        filePath: String,
        line: Int,
        message: String,
        condition: String? = nil
    ) async -> NativeDebugSessionState {
        await setEnhancedBreakpoint(
            filePath: filePath,
            line: line,
            condition: condition,
            modifier: BreakpointModifier(logMessage: message, isAutoResume: true)
        )
    }

    /// Imposta un breakpoint con hit count (ignora i primi N hit).
    func setHitCountBreakpoint(
        filePath: String,
        line: Int,
        ignoreCount: Int,
        condition: String? = nil
    ) async -> NativeDebugSessionState {
        await setEnhancedBreakpoint(
            filePath: filePath,
            line: line,
            condition: condition,
            modifier: BreakpointModifier(ignoreCount: ignoreCount)
        )
    }
}
