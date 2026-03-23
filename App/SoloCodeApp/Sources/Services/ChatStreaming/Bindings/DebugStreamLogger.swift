import Combine
import Foundation

enum DebugStreamLogger {
    static let logDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("SoloCode/DebugStream", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var logFileURL: URL { logDirectory.appendingPathComponent("debug-stream.log") }

    struct LogEvent: Sendable {
        let timestamp: Date
        let message: String
    }

    static let logRelay = PassthroughSubject<LogEvent, Never>()

    static func log(_ location: String, _ message: String, _ data: [String: Any] = [:], hyp: String = "") {
        let now = Date()
        var p: [String: Any] = [
            "sessionId": "17ea27", "location": location, "message": message,
            "timestamp": now.timeIntervalSince1970 * 1000, "hypothesisId": hyp, "runId": "stream1",
        ]
        if !data.isEmpty { p["data"] = jsonSafe(data) }
        guard JSONSerialization.isValidJSONObject(p),
              let d = try? JSONSerialization.data(withJSONObject: p),
              let line = String(data: d, encoding: .utf8)
        else { return }
        let url = logFileURL
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile()
            fh.write((line + "\n").data(using: .utf8)!)
            fh.closeFile()
        } else {
            try? (line + "\n").write(to: url, atomically: false, encoding: .utf8)
        }
        logRelay.send(LogEvent(timestamp: now, message: message))
    }

    static func clearLogFile() {
        try? "".write(to: logFileURL, atomically: false, encoding: .utf8)
    }

    private static func jsonSafe(_ value: Any) -> Any {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n
        case let dict as [String: Any]: return dict.mapValues { jsonSafe($0) }
        case let arr as [Any]: return arr.map { jsonSafe($0) }
        case is NSNull: return NSNull()
        default: return String(describing: value)
        }
    }
}
