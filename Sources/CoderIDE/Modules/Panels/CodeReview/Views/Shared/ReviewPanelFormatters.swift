import Foundation

// MARK: - Text Formatting

/// Format a file path to just its filename for compact display.
func reviewCompactFileName(_ path: String) -> String {
    (path as NSString).lastPathComponent
}

/// Format a date as relative time string.
func reviewRelativeTime(from date: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 60 { return "\(seconds)s ago" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    return "\(hours)h ago"
}

/// Format elapsed seconds as mm:ss.
func reviewFormatElapsed(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainder = seconds % 60
    return String(format: "%d:%02d", minutes, remainder)
}
