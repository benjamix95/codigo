import Foundation

@MainActor
final class WindowLaunchIntentStore {
    static let shared = WindowLaunchIntentStore()

    private var pendingCleanWindows = 0

    private init() {}

    func enqueueCleanWindowIntent() {
        pendingCleanWindows += 1
    }

    func consumeCleanWindowIntent() -> Bool {
        guard pendingCleanWindows > 0 else { return false }
        pendingCleanWindows -= 1
        return true
    }
}
