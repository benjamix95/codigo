import Foundation

func formatContextPercentLabel(_ pct: Double) -> String {
    let percentValue = min(100, max(0, pct * 100))
    if percentValue > 0 && percentValue < 10 {
        return String(format: "%.1f%%", percentValue)
    }
    return "\(Int(percentValue.rounded()))%"
}

func formatContextPercentHelpText(_ pct: Double) -> String {
    let percentValue = min(100, max(0, pct * 100))
    return "Window context: \(String(format: "%.1f", percentValue))% used"
}
