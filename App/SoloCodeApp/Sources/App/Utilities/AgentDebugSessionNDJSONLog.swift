import Foundation

/// Placeholder: optional NDJSON ingest was removed (hardcoded paths are unsafe). Hook here if product adds a real session sink.
enum AgentDebugSessionNDJSONLog {
    static func appendThrottled(
        gateKey _: String,
        minInterval _: TimeInterval = 0.45,
        hypothesisId _: String,
        location _: String,
        message _: String,
        data _: [String: String] = [:]
    ) {}

    static func append(
        hypothesisId _: String,
        location _: String,
        message _: String,
        data _: [String: String] = [:]
    ) {}
}
