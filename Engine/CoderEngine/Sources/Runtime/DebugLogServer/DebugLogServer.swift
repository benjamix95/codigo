import Foundation

public actor DebugLogServer {
    /// All in-memory entries loaded from disk.
    var entries: [LogEntry] = []

    /// Log file destination in cache dir.
    let logFileURL: URL

    /// Maximum in-memory entries.
    let maxEntries: Int

    /// Current active session ID.
    var activeSessionId: String?

    /// Ensure a single load pass before first query/write.
    var hasLoadedFromDisk = false

    static let maxFileSize: UInt64 = 5 * 1024 * 1024 // 5 MB
    var appendsSinceLastSizeCheck: Int = 0

    public init(maxEntries: Int = 5000) {
        self.maxEntries = maxEntries
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            self.logFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("debug_log.jsonl")
            return
        }
        let debugDir = cacheDir.appendingPathComponent("com.codigo.debug", isDirectory: true)
        try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)
        self.logFileURL = debugDir.appendingPathComponent("debug_log.jsonl")
    }
}
