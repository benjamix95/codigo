import CoderEngine
import Foundation

/// Unisce gli esiti dei backend nativi (LLDB + ausiliari MCP).
enum DebugNativePipelineOutcomeMerge {
    /// Per `nativeStart` / `nativeStop` lo stato LLDB (`adapter` contiene "lldb") ha precedenza:
    /// evita di mascherare errori di sessione quando un backend ausiliario non espone `state`.
    static func mergedOutcome(
        context: DebugNativePipelineTaskContext,
        indexedOutcomes: [(index: Int, outcome: DebugNativeBackendOutcome)]
    ) -> DebugNativeBackendOutcome {
        let sorted = indexedOutcomes.sorted { $0.index < $1.index }
        var merged = DebugNativeBackendOutcome()
        for item in sorted {
            merged.logs.append(contentsOf: item.outcome.logs)
        }

        let sessionCritical = context.stage == .nativeStart || context.stage == .nativeStop
        if sessionCritical,
           let lldbState = sorted
           .compactMap(\.outcome.state)
           .first(where: { $0.adapter.lowercased().contains("lldb") })
        {
            merged.state = lldbState
            return merged
        }

        for item in sorted {
            if let state = item.outcome.state {
                if let existing = merged.state {
                    let existingErr = existing.status == .error
                    let incomingErr = state.status == .error
                    if existingErr, !incomingErr {
                        merged.state = state
                    } else if !existingErr, incomingErr {
                        // Mantieni lo stato non-errore già scelto.
                    } else {
                        merged.state = state
                    }
                } else {
                    merged.state = state
                }
            }
        }
        return merged
    }
}
