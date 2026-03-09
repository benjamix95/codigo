import Foundation

public actor ValidationMetricsStore {
    public static let shared = ValidationMetricsStore()

    private var runs: [ValidationRunResult] = []

    public func record(_ result: ValidationRunResult) {
        runs.append(result)
    }

    public func recent(limit: Int = 20) -> [ValidationRunResult] {
        Array(runs.suffix(limit))
    }
}
