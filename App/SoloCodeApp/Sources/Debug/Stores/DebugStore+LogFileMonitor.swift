import Foundation
import os.log

private let logger = Logger(subsystem: "com.coderIDE", category: "DebugLogFileMonitor")

extension DebugStore {
    /// Default debug log path used by DebugLogServer.
    static var defaultDebugLogPath: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir
            .appendingPathComponent("com.solocode.debug", isDirectory: true)
            .appendingPathComponent("debug_log.jsonl")
    }

    /// Workspace-scoped debug log path.
    static func workspaceDebugLogPath(workspace: String, sessionId: String?) -> URL {
        let wsURL = URL(fileURLWithPath: workspace)
        let debugDir = wsURL.appendingPathComponent(".solocode/debug", isDirectory: true)
        let filename = sessionId.map { "session_\($0).jsonl" } ?? "debug_log.jsonl"
        return debugDir.appendingPathComponent(filename)
    }

    var activeDebugLogPath: URL {
        if let workspace = debugWorkspacePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspace.isEmpty {
            return Self.workspaceDebugLogPath(workspace: workspace, sessionId: activeDebugSessionId)
        }
        return Self.defaultDebugLogPath
    }

    func configureLogPersistence(workspacePath: String?, sessionId: String?) {
        let normalizedWorkspace = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSession = sessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextWorkspace = normalizedWorkspace?.isEmpty == false ? normalizedWorkspace : debugWorkspacePath
        let nextSession = normalizedSession?.isEmpty == false ? normalizedSession : activeDebugSessionId
        let previousPath = activeDebugLogPath

        debugWorkspacePath = nextWorkspace
        activeDebugSessionId = nextSession

        let nextPath = activeDebugLogPath
        guard previousPath != nextPath else { return }

        stopLogFileMonitor()
        runtimeLogs.removeAll()
        loadRuntimeLogsFromDisk(path: nextPath)
        startLogFileMonitor(path: nextPath)
        rescheduleDebugIdleWarningIfNeeded()
    }

    /// Loads runtime logs from a JSONL file on disk into the runtimeLogs array.
    func loadRuntimeLogsFromDisk(path: URL) {
        guard FileManager.default.fileExists(atPath: path.path) else {
            logger.debug("No debug log file at \(path.path)")
            return
        }

        do {
            let content = try String(contentsOf: path, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            var loadedCount = 0
            for line in lines {
                guard let data = line.data(using: .utf8) else { continue }
                if let entry = try? decoder.decode(DebugLogJSONLEntry.self, from: data),
                   entry.isRuntimeLike {
                    let existing = runtimeLogs.contains { $0.id == entry.id }
                    guard !existing else { continue }

                    addRuntimeLog(entry.runtimeLogEntry(defaultLocation: "disk"))
                    loadedCount += 1
                }
            }

            if loadedCount > 0 {
                logger.info("Loaded \(loadedCount) runtime log(s) from \(path.lastPathComponent)")
                addLog(
                    severity: .info,
                    source: "log_monitor",
                    message: "Loaded \(loadedCount) log entries from disk",
                    category: "system"
                )
            }
        } catch {
            logger.error("Failed to load debug logs from \(path.path): \(error.localizedDescription)")
        }
    }

    /// Starts monitoring a debug log file for new entries.
    func startLogFileMonitor(path: URL) {
        stopLogFileMonitor()

        let fileManager = FileManager.default
        let dir = path.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: path.path) {
            fileManager.createFile(atPath: path.path, contents: nil)
        }

        guard let fileHandle = try? FileHandle(forReadingFrom: path) else {
            logger.warning("Cannot open debug log file for monitoring: \(path.path)")
            return
        }

        // Seek to end — only watch for NEW entries
        fileHandle.seekToEndOfFile()

        let fd = fileHandle.fileDescriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            let newData = fileHandle.readDataToEndOfFile()
            guard !newData.isEmpty, let content = String(data: newData, encoding: .utf8) else { return }

            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for line in lines {
                guard let data = line.data(using: .utf8),
                      let entry = try? decoder.decode(DebugLogJSONLEntry.self, from: data),
                      entry.isRuntimeLike else { continue }
                let e = entry.runtimeLogEntry(defaultLocation: "live")
                guard self?.runtimeLogs.contains(where: { $0.id == e.id }) != true else { continue }
                self?.addRuntimeLog(e)
            }
        }

        source.setCancelHandler {
            fileHandle.closeFile()
        }

        source.resume()
        logFileMonitorSource = source
        logFileMonitorHandle = fileHandle
        logger.info("Started debug log file monitor at \(path.lastPathComponent)")
    }

    /// Stops the active log file monitor.
    func stopLogFileMonitor() {
        logFileMonitorSource?.cancel()
        logFileMonitorSource = nil
        logFileMonitorHandle = nil
    }
}

// MARK: - JSONL Entry Model

struct DebugLogJSONLEntry: Codable {
    let id: String?
    let timestamp: Date?
    let severity: String?
    let source: String?
    let message: String?
    let detail: String?
    let category: String?
    let data: [String: String]?
    let sessionId: String?
    let hypothesisId: String?
    let runId: String?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, severity, source, message, detail, category, data
        case sessionId = "session_id"
        case hypothesisId = "hypothesis_id"
        case runId = "run_id"
        case tags
    }

    var isRuntimeLike: Bool {
        if category == "runtime" || category == "instrumentation" {
            return true
        }
        if let hypothesisId, !hypothesisId.isEmpty {
            return true
        }
        return !(data ?? [:]).isEmpty
    }

    func runtimeLogEntry(defaultLocation: String) -> RuntimeLogEntry {
        RuntimeLogEntry(
            id: id ?? UUID().uuidString,
            timestamp: timestamp ?? Date(),
            location: source ?? defaultLocation,
            message: message ?? "",
            data: data ?? [:],
            sessionId: sessionId,
            runId: runId,
            hypothesisId: hypothesisId
        )
    }
}
