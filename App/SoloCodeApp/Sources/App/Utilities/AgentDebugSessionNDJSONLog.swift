import CryptoKit
import Foundation

/// NDJSON diagnostica agent (Application Support, bucket per workspace). Non loggare segreti o PII.
enum AgentDebugSessionNDJSONLog {
    private static let queue = DispatchQueue(label: "solo.agent.debug.ndjson")
    private static var logFileURL: URL?
    private static let cursorDebugSessionId = "2fa5b8"
    private static let cursorDebugRunId = "pre-fix"
    private static var sessionId = cursorDebugSessionId
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
            sessionId = cursorDebugSessionId
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

    /// Se `configure` non è ancora stato chiamato (folder vuoti), scrive comunque qui.
    private static func fallbackLogURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base
            .appendingPathComponent("SoloCode", isDirectory: true)
            .appendingPathComponent("DebugNDJSON", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chat-send-trace.ndjson", isDirectory: false)
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

    /// Copia mirror nel repo per la sessione Cursor debug corrente.
    private static let cursorWorkspaceMirrorPath =
        "/Users/benjaminstoica/SoloCode/.cursor/debug-2fa5b8.log"

    static func append(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String] = [:]
    ) {
        queue.async {
            let primaryURL = logFileURL ?? fallbackLogURL()
            let sid = sessionId
            let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
            let payload: [String: Any] = [
                "id": "log_\(timestamp)_\(UUID().uuidString)",
                "sessionId": sid,
                "runId": cursorDebugRunId,
                "hypothesisId": hypothesisId,
                "location": location,
                "message": message,
                "timestamp": timestamp,
                "data": data,
            ]
            guard let json = try? JSONSerialization.data(withJSONObject: payload, options: []),
                  var line = String(data: json, encoding: .utf8)
            else { return }
            line.append("\n")
            let lineData = Data(line.utf8)
            if let primaryURL {
                Self.appendData(lineData, toPath: primaryURL.path)
            }
            Self.appendData(lineData, toPath: cursorWorkspaceMirrorPath)
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
