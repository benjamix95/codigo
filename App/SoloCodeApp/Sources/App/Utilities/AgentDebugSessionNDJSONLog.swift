import CryptoKit
import Foundation

/// NDJSON diagnostica agent (Application Support, bucket per workspace). Non loggare segreti o PII.
enum AgentDebugSessionNDJSONLog {
    private static let queue = DispatchQueue(label: "solo.agent.debug.ndjson")
    private static var logFileURL: URL?
    private static var sessionId = UUID().uuidString
    private static var throttleLast: [String: CFAbsoluteTime] = [:]
    private static let throttleLock = NSLock()

    /// Aggiorna directory di log in base alle radici workspace (path ordinati + hash).
    @MainActor
    static func configure(workspaceRoots: [String]) {
        let sorted = workspaceRoots
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { Self.canonicalFilePath($0) }
            .sorted()
        queue.sync {
            guard !sorted.isEmpty,
                  let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            else {
                logFileURL = nil
                return
            }
            let fingerprint = sha256Hex(sorted.joined(separator: "\u{1e}"))
            sessionId = UUID().uuidString
            let dir = base
                .appendingPathComponent("SoloCode", isDirectory: true)
                .appendingPathComponent("AgentDebugNDJSON", isDirectory: true)
                .appendingPathComponent(fingerprint, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            logFileURL = dir.appendingPathComponent("session-\(sessionId).ndjson", isDirectory: false)
        }
    }

    /// Allineamento al fingerprint Rust (`canonicalize`): stesso workspace → stesso bucket NDJSON.
    private static func canonicalFilePath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        return url.path
    }

    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

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
            guard let url = logFileURL else { return }
            let sid = sessionId
            let payload: [String: Any] = [
                "sessionId": sid,
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
            let path = url.path
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: Data(line.utf8))
                return
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(Data(line.utf8))
        }
    }
}
