import Foundation

// MARK: - Variable Inspection

extension LLDBDAPDebugAdapter {
    /// Ispeziona le variabili locali del frame corrente tramite `frame variable`.
    func inspectLocals() async -> [NativeVariable] {
        guard isSessionActive else { return [] }

        let commands = ["frame variable"]
        return await executeVariableInspection(
            commands: commands,
            scope: .local
        )
    }

    /// Ispeziona le variabili globali/statiche tramite `target variable`.
    func inspectGlobals() async -> [NativeVariable] {
        guard isSessionActive else { return [] }

        let commands = ["target variable"]
        return await executeVariableInspection(
            commands: commands,
            scope: .global
        )
    }

    /// Ispeziona gli argomenti del frame corrente tramite `frame variable --no-locals`.
    func inspectArguments() async -> [NativeVariable] {
        guard isSessionActive else { return [] }

        let commands = ["frame variable --no-locals"]
        return await executeVariableInspection(
            commands: commands,
            scope: .argument
        )
    }

    /// Ispeziona i registri CPU tramite `register read`.
    func inspectRegisters() async -> [NativeVariable] {
        guard isSessionActive else { return [] }

        let commands = ["register read"]
        return await executeRegisterInspection(commands: commands)
    }

    // MARK: - Private Helpers

    private func executeVariableInspection(
        commands: [String],
        scope: NativeVariable.VariableScope
    ) async -> [NativeVariable] {
        switch engine {
        case .persistent:
            return await inspectPersistent(commands: commands, scope: scope)
        case .batch:
            return await inspectBatch(commands: commands, scope: scope)
        }
    }

    private func inspectPersistent(
        commands: [String],
        scope: NativeVariable.VariableScope
    ) async -> [NativeVariable] {
        guard let session = persistentSession else { return [] }

        do {
            let output = try await session.send(commands: commands)
            return LLDBDAPDebugAdapterSupport.parseFrameVariables(from: output, scope: scope)
        } catch {
            return []
        }
    }

    private func inspectBatch(
        commands: [String],
        scope: NativeVariable.VariableScope
    ) async -> [NativeVariable] {
        guard let targetPath else { return [] }
        guard case .batch(let runBatch) = engine else { return [] }

        let batchCommands = buildBatchCommands(targetPath: targetPath, actionCommand: nil) + commands
        let result = await runBatch(batchCommands)
        guard result.exitCode == 0 else { return [] }
        return LLDBDAPDebugAdapterSupport.parseFrameVariables(from: result.output, scope: scope)
    }

    private func executeRegisterInspection(commands: [String]) async -> [NativeVariable] {
        switch engine {
        case .persistent:
            guard let session = persistentSession else { return [] }
            do {
                let output = try await session.send(commands: commands)
                return parseRegisters(from: output)
            } catch {
                return []
            }
        case .batch:
            guard let targetPath else { return [] }
            guard case .batch(let runBatch) = engine else { return [] }
            let batchCommands = buildBatchCommands(targetPath: targetPath, actionCommand: nil) + commands
            let result = await runBatch(batchCommands)
            guard result.exitCode == 0 else { return [] }
            return parseRegisters(from: result.output)
        }
    }

    /// Parsa output di `register read`.
    /// Formato: `regname = 0xVALUE` o `regname = value`
    private func parseRegisters(from output: String) -> [NativeVariable] {
        let pattern = #"^\s*(\w+)\s*=\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return []
        }

        let nsOutput = output as NSString
        let matches = regex.matches(in: output, range: NSRange(location: 0, length: nsOutput.length))
        return matches.compactMap { match -> NativeVariable? in
            guard match.numberOfRanges == 3 else { return nil }
            let name = nsOutput.substring(with: match.range(at: 1))
            let value = nsOutput.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.hasPrefix("(lldb)") else { return nil }
            return NativeVariable(name: name, type: "register", value: value, scope: .register)
        }
    }
}
