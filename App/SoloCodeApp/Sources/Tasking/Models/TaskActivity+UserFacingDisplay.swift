import Foundation

extension TaskActivity {
    /// Dettaglio mostrato in pannelli/timeline utente (redige elenchi tool interni).
    var userFacingDetail: String? {
        guard let d = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty else { return nil }
        return UserFacingToolTraceRedaction.redactedIfNeeded(d)
    }
}
