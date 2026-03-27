import Foundation

private enum ToolTraceDiskBuffer {
    static var bufferedDataByURL: [URL: Data] = [:]
    static var scheduledFlushURLs: Set<URL> = []
    static let flushDelayNanoseconds: UInt64 = 40_000_000
    static let immediateFlushBytes = 16_384
}

extension ToolTraceStore {
    nonisolated static func queueBufferedDiskAppend(_ data: Data, url: URL) {
        var line = data
        line.append(0x0A)
        diskQueue.async {
            enqueueBufferedDiskAppendOnDiskQueue(line, url: url)
        }
    }

    static func flushAllBufferedDiskAppends() {
        let urls = Array(ToolTraceDiskBuffer.bufferedDataByURL.keys)
        ToolTraceDiskBuffer.scheduledFlushURLs.removeAll()
        for url in urls {
            flushBufferedDiskAppendsOnDiskQueue(for: url)
        }
    }

    private static func enqueueBufferedDiskAppendOnDiskQueue(_ line: Data, url: URL) {
        var buffer = ToolTraceDiskBuffer.bufferedDataByURL[url] ?? Data()
        buffer.append(line)
        ToolTraceDiskBuffer.bufferedDataByURL[url] = buffer

        if buffer.count >= ToolTraceDiskBuffer.immediateFlushBytes {
            ToolTraceDiskBuffer.scheduledFlushURLs.remove(url)
            flushBufferedDiskAppendsOnDiskQueue(for: url)
            return
        }

        if ToolTraceDiskBuffer.scheduledFlushURLs.insert(url).inserted {
            diskQueue.asyncAfter(deadline: .now() + .nanoseconds(Int(ToolTraceDiskBuffer.flushDelayNanoseconds))) {
                flushBufferedDiskAppendsOnDiskQueue(for: url)
            }
        }
    }

    private static func flushBufferedDiskAppendsOnDiskQueue(for url: URL) {
        ToolTraceDiskBuffer.scheduledFlushURLs.remove(url)
        let data = ToolTraceDiskBuffer.bufferedDataByURL.removeValue(forKey: url)
        guard let data, !data.isEmpty else { return }
        appendBufferedDataToDisk(data, url: url)
    }

    nonisolated private static func appendBufferedDataToDisk(_ data: Data, url: URL) {
        ensureTraceFileExistsOnDisk(at: url)
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
    }
}
