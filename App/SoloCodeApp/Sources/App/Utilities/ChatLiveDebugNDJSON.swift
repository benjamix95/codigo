import Foundation

enum ChatLiveDebugNDJSON {
    private static let queue = DispatchQueue(label: "solo.chat.live.ndjson")
    private static let mirrorPath = "/Users/benjaminstoica/SoloCode/.cursor/chat-live-debug.ndjson"
    private static var throttleLast: [String: CFAbsoluteTime] = [:]
    private static let throttleLock = NSLock()

    static func appendThrottled(
        gateKey: String,
        minInterval: TimeInterval = 0.35,
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
        append(message: message, data: data)
    }

    static func append(
        message: String,
        data: [String: String] = [:]
    ) {
        queue.async {
            let payload: [String: Any] = [
                "message": message,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "data": data,
            ]
            guard let json = try? JSONSerialization.data(withJSONObject: payload, options: []),
                  var line = String(data: json, encoding: .utf8)
            else { return }
            line.append("\n")
            Self.appendData(Data(line.utf8), toPath: mirrorPath)
        }
    }

    private static func appendData(_ data: Data, toPath path: String) {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: directory, isDirectory: true),
            withIntermediateDirectories: true
        )
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
