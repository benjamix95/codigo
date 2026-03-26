import Foundation

/// NDJSON sessione debug chat (path workspace). Non loggare segreti o PII.
enum AgentDebugSessionNDJSONLog {
    private static let queue = DispatchQueue(label: "solo.agent.debug.ndjson")
    private static let logPath = "/Users/benjaminstoica/SoloCode/.cursor/debug-fba6fd.log"
    private static let sessionId = "fba6fd"
    private static var throttleLast: [String: CFAbsoluteTime] = [:]
    private static let throttleLock = NSLock()

    static func appendThrottled(
        gateKey: String,
        minInterval: TimeInterval = 0.45,
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
        append(hypothesisId: hypothesisId, location: location, message: message, data: data)
    }

    static func append(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String] = [:]
    ) {
        queue.async {
            let payload: [String: Any] = [
                "sessionId": sessionId,
                "hypothesisId": hypothesisId,
                "location": location,
                "message": message,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "data": data,
            ]
            guard let json = try? JSONSerialization.data(withJSONObject: payload, options: []),
                  var line = String(data: json, encoding: .utf8)
            else { return }
            line.append("\n")
            let path = logPath
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: Data(line.utf8))
                return
            }
            let url = URL(fileURLWithPath: path)
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(Data(line.utf8))
        }
    }
}
