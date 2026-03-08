import Foundation

// MARK: - Extended Debug Adapter Protocol

/// Protocollo esteso per capability avanzate del debug adapter.
/// Aggiunge frame navigation, variable inspection, expression evaluation e enhanced breakpoints.
/// Default implementations restituiscono valori vuoti per adapter disabilitati.
protocol ExtendedNativeDebugAdapter: NativeDebugAdapter {
    /// Seleziona un frame specifico nello stack trace (`frame select N`).
    func selectFrame(index: Int) async -> FrameSelectionResult

    /// Ispeziona le variabili locali del frame corrente (`frame variable`).
    func inspectLocals() async -> [NativeVariable]

    /// Ispeziona le variabili globali/statiche (`target variable`).
    func inspectGlobals() async -> [NativeVariable]

    /// Valuta un'espressione nel contesto corrente (`expression -- <expr>`).
    func evaluateExpression(_ expression: String) async -> ExpressionResult

    /// Imposta un breakpoint con modificatori avanzati (hit count, log, one-shot).
    func setEnhancedBreakpoint(
        filePath: String,
        line: Int,
        condition: String?,
        modifier: BreakpointModifier
    ) async -> NativeDebugSessionState
}

// MARK: - Default Implementations (per adapter disabilitati)

extension ExtendedNativeDebugAdapter {
    func selectFrame(index: Int) async -> FrameSelectionResult {
        .empty
    }

    func inspectLocals() async -> [NativeVariable] {
        []
    }

    func inspectGlobals() async -> [NativeVariable] {
        []
    }

    func evaluateExpression(_ expression: String) async -> ExpressionResult {
        .failure(expression: expression, error: "Adapter non supporta expression evaluation.")
    }

    func setEnhancedBreakpoint(
        filePath: String,
        line: Int,
        condition: String?,
        modifier: BreakpointModifier
    ) async -> NativeDebugSessionState {
        .idle
    }
}
