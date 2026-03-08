import Foundation

// MARK: - Call Stack Navigation

extension LLDBDAPDebugAdapter {
    /// Seleziona un frame specifico nello stack trace e restituisce il contesto del frame.
    /// Invia `frame select N` + `frame variable` per ottenere le variabili locali del frame.
    func selectFrame(index: Int) async -> FrameSelectionResult {
        guard isSessionActive else { return .empty }

        let commands = [
            "frame select \(index)",
            "frame variable"
        ]

        switch engine {
        case .persistent:
            return await selectFramePersistent(index: index, commands: commands)
        case .batch:
            return await selectFrameBatch(index: index)
        }
    }

    private func selectFramePersistent(
        index: Int,
        commands: [String]
    ) async -> FrameSelectionResult {
        guard let session = persistentSession else { return .empty }

        do {
            let output = try await session.send(commands: commands)
            let frameResult = LLDBDAPDebugAdapterSupport.parseFrameSelection(
                from: output,
                requestedIndex: index
            )
            let locals = LLDBDAPDebugAdapterSupport.parseFrameVariables(
                from: output,
                scope: .local
            )
            return FrameSelectionResult(
                frameIndex: frameResult.frameIndex,
                function: frameResult.function,
                filePath: frameResult.filePath,
                line: frameResult.line,
                localVariables: locals
            )
        } catch {
            return .empty
        }
    }

    private func selectFrameBatch(index: Int) async -> FrameSelectionResult {
        guard let targetPath else { return .empty }
        guard case .batch(let runBatch) = engine else { return .empty }

        let commands = buildBatchCommands(targetPath: targetPath, actionCommand: "frame select \(index)")
            + ["frame variable"]
        let result = await runBatch(commands)
        let frameResult = LLDBDAPDebugAdapterSupport.parseFrameSelection(
            from: result.output,
            requestedIndex: index
        )
        let locals = LLDBDAPDebugAdapterSupport.parseFrameVariables(
            from: result.output,
            scope: .local
        )
        return FrameSelectionResult(
            frameIndex: frameResult.frameIndex,
            function: frameResult.function,
            filePath: frameResult.filePath,
            line: frameResult.line,
            localVariables: locals
        )
    }
}
