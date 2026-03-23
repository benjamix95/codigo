import Foundation

public struct FileWatcherMetrics: Sendable {
    public let acceptedPaths: Int
    public let droppedHiddenPaths: Int
    public let droppedIgnoredDirectories: Int
    public let droppedByExtension: Int
}

/// FSEvents-based file watcher for real-time codebase index updates.
/// Monitors workspace directories and triggers incremental re-indexing
/// when source files are modified, created, or deleted.
public actor FileWatcher {

    private let index: CodebaseIndex
    private let workspacePaths: [URL]

    private var stream: FSEventStreamRef?
    private var debounceTasksByPath: [String: Task<Void, Never>] = [:]
    private var isRunning = false

    private var acceptedPathsCount = 0
    private var droppedHiddenPathsCount = 0
    private var droppedIgnoredDirectoriesCount = 0
    private var droppedByExtensionCount = 0

    /// Directories to ignore at the event filter level
    private static let ignoredDirNames = ExcludedDirectories.defaultSet

    /// Source file extensions worth re-indexing
    private static let watchedExtensions: Set<String> = CodebaseIndex.indexableExtensions

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
        FSEventStreamSetDispatchQueue(eventStream, DispatchQueue(label: "com.solocode.filewatcher", qos: .utility))
        if !FSEventStreamStart(eventStream) {
            FSEventStreamInvalidate(eventStream)
            FSEventStreamRelease(eventStream)
            stream = nil
            isRunning = false
        }
    }

    public func stop() {
        guard isRunning else { return }
        cancelAllDebounceTasks()

        if let eventStream = stream {
            FSEventStreamStop(eventStream)
            FSEventStreamInvalidate(eventStream)
            FSEventStreamRelease(eventStream)
            stream = nil
        }
        isRunning = false
    }

    public func metrics() -> FileWatcherMetrics {
        FileWatcherMetrics(
            acceptedPaths: acceptedPathsCount,
            droppedHiddenPaths: droppedHiddenPathsCount,
            droppedIgnoredDirectories: droppedIgnoredDirectoriesCount,
            droppedByExtension: droppedByExtensionCount
        )
    }

    func ingestPathsForTesting(_ paths: [String]) {
        for path in paths {
            switch watchDecision(for: path) {
            case .watch:
                acceptedPathsCount += 1
            case .dropHidden:
                droppedHiddenPathsCount += 1
            case .dropIgnoredDirectory:
                droppedIgnoredDirectoriesCount += 1
            case .dropByExtension:
                droppedByExtensionCount += 1
            }
        }
    }

    // MARK: - Event Handling

    /// Called from the FSEvents callback (bridged via nonisolated helper)
    nonisolated func handleEvents(_ paths: [String]) {
        Task { await self.enqueueChanges(paths) }
    }

    func enqueueChanges(_ paths: [String]) {
        guard isRunning else { return }
        for path in paths {
            switch watchDecision(for: path) {
            case .watch:
                acceptedPathsCount += 1
                scheduleDebouncedPath(path)
            case .dropHidden:
                droppedHiddenPathsCount += 1
            case .dropIgnoredDirectory:
                droppedIgnoredDirectoriesCount += 1
            case .dropByExtension:
                droppedByExtensionCount += 1
            }
        }
    }

    private func scheduleDebouncedPath(_ absolutePath: String) {
        debounceTasksByPath[absolutePath]?.cancel()
        debounceTasksByPath[absolutePath] = Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await flushPath(absolutePath)
        }
    }

    private func flushPath(_ absolutePath: String) async {
        debounceTasksByPath[absolutePath] = nil
        guard isRunning else { return }

        let relPath =
            await index.canonicalRelativePath(for: absolutePath)
            ?? computeInternalRelativePath(for: absolutePath)
        guard let relPath else { return }

        if FileManager.default.fileExists(atPath: absolutePath) {
            await index.indexSingleFile(absolutePath: absolutePath, relativePath: relPath)
        } else {
            await index.removeSingleFile(absolutePath: absolutePath, relativePath: relPath)
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

    private func cancelAllDebounceTasks() {
        for task in debounceTasksByPath.values {
            task.cancel()
        }
        debounceTasksByPath.removeAll(keepingCapacity: true)
    }

    // MARK: - Filtering

    private enum WatchDecision {
        case watch
        case dropHidden
        case dropIgnoredDirectory
        case dropByExtension
    }

    private func watchDecision(for path: String) -> WatchDecision {
        let filename = (path as NSString).lastPathComponent
        if filename.hasPrefix(".") {
            return .dropHidden
        }

        let components = path.components(separatedBy: "/")
        for component in components {
            if component.hasPrefix(".") {
                return .dropHidden
            }
            if Self.ignoredDirNames.contains(component) {
                return .dropIgnoredDirectory
            }
        }

        let ext = (path as NSString).pathExtension.lowercased()
        if !Self.watchedExtensions.contains(ext) {
            return .dropByExtension
        }
        return .watch
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
