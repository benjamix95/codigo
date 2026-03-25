import Darwin
import Foundation

extension MCPSharedState {

    // MARK: - Public Locking APIs

    static func withCodeReviewFileLock<T>(
        _ body: () -> T
    ) -> T {
        withAdvisoryFileLock(
            label: "CodeReviewLock",
            lockURL: codeReviewDirectoryPath.appendingPathComponent(".lock"),
            createMode: 0o644,
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
            createMode: 0o644,
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
        // NSRecursiveLock gestisce reentrancy e serializzazione intra-processo.
        fallbackLock.lock()
        defer { fallbackLock.unlock() }

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

    private static let codeReviewFallbackLock = NSRecursiveLock()
    private static let bugHunterFallbackLock = NSRecursiveLock()

    /// Timeout massimo per acquisire il file lock cross-processo (secondi).
    static var advisoryLockTimeout: TimeInterval = 10

    static func acquireAdvisoryFileLock(
        lockURL: URL,
        createMode: mode_t,
        ensureLockDirectory: () -> Void
    ) -> AdvisoryFileLockResult {
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
            #if DEBUG
            NSLog("[CrossProcessLock] Timeout acquiring advisory lock at %@", lockURL.path)
            #endif
            return .fallback
        }

        return .fallback
    }
}
