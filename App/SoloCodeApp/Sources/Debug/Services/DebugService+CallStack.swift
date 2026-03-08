import Foundation

// MARK: - Call Stack Navigation

extension DebugService {
    /// Seleziona un frame specifico nello stack trace.
    /// Il frame diventa il contesto corrente per ispezione variabili e valutazione espressioni.
    func selectFrame(index: Int) async -> FrameSelectionResult {
        guard state.status == .paused else { return .empty }

        if let extended = adapter as? LLDBDAPDebugAdapter {
            return await extended.selectFrame(index: index)
        }
        return .empty
    }

    /// Naviga al frame corrispondente a un NativeCallStackFrame specifico.
    /// Trova l'indice del frame nel callStack e lo seleziona.
    func navigateToFrame(_ frame: NativeCallStackFrame) async -> FrameSelectionResult {
        guard let index = state.callStack.firstIndex(where: { $0.id == frame.id }) else {
            return .empty
        }
        return await selectFrame(index: index)
    }

    /// Restituisce il frame correntemente selezionato (frame #0 se nessuna selezione esplicita).
    func currentFrameLocals() async -> [NativeVariable] {
        guard state.status == .paused else { return [] }

        if let extended = adapter as? LLDBDAPDebugAdapter {
            return await extended.inspectLocals()
        }
        return []
    }
}
