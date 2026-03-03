import Foundation

// #region agent log
enum DebugSessionLog {
    private static let logPath = "/Users/benjaminstoica/codigo/.cursor/debug-2e439e.log"

    static func log(location: String, message: String, data: [String: Any] = [:], hypothesisId: String = "") {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let dataJson: String
        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let str = String(data: jsonData, encoding: .utf8) {
            dataJson = str
        } else {
            dataJson = "{}"
        }
        let line = "{\"sessionId\":\"2e439e\",\"location\":\"\(location.replacingOccurrences(of: "\"", with: "\\\""))\",\"message\":\"\(message.replacingOccurrences(of: "\"", with: "\\\""))\",\"data\":\(dataJson),\"timestamp\":\(timestamp),\"hypothesisId\":\"\(hypothesisId)\"}\n"
        guard let lineData = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: logPath)
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
        }
        if let handle = try? FileHandle(forUpdating: url) {
            handle.seekToEndOfFile()
            handle.write(lineData)
            try? handle.close()
        }
    }
}
// #endregion
