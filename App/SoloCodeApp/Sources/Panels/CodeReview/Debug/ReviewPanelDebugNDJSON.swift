import Foundation

/// Log di debug review panel → NDJSON locale + print (solo DEBUG). Non rimuovere finché il flusso review non è stabile.
/// Scrittura su file **in coda utility**: evita bloccare il main thread quando `emit` parte da body SwiftUI (`phase_ring`, ecc.).
enum ReviewPanelDebugNDJSON {
    static let sessionId = "7e54b6"
    private static let path = "/Users/benjaminstoica/SoloCode/.cursor/debug-7e54b6.log"
    private static let writeQueue = DispatchQueue(
        label: "com.solocode.reviewPanelDebugNDJSON",
        qos: .utility
    )
    private static var lastThrottledEmit: [String: TimeInterval] = [:]

    /// Evita NDJSON ingest decine di volte per frame SwiftUI.
    static func emitThrottled(
        key: String,
        minInterval: TimeInterval = 0.35,
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any]
    ) {
        #if DEBUG
        writeQueue.async {
            let now = Date().timeIntervalSince1970
            if let t = lastThrottledEmit[key], now - t < minInterval { return }
            lastThrottledEmit[key] = now
            writePayload(
                hypothesisId: hypothesisId,
                location: location,
                message: message,
                data: data
            )
        }
        #endif
    }

    static func emit(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any]
    ) {
        #if DEBUG
        writeQueue.async {
            writePayload(
                hypothesisId: hypothesisId,
                location: location,
                message: message,
                data: data
            )
        }
        #endif
    }

    private static func writePayload(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any]
    ) {
        let payload: [String: Any] = [
            "sessionId": sessionId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let json = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: json, encoding: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
        }
        let short = data.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("[ReviewPanelDEBUG] \(location) | \(message) | \(short)")
    }
}
