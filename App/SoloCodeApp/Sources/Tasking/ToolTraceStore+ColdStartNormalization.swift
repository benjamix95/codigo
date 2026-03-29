import Foundation

extension ToolTraceStore {
    func settledLoadedEventsForColdStart(_ events: [ToolTraceEvent]) -> [ToolTraceEvent] {
        events.map { event in
            var settled = event
            settled.isRunning = false
            return settled
        }
    }
}
