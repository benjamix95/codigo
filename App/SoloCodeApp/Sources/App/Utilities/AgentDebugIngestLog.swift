import Foundation

/// NDJSON append per la sessione debug agent (path e ID allineati al collector Cursor).
enum AgentDebugIngestLog {
    static let sessionId = "773578"
    private static let logPath = "/Users/benjaminstoica/SoloCode/.cursor/debug-\(sessionId).log"
    private static let queue = DispatchQueue(label: "solo.agent.debug.ingest.773578")

    static func append(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String] = [:],
        runId: String? = nil
    ) {
        queue.async {
            var payload: [String: Any] = [
                "sessionId": sessionId,
                "hypothesisId": hypothesisId,
                "location": location,
                "message": message,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "data": data,
            ]
            if let runId { payload["runId"] = runId }
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
}
