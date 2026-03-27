import Foundation

func shouldPreserveSnapshotAgainstTransientEmptyStore(
    freshConversationId: UUID,
    freshMessageCount: Int,
    previousSnapshotConversationId: UUID?,
    previousSnapshotMessageCount: Int,
    chromeBusy: Bool,
    lastBusyAt: Date?,
    now: Date = .now,
    idleGraceWindow: TimeInterval = 0.75
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
    return now.timeIntervalSince(lastBusyAt) <= idleGraceWindow
}
