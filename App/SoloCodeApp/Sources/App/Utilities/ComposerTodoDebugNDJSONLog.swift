import Foundation

/// Placeholder: optional NDJSON ingest was removed (hardcoded paths are unsafe). Hook here if product adds a real session sink.
enum ComposerTodoDebugNDJSONLog {
    static func append(
        hypothesisId _: String,
        location _: String,
        message _: String,
        runId _: String = "pre-fix",
        data _: [String: String] = [:]
    ) {}
}
