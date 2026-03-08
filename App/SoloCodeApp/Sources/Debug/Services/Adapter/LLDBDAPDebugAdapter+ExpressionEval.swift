import Foundation

// MARK: - Expression Evaluation

extension LLDBDAPDebugAdapter {
    /// Valuta un'espressione nel contesto corrente del frame.
    /// Usa `expression -- <expr>` per valutazione sicura.
    func evaluateExpression(_ expression: String) async -> ExpressionResult {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(expression: expression, error: "Espressione vuota.")
        }
        guard isSessionActive else {
            return .failure(expression: expression, error: "Nessuna sessione debug attiva.")
        }

        let escaped = trimmed.replacingOccurrences(of: "\"", with: "\\\"")
        let command = "expression -- \(escaped)"

        switch engine {
        case .persistent:
            return await evaluatePersistent(command: command, expression: trimmed)
        case .batch:
            return await evaluateBatch(command: command, expression: trimmed)
        }
    }

    private func evaluatePersistent(command: String, expression: String) async -> ExpressionResult {
        guard let session = persistentSession else {
            return .failure(expression: expression, error: "Sessione LLDB non inizializzata.")
        }

        do {
            let output = try await session.send(commands: [command])
            return LLDBDAPDebugAdapterSupport.parseExpressionResult(
                from: output,
                expression: expression
            )
        } catch {
            return .failure(expression: expression, error: error.localizedDescription)
        }
    }

    private func evaluateBatch(command: String, expression: String) async -> ExpressionResult {
        guard let targetPath else {
            return .failure(expression: expression, error: "Nessun target configurato.")
        }
        guard case .batch(let runBatch) = engine else {
            return .failure(expression: expression, error: "Engine batch non disponibile.")
        }

        let commands = buildBatchCommands(targetPath: targetPath, actionCommand: nil) + [command]
        let result = await runBatch(commands)
        guard result.exitCode == 0 else {
            return .failure(
                expression: expression,
                error: result.output.isEmpty ? "Valutazione fallita." : result.output
            )
        }
        return LLDBDAPDebugAdapterSupport.parseExpressionResult(
            from: result.output,
            expression: expression
        )
    }

    /// Imposta un breakpoint con modificatori avanzati.
    func setEnhancedBreakpoint(
        filePath: String,
        line: Int,
        condition: String?,
        modifier: BreakpointModifier
    ) async -> NativeDebugSessionState {
        guard isSessionActive else { return state }

        let commands = LLDBDAPDebugAdapterSupport.makeEnhancedBreakpointCommand(
            filePath: filePath,
            line: line,
            condition: condition,
            modifier: modifier
        ) + runtimeInspectionCommands()

        return await execute(
            commands: commands,
            lastCommand: "enhanced_breakpoint_set",
            fallbackStatus: state.status
        )
    }
}
