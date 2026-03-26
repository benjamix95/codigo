import Foundation

extension CodebaseIndex {

    /// Byte totali sotto `cacheDirectory` (es. `semantic.jsonl`, delta persistence).
    public nonisolated static func indexCacheStorageBytes(for workspacePaths: [URL]) -> UInt64 {
        guard !workspacePaths.isEmpty else { return 0 }
        let dir = cacheDirectory(for: workspacePaths)
        return directoryTreeSizeBytes(at: dir)
    }

    nonisolated private static func directoryTreeSizeBytes(at root: URL) -> UInt64 {
        guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: UInt64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let sz = values.fileSize
            else { continue }
            total += UInt64(sz)
        }
        return total
    }
}
