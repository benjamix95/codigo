import Foundation

/// NDJSON per capire dove il flusso Plan si ferma (prompt bridge Rust vuoti, abort prefight). Sessione Cursor 773578.
enum PlanFlowDebugNDJSONLog {
    private static let sessionId = "773578"
    private static let logPath = "/Users/benjaminstoica/SoloCode/.cursor/debug-\(sessionId).log"
    private static let queue = DispatchQueue(label: "solo.planflow.debug.ndjson")

    // #region agent log
    static func append(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String] = [:],
        runId: String = "plan-trace"
    ) {
        queue.async {
            let payload: [String: Any] = [
                "sessionId": sessionId,
                "runId": runId,
                "hypothesisId": hypothesisId,
                "location": location,
                "message": message,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "data": data,
            ]
            guard let json = try? JSONSerialization.data(withJSONObject: payload),
                  var line = String(data: json, encoding: .utf8)
            else { return }
            line.append("\n")
            let url = URL(fileURLWithPath: logPath)
            if !FileManager.default.fileExists(atPath: logPath) {
                FileManager.default.createFile(atPath: logPath, contents: Data(line.utf8))
                return
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(Data(line.utf8))
        }
    }
    // #endregion
}
