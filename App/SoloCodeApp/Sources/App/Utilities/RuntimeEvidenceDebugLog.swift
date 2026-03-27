import Foundation

enum RuntimeEvidenceDebugLog {
    private static let sessionId = "79c50e"
    private static let runId = "pre-fix"
    private static let logPath = "/Users/benjaminstoica/SoloCode/.cursor/debug-79c50e.log"
    private static let queue = DispatchQueue(label: "solo.runtime.evidence.debug")
    private static var throttleLast: [String: CFAbsoluteTime] = [:]
    private static let throttleLock = NSLock()

    static func appendThrottled(
        gateKey: String,
        minInterval: TimeInterval = 0.5,
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String] = [:]
    ) {
        throttleLock.lock()
        let now = CFAbsoluteTimeGetCurrent()
        if now - (throttleLast[gateKey] ?? 0) < minInterval {
            throttleLock.unlock()
            return
        }
        throttleLast[gateKey] = now
        throttleLock.unlock()
        append(
            hypothesisId: hypothesisId,
            location: location,
            message: message,
            data: data
        )
    }

    static func append(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String] = [:]
    ) {
        queue.async {
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let payload: [String: Any] = [
                "sessionId": sessionId,
                "runId": runId,
                "id": "log_\(timestamp)_\(UUID().uuidString)",
                "timestamp": timestamp,
                "location": location,
                "message": message,
                "hypothesisId": hypothesisId,
                "data": data,
            ]
            guard let json = try? JSONSerialization.data(withJSONObject: payload, options: []),
                  var line = String(data: json, encoding: .utf8)
            else { return }
            line.append("\n")
            appendData(Data(line.utf8), toPath: logPath)
        }
    }

    private static func appendData(_ data: Data, toPath path: String) {
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: data)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        handle.write(data)
    }
}
