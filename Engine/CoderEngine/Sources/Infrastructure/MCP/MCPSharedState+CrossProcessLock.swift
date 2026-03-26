import Darwin
import Foundation

extension MCPSharedState {

    // MARK: - Public Locking APIs

    static func withTodosAdvisoryLock<T>(
        _ body: () -> T
    ) -> T {
        withAdvisoryFileLock(
            label: "TodosLock",
            lockURL: sharedDirectory.appendingPathComponent("todos.lock"),
            createMode: 0o600,
            fallbackLock: todosFallbackLock,
            ensureLockDirectory: {
                ensureDirectory()
            },
            body: body
        )
    }

    static func withCodeReviewFileLock<T>(
        _ body: () -> T
    ) -> T {
        withAdvisoryFileLock(
            label: "CodeReviewLock",
            lockURL: codeReviewDirectoryPath.appendingPathComponent(".lock"),
            createMode: 0o600,
            fallbackLock: codeReviewFallbackLock,
            ensureLockDirectory: {
                ensureDirectory()
                try? FileManager.default.createDirectory(
                    at: codeReviewDirectoryPath,
                    withIntermediateDirectories: true
                )
            },
            body: body
        )
    }


    static func withBugHunterAdvisoryLock<T>(
        _ body: () -> T
    ) -> T {
        withAdvisoryFileLock(
            label: "BugHunterLock",
            lockURL: bugHunterDirectoryPath.appendingPathComponent(".lock"),
            createMode: 0o600,
            fallbackLock: bugHunterFallbackLock,
            ensureLockDirectory: {
                ensureBugHunterDirectories()
            },
            body: body
        )
    }

    // MARK: - Core Lock Implementation

    /// Advisory file lock con fallback a NSRecursiveLock.
    ///
    /// Usa `flock()` per cross-process locking e `NSRecursiveLock`
    /// per la serializzazione intra-processo. La NSRecursiveLock
    /// gestisce nativamente la reentrancy senza bisogno di
    /// Thread.threadDictionary.
    static func withAdvisoryFileLock<T>(
        label: String,
        lockURL: URL,
        createMode: mode_t,
        fallbackLock: NSRecursiveLock,
        ensureLockDirectory: () -> Void,
        acquireLock: (() -> AdvisoryFileLockResult)? = nil,
        body: () -> T
    ) -> T {
        #if DEBUG
        let _lockEntryTime = CFAbsoluteTimeGetCurrent()
        #endif
        // NSRecursiveLock gestisce reentrancy e serializzazione intra-processo.
        fallbackLock.lock()
        defer {
            fallbackLock.unlock()
            #if DEBUG
            let elapsed = (CFAbsoluteTimeGetCurrent() - _lockEntryTime) * 1000
            if Thread.isMainThread && elapsed > 3 {
                NSLog("[CrossProcessLock] MAIN-STALL-TOTAL: label=%@ — %.0fms total (lock+body)", label, elapsed)
            }
            #endif
        }

        // On the main thread, skip the advisory file lock (flock) to avoid
        // blocking the UI with up to 10s spin-wait. The NSRecursiveLock
        // above is sufficient for intra-process serialization. Cross-process
        // safety is sacrificed on main-thread calls, but this is acceptable
        // because the MCP server (the other process) rarely holds the lock
        // for more than a few ms, and UI responsiveness is more important.
        if Thread.isMainThread {
            ensureLockDirectory()
            return body()
        }

        let result = acquireLock?() ?? acquireAdvisoryFileLock(
            lockURL: lockURL,
            createMode: createMode,
            ensureLockDirectory: ensureLockDirectory
        )

        switch result {
        case .locked(let descriptor):
            defer {
                flock(descriptor, LOCK_UN)
                close(descriptor)
            }
            return body()
        case .fallback:
            ensureLockDirectory()
            return body()
        }
    }

    // MARK: - Types

    enum AdvisoryFileLockResult {
        case locked(Int32)
        case fallback
    }

    // MARK: - Private

    private static let todosFallbackLock = NSRecursiveLock()
    private static let codeReviewFallbackLock = NSRecursiveLock()
    private static let bugHunterFallbackLock = NSRecursiveLock()

    /// Timeout thread-safe per acquisire il file lock cross-processo.
    private static let _lockTimeout = LockedValue<TimeInterval>(initial: 10)

    static var advisoryLockTimeout: TimeInterval {
        get { _lockTimeout.value }
        set { _lockTimeout.value = newValue }
    }

    /// Valore generico protetto da lock. Lock e stato co-locati.
    private final class LockedValue<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: T
        init(initial: T) { _value = initial }
        var value: T {
            get { lock.lock(); defer { lock.unlock() }; return _value }
            set { lock.lock(); defer { lock.unlock() }; _value = newValue }
        }
    }

    static func acquireAdvisoryFileLock(
        lockURL: URL,
        createMode: mode_t,
        ensureLockDirectory: () -> Void
    ) -> AdvisoryFileLockResult {
        let lockStartTime = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        if Thread.isMainThread {
            NSLog("[CrossProcessLock] WARNING: acquireAdvisoryFileLock called on main thread — this will block the UI for up to %.0fs. Move to background thread. caller=%@", advisoryLockTimeout, Thread.callStackSymbols.prefix(8).joined(separator: "\n"))
        }
        #endif
        let deadline = Date().addingTimeInterval(advisoryLockTimeout)

        for _ in 0..<2 {
            ensureLockDirectory()
            let descriptor = open(lockURL.path, O_CREAT | O_RDWR, createMode)
            guard descriptor >= 0 else {
                let err = errno
                if err == ENOENT { continue }
                return .fallback
            }

            while Date() < deadline {
                let lockResult = flock(descriptor, LOCK_EX | LOCK_NB)
                if lockResult == 0 {
                    let lockElapsed = (CFAbsoluteTimeGetCurrent() - lockStartTime) * 1000
                    if lockElapsed > 5 && Thread.isMainThread {
                        NSLog("[CrossProcessLock] MAIN-STALL: lock acquired after %.0fms on main thread", lockElapsed)
                    }
                    return .locked(descriptor)
                }
                let err = errno
                if err == EINTR { continue }
                if err == EWOULDBLOCK || err == EAGAIN {
                    Thread.sleep(forTimeInterval: 0.05)
                    continue
                }
                close(descriptor)
                if err == ENOENT { break }
                return .fallback
            }

            // Timeout raggiunto: rilascia il descriptor e usa fallback.
            close(descriptor)
            NSLog("[CrossProcessLock] WARNING: Timeout acquiring advisory lock at %@ — proceeding with intra-process lock only. Cross-process data corruption is possible.", lockURL.path)
            return .fallback
        }

        return .fallback
    }
}
