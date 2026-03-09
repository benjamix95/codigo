import Foundation

public enum ValidationReportFormatter {
    public static func summary(for result: ValidationRunResult) -> String {
        let stages = result.stageResults.map { stage in
            "[\((stage.status.rawValue).uppercased())] \(stage.stage.rawValue): \(stage.summary)"
        }.joined(separator: "\n")
        return """
        Validation run: \(result.runId)
        Profile: \(result.profile.rawValue)
        Status: \(result.status.rawValue)
        Files: \(result.touchedFiles.joined(separator: ", "))
        Duration: \(result.durationMs)ms
        \(stages)
        """
    }
}
