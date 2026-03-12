import Foundation

public extension SessionConfig {
    var reviewCommandPayload: [String: String] {
        [
            "max_workers": String(maxWorkers),
            "max_rounds": String(maxRounds),
            "analysis_backend": analysisBackend,
            "execution_backend": executionBackend,
            "analysis_only": analysisOnly ? "true" : "false",
        ]
    }
}
