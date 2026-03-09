import Darwin
import Foundation

extension MCPSharedState {
    enum AdvisoryFileLockAcquisition {
        case locked(Int32)
        case fallback(Int32)
    }

    private static let codeReviewFallbackLock = NSRecursiveLock()
    private static let bugHunterFallbackLock = NSRecursiveLock()

    static func withCodeReviewFileLock<T>(
        _ body: () -> T
    ) -> T {
        withAdvisoryFileLock(
            label: "CodeReviewLock",
            lockURL: codeReviewDirectoryPath.appendingPathComponent(".lock"),
            createMode: S_IRUSR | S_IWUSR,
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

    static func withAdvisoryFileLock<T>(
        label: String,
        lockURL: URL,
        createMode: mode_t,
        fallbackLock: NSRecursiveLock,
        ensureLockDirectory: () -> Void,
        acquireLock: (() -> AdvisoryFileLockAcquisition)? = nil,
        body: () -> T
    ) -> T {
        let acquisition = acquireLock?() ?? acquireAdvisoryFileLock(
            lockURL: lockURL,
            createMode: createMode,
            ensureLockDirectory: ensureLockDirectory
        )

        switch acquisition {
        case .locked(let descriptor):
            defer { close(descriptor) }
            defer { flock(descriptor, LOCK_UN) }
            return body()
        case .fallback(let err):
            print(
                "[MCPSharedState] ⚠️ \(label): fallback al lock locale per \(lockURL.path), errno: \(err)"
            )
            ensureLockDirectory()
            fallbackLock.lock()
            defer { fallbackLock.unlock() }
            return body()
        }
    }

    static func acquireAdvisoryFileLock(
        lockURL: URL,
        createMode: mode_t,
        ensureLockDirectory: () -> Void
    ) -> AdvisoryFileLockAcquisition {
        var lastErr: Int32 = 0

        for _ in 0..<2 {
            ensureLockDirectory()
            let descriptor = open(lockURL.path, O_CREAT | O_RDWR, createMode)
            guard descriptor >= 0 else {
                lastErr = errno
                if lastErr == ENOENT {
                    continue
                }
                return .fallback(lastErr)
            }

            while true {
                let lockResult = flock(descriptor, LOCK_EX)
                if lockResult == 0 {
                    return .locked(descriptor)
                }

                lastErr = errno
                if lastErr == EINTR {
                    continue
                }
                close(descriptor)
                if lastErr == ENOENT {
                    break
                }
                return .fallback(lastErr)
            }
        }

        return .fallback(lastErr)
    }
}
