import Combine
import Foundation

enum DebugStreamLogger {

    // MARK: - Log Event Relay

    struct LogEvent {
        let timestamp: Date
        let message: String
    }

    static let logRelay = PassthroughSubject<LogEvent, Never>()

    // MARK: - File Paths

    static let logDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("SoloCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let logFileURL: URL = {
        logDirectory.appendingPathComponent("debug-stream.log")
    }()

    // MARK: - Sanitization

    /// Recursively convert any non-JSON-serializable Swift value to a String
    /// so JSONSerialization never throws an ObjC NSInvalidArgumentException.
    private static func sanitize(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            return dict.mapValues { sanitize($0) }
        case let arr as [Any]:
            return arr.map { sanitize($0) }
        case let str as String:
            return str
        case let num as NSNumber:
            return num
        case let b as Bool:
            return b
        default:
            return String(describing: value)
        }
    }

    // MARK: - Logging

    static func log(_ location: String, _ message: String, _ data: [String: Any] = [:], hyp: String = "") {
        let now = Date()
        var p: [String: Any] = [
            "location": location, "message": message,
            "timestamp": now.timeIntervalSince1970 * 1000, "hypothesisId": hyp,
        ]
        if !data.isEmpty { p["data"] = sanitize(data) }
        guard let d = try? JSONSerialization.data(withJSONObject: p),
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

    // MARK: - Clear

    /// Truncates the on-disk log file to zero bytes.
    static func clearLogFile() {
        let url = logFileURL
        try? "".write(to: url, atomically: false, encoding: .utf8)
    }
}
