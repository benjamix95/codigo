import Combine
import Foundation

extension DebugStore {
    private static let streamLogCapacity = 500

    func setupStreamLogRelay() {
        streamLogCancellable = DebugStreamLogger.logRelay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                let entry = DebugStreamLogEntry(
                    timestamp: event.timestamp,
                    message: event.message
                )
                self.streamLogs.append(entry)
                self.streamLogNewCount += 1
                if self.streamLogs.count > Self.streamLogCapacity {
                    self.streamLogs.removeFirst(self.streamLogs.count - Self.streamLogCapacity)
                }
            }
    }

    /// Clears both the in-memory stream logs and the on-disk log file.
    func clearStreamLogs() {
        streamLogs.removeAll()
        streamLogNewCount = 0
        DebugStreamLogger.clearLogFile()
    }
}
