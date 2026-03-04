import Foundation

extension DebugStore {
    var resolvedNativeTargetPathInput: String? {
        let trimmed = nativeTargetPathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return defaultNativeDebugTargetPath
    }

    var parsedNativeArguments: [String] {
        parseNativeListInput(nativeArgumentsInput)
    }

    var parsedNativeWatchExpressions: [String] {
        parseNativeListInput(nativeWatchExpressionsInput)
    }

    func addBreakpointFromNativeInputs() {
        let filePath = nativeBreakpointFilePathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filePath.isEmpty else {
            setNativeValidationError("Percorso file breakpoint obbligatorio.")
            return
        }

        guard let line = Int(nativeBreakpointLineInput), line > 0 else {
            setNativeValidationError("Linea breakpoint non valida.")
            return
        }

        let condition = nativeBreakpointConditionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        addBreakpoint(
            filePath: filePath,
            line: line,
            condition: condition.isEmpty ? nil : condition
        )
        nativeBreakpointLineInput = ""
        nativeBreakpointConditionInput = ""
        nativeSession.lastError = nil
    }

    func applyNativeWatchExpressions() {
        syncNativeConfiguration(force: true)
    }

    func resetNativeInputs(clearTargetAndArguments: Bool = true) {
        if clearTargetAndArguments {
            nativeTargetPathInput = ""
            nativeArgumentsInput = ""
        }
        nativeWatchExpressionsInput = ""
        nativeBreakpointFilePathInput = ""
        nativeBreakpointLineInput = ""
        nativeBreakpointConditionInput = ""
    }

    func primeNativeTargetInputIfNeeded() {
        guard nativeTargetPathInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        if let defaultTarget = defaultNativeDebugTargetPath {
            nativeTargetPathInput = defaultTarget
        }
    }

    private func parseNativeListInput(_ value: String) -> [String] {
        value
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func setNativeValidationError(_ message: String) {
        nativeSession.status = .error
        nativeSession.lastError = message
        nativeSession.updatedAt = Date()
    }
}
