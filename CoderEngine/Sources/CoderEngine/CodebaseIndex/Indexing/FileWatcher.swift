import Foundation

/// FSEvents-based file watcher for real-time codebase index updates.
/// Monitors workspace directories and triggers incremental re-indexing
/// when source files are modified, created, or deleted.
public actor FileWatcher {

    private let index: CodebaseIndex
    private let workspacePaths: [URL]

    private var stream: FSEventStreamRef?
    private var debounceTask: Task<Void, Never>?
    private var pendingPaths: Set<String> = []
    private var isRunning = false

    /// Directories to ignore at the event filter level
    private static let ignoredDirNames = ExcludedDirectories.defaultSet

    /// Source file extensions worth re-indexing
    private static let watchedExtensions: Set<String> = [
        "swift", "py", "js", "mjs", "cjs", "jsx", "ts", "mts", "cts", "tsx",
        "go", "rs", "java", "kt", "kts", "rb", "php", "cs", "c", "cpp", "h", "hpp",
        "m", "mm", "dart", "ex", "exs", "lua", "r", "scala", "hs", "zig",
    ]

    /// Debounce interval in seconds
    private static let debounceInterval: TimeInterval = 0.5

    public init(index: CodebaseIndex, workspacePaths: [URL]) {
        self.index = index
        self.workspacePaths = workspacePaths
    }

    // MARK: - Public API

    public func start() {
        guard !isRunning, !workspacePaths.isEmpty else { return }
        isRunning = true

        let paths = workspacePaths.map(\.path) as CFArray
        let callbackInfo = Unmanaged.passUnretained(self).toOpaque()

        var context = FSEventStreamContext(
            version: 0,
            info: callbackInfo,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let eventStream = FSEventStreamCreate(
            nil,
            fileWatcherCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.debounceInterval,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            isRunning = false
            return
        }

        stream = eventStream
        FSEventStreamSetDispatchQueue(eventStream, DispatchQueue(label: "com.codigo.filewatcher", qos: .utility))
        FSEventStreamStart(eventStream)
    }

    public func stop() {
        guard isRunning else { return }
        debounceTask?.cancel()
        debounceTask = nil

        if let eventStream = stream {
            FSEventStreamStop(eventStream)
            FSEventStreamInvalidate(eventStream)
            FSEventStreamRelease(eventStream)
            stream = nil
        }
        isRunning = false
        pendingPaths.removeAll()
    }

    // MARK: - Event Handling

    /// Called from the FSEvents callback (bridged via nonisolated helper)
    nonisolated func handleEvents(_ paths: [String]) {
        Task { await self.enqueueChanges(paths) }
    }

    private func enqueueChanges(_ paths: [String]) {
        let filtered = paths.filter { shouldWatch($0) }
        guard !filtered.isEmpty else { return }

        pendingPaths.formUnion(filtered)

        // Debounce: cancel previous task, start new one
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await flushPending()
        }
    }

    private func flushPending() async {
        let paths = pendingPaths
        pendingPaths.removeAll()

        for absolutePath in paths {
            let relPath =
                await index.canonicalRelativePath(for: absolutePath)
                ?? computeInternalRelativePath(for: absolutePath)
            guard let relPath else { continue }

            if FileManager.default.fileExists(atPath: absolutePath) {
                // File created or modified — re-index it
                await index.indexSingleFile(absolutePath: absolutePath, relativePath: relPath)
            } else {
                // File removed or renamed — remove stale index entries immediately.
                await index.removeSingleFile(absolutePath: absolutePath, relativePath: relPath)
            }
        }
    }

    private func computeInternalRelativePath(for absolutePath: String) -> String? {
        for ws in workspacePaths {
            let rootPath = ws.path
            if absolutePath == rootPath {
                return ws.lastPathComponent
            }
            let rootWithSlash = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            if absolutePath.hasPrefix(rootWithSlash) {
                let tail = String(absolutePath.dropFirst(rootWithSlash.count))
                let rootName = ws.lastPathComponent
                return tail.isEmpty ? rootName : "\(rootName)/\(tail)"
            }
        }
        return nil
    }

    // MARK: - Filtering

    private func shouldWatch(_ path: String) -> Bool {
        // Skip hidden files
        let filename = (path as NSString).lastPathComponent
        if filename.hasPrefix(".") { return false }

        // Skip ignored directories
        let components = path.components(separatedBy: "/")
        for component in components {
            if Self.ignoredDirNames.contains(component) { return false }
        }

        // Only watch source file extensions
        let ext = (path as NSString).pathExtension.lowercased()
        return Self.watchedExtensions.contains(ext)
    }
}

// MARK: - FSEvents Callback (C function)

private func fileWatcherCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()

    guard let cfPaths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] else { return }

    var changedPaths: [String] = []
    for i in 0..<numEvents {
        let flags = eventFlags[i]
        // Only care about file-level events (created, modified, removed, renamed)
        let relevant = flags & UInt32(
            kFSEventStreamEventFlagItemCreated |
            kFSEventStreamEventFlagItemModified |
            kFSEventStreamEventFlagItemRemoved |
            kFSEventStreamEventFlagItemRenamed
        )
        if relevant != 0, i < cfPaths.count {
            changedPaths.append(cfPaths[i])
        }
    }

    if !changedPaths.isEmpty {
        watcher.handleEvents(changedPaths)
    }
}
