import Foundation

extension TerminalActivitySession {
    static func normalizedRunningState(
        status rawStatus: String?,
        fallbackIsRunning: Bool
    ) -> Bool {
        let status = rawStatus?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        switch status {
        case "completed", "failed", "error", "fatal", "success", "done", "ok",
             "cancelled", "canceled", "aborted", "terminated", "timeout", "timed_out":
            return false
        case "started", "running", "in_progress":
            return true
        default:
            return fallbackIsRunning
        }
    }
}
