import Foundation

// MARK: - Expression Evaluation

extension DebugService {
    /// Valuta un'espressione nel contesto corrente del debugger.
    /// Funziona solo quando il debugger è in pausa (breakpoint o step).
    func evaluateExpression(_ expression: String) async -> ExpressionResult {
        guard state.status == .paused else {
            return .failure(
                expression: expression,
                error: "La valutazione è possibile solo in stato paused."
            )
        }

        if let lldbAdapter = adapter as? LLDBDAPDebugAdapter {
            return await lldbAdapter.evaluateExpression(expression)
        }
        return .failure(
            expression: expression,
            error: "Adapter non supporta expression evaluation."
        )
    }

    /// Valuta più espressioni in sequenza e restituisce i risultati.
    func evaluateExpressions(_ expressions: [String]) async -> [ExpressionResult] {
        guard state.status == .paused else {
            return expressions.map {
                .failure(expression: $0, error: "Debugger non in pausa.")
            }
        }

        var results: [ExpressionResult] = []
        for expression in expressions {
            let result = await evaluateExpression(expression)
            results.append(result)
        }
        return results
    }
}
