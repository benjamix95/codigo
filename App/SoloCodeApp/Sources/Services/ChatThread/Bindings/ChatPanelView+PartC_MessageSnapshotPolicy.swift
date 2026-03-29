import Foundation

func shouldPreserveSnapshotAgainstTransientEmptyStore(
    freshConversationId: UUID,
    freshMessageCount: Int,
    previousSnapshotConversationId: UUID?,
    previousSnapshotMessageCount: Int,
    chromeBusy: Bool,
    lastBusyAt: Date?,
    now: Date = .now,
    /// Oltre al flip `isLoading=false`, lo store puo' rimanere incoerente (es. errore stream,
    /// round-trip Rust ritardato) per **decine di secondi** prima che i messaggi riappaiano senza
    /// resize—evidenza sessione `2fa5b8` (~22s tra snap con 2 msg e store vuoto).
    idleGraceWindow: TimeInterval = 30,
    partialReductionGraceWindow: TimeInterval = 0.75
) -> Bool {
    guard previousSnapshotConversationId == freshConversationId,
          previousSnapshotMessageCount > 0,
          freshMessageCount < previousSnapshotMessageCount
    else {
        return false
    }

    if chromeBusy {
        return true
    }

    guard let lastBusyAt else { return false }
    let effectiveGraceWindow = freshMessageCount == 0
        ? idleGraceWindow
        : partialReductionGraceWindow
    return now.timeIntervalSince(lastBusyAt) <= effectiveGraceWindow
}
