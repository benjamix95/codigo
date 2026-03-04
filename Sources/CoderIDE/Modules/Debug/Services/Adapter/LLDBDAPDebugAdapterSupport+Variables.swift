import Foundation

// MARK: - Variable Parsing Helpers

extension LLDBDAPDebugAdapterSupport {
    /// Parsa l'output di `frame variable` in una lista di NativeVariable.
    /// Formato tipico LLDB: `(Type) name = value`
    static func parseFrameVariables(from text: String, scope: NativeVariable.VariableScope = .local) -> [NativeVariable] {
        let lines = text.components(separatedBy: .newlines)
        var variables: [NativeVariable] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("(lldb)"),
                  !trimmed.hasPrefix("Global variables"),
                  !trimmed.hasPrefix("No variables"),
                  !trimmed.hasPrefix("error:") else { continue }

            if let variable = parseSingleVariable(from: trimmed, scope: scope) {
                variables.append(variable)
            }
        }
        return variables
    }

    /// Parsa una singola riga di variabile LLDB.
    /// Formato: `(Type) name = value` oppure `name = value`
    static func parseSingleVariable(
        from line: String,
        scope: NativeVariable.VariableScope
    ) -> NativeVariable? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pattern: (Type) name = value
        let typePattern = #"^\(([^)]+)\)\s+(\S+)\s*=\s*(.+)$"#
        if let match = trimmed.range(of: typePattern, options: .regularExpression) {
            return parseTypedVariable(from: trimmed, match: match, scope: scope)
        }

        // Fallback: name = value (senza tipo esplicito)
        let simplePattern = #"^(\S+)\s*=\s*(.+)$"#
        if let match = trimmed.range(of: simplePattern, options: .regularExpression) {
            return parseUntypedVariable(from: trimmed, match: match, scope: scope)
        }

        return nil
    }

    private static func parseTypedVariable(
        from text: String,
        match: Range<String.Index>,
        scope: NativeVariable.VariableScope
    ) -> NativeVariable? {
        let regex = try? NSRegularExpression(pattern: #"^\(([^)]+)\)\s+(\S+)\s*=\s*(.+)$"#)
        let nsText = text as NSString
        guard let result = regex?.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              result.numberOfRanges == 4 else { return nil }

        let type = nsText.substring(with: result.range(at: 1))
        let name = nsText.substring(with: result.range(at: 2))
        let value = nsText.substring(with: result.range(at: 3))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return NativeVariable(name: name, type: type, value: value, scope: scope)
    }

    private static func parseUntypedVariable(
        from text: String,
        match: Range<String.Index>,
        scope: NativeVariable.VariableScope
    ) -> NativeVariable? {
        let regex = try? NSRegularExpression(pattern: #"^(\S+)\s*=\s*(.+)$"#)
        let nsText = text as NSString
        guard let result = regex?.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              result.numberOfRanges == 3 else { return nil }

        let name = nsText.substring(with: result.range(at: 1))
        let value = nsText.substring(with: result.range(at: 2))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return NativeVariable(name: name, type: "unknown", value: value, scope: scope)
    }

    /// Parsa il risultato di una valutazione espressione LLDB.
    /// Formato: `(Type) $N = value` oppure `error: ...`
    static func parseExpressionResult(from text: String, expression: String) -> ExpressionResult {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("(lldb)") }

        if let errorLine = lines.first(where: { $0.hasPrefix("error:") }) {
            let errorMsg = String(errorLine.dropFirst("error:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(expression: expression, error: errorMsg)
        }

        // Pattern: (Type) $N = value
        let resultPattern = #"^\(([^)]+)\)\s+\$\d+\s*=\s*(.+)$"#
        for line in lines {
            let nsLine = line as NSString
            guard let regex = try? NSRegularExpression(pattern: resultPattern),
                  let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
                  match.numberOfRanges == 3 else { continue }

            let type = nsLine.substring(with: match.range(at: 1))
            let value = nsLine.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(expression: expression, result: value, type: type)
        }

        // Fallback: prima riga non vuota come risultato
        if let firstResult = lines.first {
            return .success(expression: expression, result: firstResult)
        }

        return .failure(expression: expression, error: "Nessun risultato ottenuto.")
    }

    /// Parsa l'output di `frame select N` per estrarre info del frame selezionato.
    static func parseFrameSelection(from text: String, requestedIndex: Int) -> FrameSelectionResult {
        let pattern = #"frame #(\d+): .*`([^`]+)`.* at ([^:]+):(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return FrameSelectionResult(
                frameIndex: requestedIndex, function: "", filePath: "", line: 0, localVariables: []
            )
        }

        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges == 5 else {
            return FrameSelectionResult(
                frameIndex: requestedIndex, function: "", filePath: "", line: 0, localVariables: []
            )
        }

        let function = nsText.substring(with: match.range(at: 2))
        let filePath = nsText.substring(with: match.range(at: 3))
        let line = Int(nsText.substring(with: match.range(at: 4))) ?? 0

        return FrameSelectionResult(
            frameIndex: requestedIndex,
            function: function,
            filePath: filePath,
            line: line,
            localVariables: []
        )
    }

    /// Genera il comando LLDB per un breakpoint con modificatori avanzati.
    static func makeEnhancedBreakpointCommand(
        filePath: String,
        line: Int,
        condition: String?,
        modifier: BreakpointModifier
    ) -> [String] {
        let escapedPath = filePath.replacingOccurrences(of: "\"", with: "\\\"")
        var command = "breakpoint set --file \"\(escapedPath)\" --line \(line)"

        if let condition, !condition.isEmpty {
            let escapedCondition = condition.replacingOccurrences(of: "\"", with: "\\\"")
            command += " --condition \"\(escapedCondition)\""
        }
        if modifier.isOneShot {
            command += " -o"
        }
        if let ignoreCount = modifier.ignoreCount, ignoreCount > 0 {
            command += " --ignore-count \(ignoreCount)"
        }
        if modifier.isAutoResume {
            command += " --auto-continue true"
        }

        var commands = [command]

        // Breakpoint log message: richiede un breakpoint command
        if let logMessage = modifier.logMessage, !logMessage.isEmpty {
            let escaped = logMessage.replacingOccurrences(of: "\"", with: "\\\"")
            commands.append("breakpoint command add -o \"script print('\(escaped)')\"")
        }

        return commands
    }
}
