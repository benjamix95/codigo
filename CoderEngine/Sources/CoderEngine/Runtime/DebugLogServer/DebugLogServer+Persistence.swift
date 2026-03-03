import Foundation

public extension DebugLogServer {
    func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        if let data = try? JSONEncoder().encode(entry),
           let line = String(data: data, encoding: .utf8) {
            appendLineToDisk(line)
        }
        appendsSinceLastSizeCheck += 1
        if appendsSinceLastSizeCheck >= 200 {
            appendsSinceLastSizeCheck = 0
            rotateFileIfNeeded()
        }
    }

    func appendLineToDisk(_ line: String) {
        let lineData = (line + "\n").data(using: .utf8) ?? Data()
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            _ = FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: logFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
            return
        } catch {
            persistToDisk()
        }
    }

    func rotateFileIfNeeded() {
        guard currentLogFileSize() > Self.maxFileSize else { return }
        persistToDisk()
        guard currentLogFileSize() > Self.maxFileSize else { return }
        trimEntriesToFitFileSize(Self.maxFileSize)
        persistToDisk()
    }

    func currentLogFileSize() -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let fileSize = attrs[.size] as? UInt64 else {
            return 0
        }
        return fileSize
    }

    func trimEntriesToFitFileSize(_ maxBytes: UInt64) {
        guard !entries.isEmpty else { return }
        let maxBytesInt = Int(min(maxBytes, UInt64(Int.max)))
        var kept: [LogEntry] = []
        var usedBytes = 0

        for entry in entries.reversed() {
            guard let encoded = try? JSONEncoder().encode(entry) else { continue }
            let lineBytes = encoded.count + 1 // newline
            if !kept.isEmpty, usedBytes + lineBytes > maxBytesInt {
                break
            }
            if kept.isEmpty, lineBytes > maxBytesInt {
                kept.append(entry)
                break
            }
            kept.append(entry)
            usedBytes += lineBytes
        }

        entries = kept.reversed()
    }

    func persistToDisk() {
        let lines = entries.compactMap { entry -> String? in
            guard let data = try? JSONEncoder().encode(entry) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        try? lines.joined(separator: "\n").write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    func ensureLoadedFromDiskIfNeeded() {
        guard !hasLoadedFromDisk else { return }
        loadFromDisk()
    }

    func loadFromDisk() {
        hasLoadedFromDisk = true
        entries.removeAll(keepingCapacity: true)
        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        for line in content.components(separatedBy: "\n") where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(LogEntry.self, from: data) else { continue }
            entries.append(entry)
        }

        let needsTrim = entries.count > maxEntries
        if needsTrim {
            entries.removeFirst(entries.count - maxEntries)
        }
        if needsTrim || currentLogFileSize() > Self.maxFileSize {
            trimEntriesToFitFileSize(Self.maxFileSize)
            persistToDisk()
        }
    }
}
