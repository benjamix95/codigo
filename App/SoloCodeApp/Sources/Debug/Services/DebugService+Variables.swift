import Foundation

// MARK: - Variable Inspection

extension DebugService {
    /// Ispeziona le variabili locali del frame corrente.
    func inspectLocals() async -> [NativeVariable] {
        guard state.status == .paused else { return [] }

        if let lldbAdapter = adapter as? LLDBDAPDebugAdapter {
            return await lldbAdapter.inspectLocals()
        }
        return []
    }

    /// Ispeziona le variabili globali/statiche.
    func inspectGlobals() async -> [NativeVariable] {
        guard state.status == .paused else { return [] }

        if let lldbAdapter = adapter as? LLDBDAPDebugAdapter {
            return await lldbAdapter.inspectGlobals()
        }
        return []
    }

    /// Ispeziona gli argomenti del frame corrente.
    func inspectArguments() async -> [NativeVariable] {
        guard state.status == .paused else { return [] }

        if let lldbAdapter = adapter as? LLDBDAPDebugAdapter {
            return await lldbAdapter.inspectArguments()
        }
        return []
    }

    /// Ispeziona i registri CPU.
    func inspectRegisters() async -> [NativeVariable] {
        guard state.status == .paused else { return [] }

        if let lldbAdapter = adapter as? LLDBDAPDebugAdapter {
            return await lldbAdapter.inspectRegisters()
        }
        return []
    }

    /// Ispezione completa: variabili locali + argomenti + globali aggregate per scope.
    func inspectAllVariables() async -> [NativeVariable] {
        guard state.status == .paused else { return [] }

        if let lldbAdapter = adapter as? LLDBDAPDebugAdapter {
            async let locals = lldbAdapter.inspectLocals()
            async let arguments = lldbAdapter.inspectArguments()
            async let globals = lldbAdapter.inspectGlobals()
            return await locals + arguments + globals
        }
        return []
    }
}
